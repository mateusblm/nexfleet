[CmdletBinding()]
param(
    [ValidateRange(1, 8760)][int]$MaxRpoHours = 24,
    [ValidateRange(1, 8760)][int]$MaxRtoHours = 4
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workDirectory = [IO.Path]::GetFullPath((Join-Path $tempRoot "nexfleet-cq10-$([guid]::NewGuid().ToString('N'))"))
if (-not $workDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
    -not ([IO.Path]::GetFileName($workDirectory)).StartsWith('nexfleet-cq10-')) {
    throw 'Diretorio temporario de recuperacao invalido.'
}
$backupDirectory = Join-Path $workDirectory 'backups'
$activeContainers = [Collections.Generic.List[string]]::new()

try {
    [void](New-Item -ItemType Directory -Path $workDirectory)
    & (Join-Path $PSScriptRoot 'Backup-Databases.ps1') -OutputDirectory $backupDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar os backups do ensaio CQ10.' }

    $manifestPath = Join-Path $backupDirectory 'manifest.json'
    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $createdUtc = [DateTime]::Parse(
        [string]$manifest.createdUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind)
    $rpoAge = [DateTime]::UtcNow - $createdUtc.ToUniversalTime()
    if ($rpoAge.TotalHours -gt $MaxRpoHours) {
        throw "CQ10 reprovado: backup tem $([Math]::Round($rpoAge.TotalHours, 2)) horas."
    }

    $restoreStarted = [DateTime]::UtcNow
    foreach ($database in @($manifest.databases)) {
        $dumpPath = Join-Path $backupDirectory ([string]$database.file)
        $actualHash = (Get-FileHash -LiteralPath $dumpPath -Algorithm SHA256).Hash
        if ($actualHash -ne [string]$database.sha256) {
            throw "Checksum invalido para $($database.database)."
        }

        $suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
        $containerName = "nexfleet-cq10-$($database.database)-$suffix"
        & docker run --detach --rm --name $containerName --network none `
            --env "POSTGRES_USER=$($database.user)" `
            --env "POSTGRES_DB=$($database.database)" `
            --env 'POSTGRES_HOST_AUTH_METHOD=trust' `
            postgres:18-alpine | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Nao foi possivel iniciar a restauracao de $($database.database)." }
        $activeContainers.Add($containerName)

        $ready = $false
        $consecutiveReadyChecks = 0
        for ($attempt = 0; $attempt -lt 90; $attempt++) {
            & docker exec $containerName pg_isready `
                "--username=$($database.user)" "--dbname=$($database.database)" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $consecutiveReadyChecks++
                if ($consecutiveReadyChecks -ge 3) { $ready = $true; break }
            } else {
                $consecutiveReadyChecks = 0
            }
            Start-Sleep -Seconds 1
        }
        if (-not $ready) { throw "PostgreSQL temporario de $($database.database) nao ficou pronto." }

        $containerDump = "/tmp/$($database.file)"
        & docker cp $dumpPath "${containerName}:$containerDump"
        if ($LASTEXITCODE -ne 0) { throw "Falha ao copiar $($database.file) para o restaurador." }
        & docker exec $containerName pg_restore `
            "--username=$($database.user)" "--dbname=$($database.database)" `
            --exit-on-error --no-owner --no-privileges $containerDump
        if ($LASTEXITCODE -ne 0) { throw "Falha ao restaurar $($database.database)." }

        foreach ($table in @($database.tables)) {
            $parts = ([string]$table.name).Split('.', 2)
            if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[a-z0-9_]+$' -or $parts[1] -notmatch '^[a-z0-9_]+$') {
                throw "Tabela inesperada no manifesto: $($table.name)."
            }
            $countSql = 'SELECT COUNT(*) FROM "{0}"."{1}";' -f $parts[0], $parts[1]
            $restoredCount = & docker exec $containerName psql `
                "--username=$($database.user)" "--dbname=$($database.database)" `
                --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 `
                --command $countSql
            if ($LASTEXITCODE -ne 0) { throw "Falha ao validar $($table.name)." }
            if ([long](([string]$restoredCount).Trim()) -ne [long]$table.rows) {
                throw "Contagem divergente em $($table.name)."
            }
        }

        Write-Output "Restauracao validada: $($database.database) ($(@($database.tables).Count) tabelas)."
        & docker stop --time 1 $containerName | Out-Null
        [void]$activeContainers.Remove($containerName)
    }

    $rto = [DateTime]::UtcNow - $restoreStarted
    if ($rto.TotalHours -gt $MaxRtoHours) {
        throw "CQ10 reprovado: restauracao levou $([Math]::Round($rto.TotalHours, 2)) horas."
    }
    Write-Output (
        'CQ10 aprovado: cinco bancos restaurados e conferidos; RPO observado {0:N2} minutos (< {1} h), RTO {2:N2} minutos (< {3} h).' -f `
        $rpoAge.TotalMinutes, $MaxRpoHours, $rto.TotalMinutes, $MaxRtoHours)
} finally {
    foreach ($containerName in @($activeContainers)) {
        & docker stop --time 1 $containerName 2>$null | Out-Null
    }
    $resolvedWork = [IO.Path]::GetFullPath($workDirectory)
    if ((Test-Path -LiteralPath $resolvedWork) -and
        $resolvedWork.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedWork)).StartsWith('nexfleet-cq10-')) {
        Remove-Item -LiteralPath $resolvedWork -Recurse -Force
    }
}
