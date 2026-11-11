# Aula 23 — backup, RPO, RTO e restauração segura

## O problema que o backup resolve

Volumes Docker preservam dados quando um contêiner é recriado, mas não são um backup. Uma exclusão acidental, corrupção ou perda do computador também pode atingir o volume. Um backup precisa existir separadamente e, principalmente, precisa ser restaurável.

No CQ10:

- **RPO** responde “até quanto dado podemos perder?”; o limite é 24 horas;
- **RTO** responde “quanto tempo podemos levar para recuperar?”; o limite é 4 horas.

## Criar backups dos cinco bancos

Com o backend ativo, execute na raiz:

```powershell
.\scripts\Backup-Databases.ps1
```

Será criada uma pasta como `backups/20261107-220000` com cinco arquivos `.dump` e `manifest.json`. O manifesto registra hashes, tamanho e contagens. A pasta está no `.gitignore`, mas isso não substitui controle de acesso ou criptografia.

Você também pode escolher outro destino:

```powershell
.\scripts\Backup-Databases.ps1 `
  -OutputDirectory "D:\Backups\NexFleet\2026-11-07"
```

Nunca coloque backups em Git, e-mail comum ou armazenamento público.

## Testar a restauração

```powershell
.\scripts\Test-Recovery.ps1
```

O script não restaura sobre seu banco. Ele cria cinco PostgreSQL temporários, sem acesso de rede, confere SHA-256, restaura e compara cada tabela. No final, remove os contêineres e arquivos temporários.

Uma mensagem de aprovação mostra RPO e RTO observados. Se checksum, restauração ou contagem falhar, o comando termina com erro.

## Por que não existe um comando de restauração em produção

Substituir um banco real é uma ação destrutiva que depende do incidente: pode ser necessário preservar evidências, escolher um ponto no tempo, bloquear escrita, trocar conexões e validar a aplicação antes de liberar usuários. Por segurança, o projeto automatiza a prova isolada, não uma sobrescrita cega do ambiente ativo.

## Automatizar a meta de 24 horas

Em desenvolvimento, agende `Backup-Databases.ps1` pelo Agendador de Tarefas, cron ou plataforma equivalente no máximo a cada 24 horas e copie o resultado para armazenamento protegido fora da máquina. Em Azure, prefira backup gerenciado e recuperação pontual do PostgreSQL, com retenção e redundância aprovadas.

Uma agenda configurada ainda precisa de monitoramento: falhas devem gerar alerta. Periodicamente execute a restauração em homologação; um arquivo que nunca foi restaurado é somente uma esperança de backup.

Consulte a [ADR 0024](../adr/0024-backup-e-recuperacao-cq10.md) e a [Evidência CQ10](../EVIDENCIA-CQ10-RECUPERACAO.md).
