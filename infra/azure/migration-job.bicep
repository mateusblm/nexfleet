// Jobs manuais do Container Apps que executam, dentro da VNet, a imagem infra/azure-database:
// - migrate: provisiona os cinco papeis e aplica as 17 migracoes Flyway (usa o administrador);
// - verify: prova versoes e isolamento usando somente as credenciais de cada servico.
// Implantado por scripts/Publish-AzureDatabaseMigration.ps1 depois da fundacao.

@description('Regiao dos jobs, igual a do Container Apps Environment.')
param location string

@description('Rotulos comuns.')
param tags object

@description('Resource ID do Container Apps Environment integrado a VNet.')
param environmentId string

@description('Imagem versionada no ACR, por exemplo cr....azurecr.io/azure-database:0.29.0.')
param image string

@description('Login server do ACR.')
param registryServer string

@description('Identidade gerenciada com AcrPull usada para baixar a imagem.')
param registryIdentityId string

@description('FQDN do PostgreSQL resolvido pela zona DNS privada.')
param postgresqlHost string

@description('Login administrativo temporario, usado somente pelo job migrate.')
param postgresqlAdministratorLogin string

@secure()
@description('Senha administrativa temporaria, entregue somente como segredo do job migrate.')
param postgresqlAdministratorPassword string

@secure()
@description('Logins e senhas dos cinco bancos.')
param serviceDatabaseCredentials object

@description('E-mail do primeiro Administrador. Vazio nao cria o job de bootstrap.')
param administratorEmail string = ''

@secure()
@description('Hash BCrypt (custo 12) da senha do primeiro Administrador; a senha nunca chega a Azure.')
param administratorPasswordHash string = ''

var services = [
  'identidade'
  'frota'
  'operacoes'
  'indicadores'
  'notificacoes'
]

var serviceSecrets = [for service in services: {
  name: '${service}-db-password'
  value: serviceDatabaseCredentials[service].password
}]

var serviceUserEnv = [for service in services: {
  name: '${toUpper(service)}_DB_USER'
  value: serviceDatabaseCredentials[service].login
}]

var servicePasswordEnv = [for service in services: {
  name: '${toUpper(service)}_DB_PASSWORD'
  secretRef: '${service}-db-password'
}]

var serviceEnv = concat(serviceUserEnv, servicePasswordEnv)

var jobNames = [
  'job-nexfleet-db-migrate'
  'job-nexfleet-db-verify'
]

var commonEnv = [
  { name: 'DB_HOST', value: postgresqlHost }
  { name: 'DB_SSLMODE', value: 'require' }
]

var jobs = [
  {
    name: jobNames[0]
    command: []
    secrets: concat(serviceSecrets, [
      { name: 'postgres-admin-password', value: postgresqlAdministratorPassword }
    ])
    env: concat(commonEnv, serviceEnv, [
      { name: 'POSTGRES_ADMIN_USER', value: postgresqlAdministratorLogin }
      { name: 'POSTGRES_ADMIN_PASSWORD', secretRef: 'postgres-admin-password' }
    ])
  }
  {
    name: jobNames[1]
    command: [
      '/nexfleet/verify.sh'
    ]
    secrets: serviceSecrets
    env: concat(commonEnv, serviceEnv)
  }
]

resource migrationJobs 'Microsoft.App/jobs@2024-03-01' = [for job in jobs: {
  name: job.name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${registryIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 1800
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: registryServer
          identity: registryIdentityId
        }
      ]
      secrets: job.secrets
    }
    template: {
      containers: [
        {
          name: 'database'
          image: image
          command: empty(job.command) ? null : job.command
          env: job.env
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
    }
  }
}]

resource administratorJob 'Microsoft.App/jobs@2024-03-01' = if (!empty(administratorEmail)) {
  name: 'job-nexfleet-db-admin'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${registryIdentityId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 0
      manualTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: registryServer
          identity: registryIdentityId
        }
      ]
      secrets: [
        { name: 'identidade-db-password', value: serviceDatabaseCredentials.identidade.password }
        { name: 'admin-password-hash', value: administratorPasswordHash }
      ]
    }
    template: {
      containers: [
        {
          name: 'database'
          image: image
          command: [
            '/nexfleet/bootstrap-admin.sh'
          ]
          env: concat(commonEnv, [
            { name: 'IDENTIDADE_DB_USER', value: serviceDatabaseCredentials.identidade.login }
            { name: 'IDENTIDADE_DB_PASSWORD', secretRef: 'identidade-db-password' }
            { name: 'ADMIN_EMAIL', value: administratorEmail }
            { name: 'ADMIN_PASSWORD_HASH', secretRef: 'admin-password-hash' }
          ])
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
    }
  }
}

@description('Nomes dos jobs migrate e verify.')
output jobNames array = jobNames
