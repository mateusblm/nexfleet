@description('Região dos recursos da plataforma.')
param location string

@description('Região de metadados do Static Web Apps.')
param staticWebLocation string

@description('Prefixo curto e globalmente seguro.')
param resourcePrefix string

@description('Nome lógico do ambiente.')
param environmentName string

@description('Rótulos comuns de governança.')
param tags object

@description('Contato administrativo exigido pelo API Management.')
param publisherEmail string

@description('Login administrativo do Azure SQL.')
param sqlAdministratorLogin string

@secure()
@description('Senha administrativa do Azure SQL; nunca é gravada no repositório nem exposta em outputs.')
param sqlAdministratorPassword string

@description('IP público opcional do administrador liberado no firewall do Azure SQL.')
param administratorIpAddress string = ''

@secure()
@description('Credenciais exclusivas por schema (identidade, operacoes, indicadores, notificacoes), provisionadas antes de habilitar os workloads.')
param serviceDatabaseCredentials object

@secure()
@description('Connection string do MongoDB Atlas usada somente pela Frota.')
param mongodbUri string = ''

@secure()
@description('Chave da Function calcular-eficiencia entregue somente ao BFF.')
param eficienciaFunctionKey string = ''

@description('Prefixo das imagens públicas no Docker Hub.')
param containerImagePrefix string

@description('Tag versionada das imagens Java.')
param containerImageTag string

@description('Mantém a sub-rede delegada do PostgreSQL legado enquanto o servidor antigo existir.')
param legacyPostgresqlSubnetEnabled bool = true

@secure()
@description('Chave RSA PKCS#8 da Identidade.')
param jwtPrivateKey string

@description('Ativa os Container Apps somente após a publicação das imagens.')
param workloadsEnabled bool

@description('Perfil de dimensionamento dos workloads: economico (padrão) ou carga (janela do CQ09).')
@allowed([
  'economico'
  'carga'
])
param workloadProfile string = 'economico'

@description('Destinatário das notificações externas. Vazio mantém o provedor captured-local, sem envio real.')
param notificationRecipientEmail string = ''

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, location))
var baseName = '${resourcePrefix}-${environmentName}'
var compactName = '${resourcePrefix}${environmentName}${resourceToken}'
var sqlDatabaseName = 'nexfleet'

var logAnalyticsName = 'log-${baseName}-${resourceToken}'
var applicationInsightsName = 'appi-${baseName}-${resourceToken}'
var keyVaultName = take('kv-${baseName}-${resourceToken}', 24)
var storageAccountName = take('st${compactName}', 24)
var serviceBusName = take('sb-${baseName}-${resourceToken}', 50)
var sqlServerName = take('sql-${baseName}-${resourceToken}', 63)
var containerEnvironmentName = take('cae-${baseName}-${resourceToken}', 60)
var staticWebAppName = take('swa-${baseName}-${resourceToken}', 60)
var apiManagementName = take('apim-${baseName}-${resourceToken}', 50)
var functionIdentityName = take('id-func-${baseName}-${resourceToken}', 128)
var functionPlanName = take('plan-func-${baseName}-${resourceToken}', 60)
var functionAppName = take('func-${baseName}-${resourceToken}', 60)
var functionDeploymentContainerName = 'app-package-${take(resourceToken, 13)}'
var virtualNetworkName = take('vnet-${baseName}-${resourceToken}', 64)
var externalEmailEnabled = !empty(notificationRecipientEmail)
var emailServiceName = take('ecs-${baseName}-${resourceToken}', 63)
var communicationServiceName = take('acs-${baseName}-${resourceToken}', 63)
// Região de residência dos dados do ACS; os recursos em si são globais.
var communicationDataLocation = 'United States'
var workloadNames = [
  'gateway'
  'bff'
  'identidade'
  'frota'
  'operacoes'
  'indicadores'
]
var apiMethods = [
  'GET'
  'POST'
  'PUT'
  'DELETE'
  'OPTIONS'
]

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    sku: {
      name: 'PerGB2018'
    }
    workspaceCapping: {
      // Limite de custo da v1.0.0: no máximo 0,15 GB/dia de ingestão.
      dailyQuotaGb: json('0.15')
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    DisableIpMasking: false
    DisableLocalAuth: true
    Flow_Type: 'Bluefield'
    IngestionMode: 'LogAnalytics'
    RetentionInDays: 30
    WorkspaceResourceId: logAnalytics.id
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    sku: {
      family: 'A'
      name: 'standard'
    }
  }
}

resource functionStorage 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: functionStorage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource functionDeploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: functionDeploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: serviceBusName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    disableLocalAuth: true
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource eventTopic 'Microsoft.ServiceBus/namespaces/topics@2024-01-01' = {
  parent: serviceBus
  name: 'nexfleet-eventos-v1'
  properties: {
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    enableExpress: false
    enablePartitioning: false
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    status: 'Active'
    supportOrdering: true
  }
}

resource indicadoresSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: eventTopic
  name: 'indicadores-v1'
  properties: {
    deadLetteringOnFilterEvaluationExceptions: true
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    lockDuration: 'PT1M'
    maxDeliveryCount: 3
    requiresSession: false
    status: 'Active'
  }
}

resource indicadoresRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2024-01-01' = {
  parent: indicadoresSubscription
  // Nome proprio: o PUT de '$Default' pelo ARM terminou Succeeded sem persistir a regra
  // (homologacao 10/11/2026), e assinatura sem regra descarta todos os eventos.
  name: 'eventos-operacoes-v1'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      compatibilityLevel: 20
      requiresPreprocessing: false
      sqlExpression: 'eventType IN (\'AbastecimentoRegistrado.v1\', \'ManutencaoRegistrada.v1\', \'AbastecimentoAtualizado.v1\', \'AbastecimentoExcluido.v1\', \'ManutencaoAtualizada.v1\', \'ManutencaoExcluida.v1\')'
    }
  }
}

resource notificacoesSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2024-01-01' = {
  parent: eventTopic
  name: 'notificacoes-abastecimentos-v1'
  properties: {
    deadLetteringOnFilterEvaluationExceptions: true
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'P14D'
    enableBatchedOperations: true
    lockDuration: 'PT1M'
    maxDeliveryCount: 3
    requiresSession: false
    status: 'Active'
  }
}

resource notificacoesRule 'Microsoft.ServiceBus/namespaces/topics/subscriptions/rules@2024-01-01' = {
  parent: notificacoesSubscription
  name: 'abastecimento-registrado-v1'
  properties: {
    filterType: 'SqlFilter'
    sqlFilter: {
      compatibilityLevel: 20
      requiresPreprocessing: false
      sqlExpression: 'eventType = \'AbastecimentoRegistrado.v1\''
    }
  }
}

// Sub-rede do PostgreSQL da v0.30.0. Uma sub-rede em uso não pode ser removida: fica enquanto o
// servidor antigo existir (reversão) e sai com legacyPostgresqlSubnetEnabled=false depois da exclusão.
var legacyPostgresqlSubnet = {
  name: 'postgresql'
  properties: {
    addressPrefix: '10.42.2.0/24'
    // Criado pelo PostgreSQL na homologação; declarado para o deploy não removê-lo.
    serviceEndpoints: [
      {
        service: 'Microsoft.Storage'
        locations: [
          'centralus'
          'eastus2'
        ]
      }
    ]
    delegations: [
      {
        name: 'postgresql-delegation'
        properties: {
          serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.42.0.0/16'
      ]
    }
    subnets: concat([
      {
        name: 'container-apps'
        properties: {
          addressPrefix: '10.42.0.0/23'
          delegations: [
            {
              name: 'container-apps-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'functions'
        properties: {
          addressPrefix: '10.42.3.0/24'
          delegations: [
            {
              name: 'functions-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ], legacyPostgresqlSubnetEnabled ? [legacyPostgresqlSubnet] : [])
  }
}

resource containerAppsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: 'container-apps'
}

resource functionsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: virtualNetwork
  name: 'functions'
}

// Azure SQL com endpoint público e TLS 1.2 (risco aceito na spec). Um único banco serverless
// com a oferta gratuita: ao esgotar o limite mensal, pausa em vez de cobrar.
resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
    version: '12.0'
  }
}

// 0.0.0.0 é a regra especial "Permitir serviços e recursos do Azure".
resource sqlAllowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlAllowAdministrator 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (!empty(administratorIpAddress)) {
  parent: sqlServer
  name: 'AllowAdministratorIp'
  properties: {
    startIpAddress: administratorIpAddress
    endIpAddress: administratorIpAddress
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 2
  }
  properties: {
    autoPauseDelay: 60
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    freeLimitExhaustionBehavior: 'AutoPause'
    maxSizeBytes: 34359738368
    minCapacity: json('0.5')
    requestedBackupStorageRedundancy: 'Local'
    useFreeLimit: true
    zoneRedundant: false
  }
}

// loginTimeout cobre o cold start (~1 min) do banco em auto-pause.
var sqlJdbcUrl = 'jdbc:sqlserver://${sqlServer.properties.fullyQualifiedDomainName}:1433;databaseName=${sqlDatabase.name};encrypt=true;trustServerCertificate=false;loginTimeout=60'

resource containerEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: containerEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnet.id
      internal: false
    }
    publicNetworkAccess: 'Enabled'
    zoneRedundant: false
  }
}

resource staticWebApp 'Microsoft.Web/staticSites@2025-03-01' = {
  name: staticWebAppName
  location: staticWebLocation
  tags: tags
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    allowConfigFileUpdates: true
    publicNetworkAccess: 'Enabled'
    stagingEnvironmentPolicy: 'Enabled'
  }
}

resource apiManagement 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: apiManagementName
  location: location
  tags: tags
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableGateway: false
    enableClientCertificate: false
    hostnameConfigurations: []
    legacyPortalStatus: 'Disabled'
    publicNetworkAccess: 'Enabled'
    publisherEmail: publisherEmail
    publisherName: 'NexFleet'
    virtualNetworkType: 'None'
  }
}

resource functionIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: functionIdentityName
  location: location
  tags: tags
}

resource workloadIdentities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [for workloadName in workloadNames: {
  name: take('id-${workloadName}-${baseName}-${resourceToken}', 128)
  location: location
  tags: tags
}]

var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'
var serviceBusDataSenderRoleId = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
var serviceBusDataReceiverRoleId = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
var communicationEmailOwnerRoleId = '09976791-48a7-449e-bb21-39d1a415f350'

resource operacoesServiceBusSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, workloadIdentities[4].id, serviceBusDataSenderRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataSenderRoleId)
    principalId: workloadIdentities[4].properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource indicadoresServiceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, workloadIdentities[5].id, serviceBusDataReceiverRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: workloadIdentities[5].properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// O escalador KEDA lê a contagem de mensagens pelas propriedades de runtime da assinatura,
// o que exige Data Owner; o escopo fica restrito à assinatura indicadores-v1.
var serviceBusDataOwnerRoleId = '090c5cfd-751d-490a-894a-3ce6f1109419'

resource indicadoresServiceBusScalerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(indicadoresSubscription.id, workloadIdentities[5].id, serviceBusDataOwnerRoleId)
  scope: indicadoresSubscription
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataOwnerRoleId)
    principalId: workloadIdentities[5].properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionServiceBusReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(serviceBus.id, functionIdentity.id, serviceBusDataReceiverRoleId)
  scope: serviceBus
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataReceiverRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionIdentity.id, storageBlobDataOwnerRoleId)
  scope: functionStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionIdentity.id, storageQueueDataContributorRoleId)
  scope: functionStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionStorage.id, functionIdentity.id, storageTableDataContributorRoleId)
  scope: functionStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource functionMetricsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, functionIdentity.id, monitoringMetricsPublisherRoleId)
  scope: applicationInsights
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = if (externalEmailEnabled) {
  name: emailServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: communicationDataLocation
  }
}

// Domínio gerenciado pela Azure (DoNotReply@<guid>.azurecomm.net): sem DNS próprio,
// limites de envio reduzidos e adequado à homologação.
resource emailDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = if (externalEmailEnabled) {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  tags: tags
  properties: {
    domainManagement: 'AzureManaged'
    userEngagementTracking: 'Disabled'
  }
}

resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = if (externalEmailEnabled) {
  name: communicationServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: communicationDataLocation
    linkedDomains: [
      emailDomain.id
    ]
  }
}

resource functionEmailSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (externalEmailEnabled) {
  name: guid(communicationService.id, functionIdentity.id, communicationEmailOwnerRoleId)
  scope: communicationService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', communicationEmailOwnerRoleId)
    principalId: functionIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

var emailAppSettings = externalEmailEnabled
  ? {
      EMAIL_PROVIDER: 'azure-communication'
      AZURE_COMMUNICATION_EMAIL_ENDPOINT: 'https://${communicationService!.properties.hostName}'
      EMAIL_SENDER_ADDRESS: 'DoNotReply@${emailDomain!.properties.mailFromSenderDomain}'
      EMAIL_RECIPIENT_ADDRESS: notificationRecipientEmail
    }
  : {
      EMAIL_PROVIDER: 'captured-local'
    }

resource functionPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: functionPlanName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
    zoneRedundant: false
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${functionIdentity.id}': {}
    }
  }
  properties: {
    httpsOnly: true
    serverFarmId: functionPlan.id
    virtualNetworkSubnetId: functionsSubnet.id
    siteConfig: {
      minTlsVersion: '1.2'
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${functionStorage.properties.primaryEndpoints.blob}${functionDeploymentContainer.name}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: functionIdentity.id
          }
        }
      }
      runtime: {
        name: 'java'
        version: '21'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: 2048
      }
    }
  }
  resource appSettings 'config' = {
    name: 'appsettings'
    properties: union({
      // DefaultAzureCredential precisa do clientId para usar a identidade atribuída pelo usuário.
      AZURE_CLIENT_ID: functionIdentity.properties.clientId
      AzureWebJobsStorage__accountName: functionStorage.name
      AzureWebJobsStorage__credential: 'managedidentity'
      AzureWebJobsStorage__clientId: functionIdentity.properties.clientId
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${functionIdentity.properties.clientId};Authorization=AAD'
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      NexFleetServiceBus__fullyQualifiedNamespace: '${serviceBus.name}.servicebus.windows.net'
      NexFleetServiceBus__credential: 'managedidentity'
      NexFleetServiceBus__clientId: functionIdentity.properties.clientId
      'AzureWebJobs.NotificarAbastecimentoRabbit.Disabled': 'true'
      DB_URL: sqlJdbcUrl
      DB_USER: serviceDatabaseCredentials.notificacoes.login
      DB_PASSWORD: serviceDatabaseCredentials.notificacoes.password
    }, emailAppSettings)
  }
  dependsOn: [
    functionEmailSenderRole
  ]
}

module workloads './workloads.bicep' = if (workloadsEnabled) {
  name: 'nexfleet-workloads'
  params: {
    location: location
    tags: tags
    baseName: baseName
    environmentId: containerEnvironment.id
    imagePrefix: containerImagePrefix
    imageTag: containerImageTag
    sqlJdbcUrl: sqlJdbcUrl
    databaseCredentials: serviceDatabaseCredentials
    mongodbUri: mongodbUri
    eficienciaFunctionUrl: 'https://${functionApp.properties.defaultHostName}'
    eficienciaFunctionKey: eficienciaFunctionKey
    jwtPrivateKey: jwtPrivateKey
    serviceBusNamespace: '${serviceBus.name}.servicebus.windows.net'
    serviceBusName: serviceBus.name
    workloadProfile: workloadProfile
    identities: {
      gateway: {
        id: workloadIdentities[0].id
        clientId: workloadIdentities[0].properties.clientId
      }
      bff: {
        id: workloadIdentities[1].id
        clientId: workloadIdentities[1].properties.clientId
      }
      identidade: {
        id: workloadIdentities[2].id
        clientId: workloadIdentities[2].properties.clientId
      }
      frota: {
        id: workloadIdentities[3].id
        clientId: workloadIdentities[3].properties.clientId
      }
      operacoes: {
        id: workloadIdentities[4].id
        clientId: workloadIdentities[4].properties.clientId
      }
      indicadores: {
        id: workloadIdentities[5].id
        clientId: workloadIdentities[5].properties.clientId
      }
    }
  }
  dependsOn: [
    sqlAllowAzureServices
    operacoesServiceBusSenderRole
    indicadoresServiceBusReceiverRole
    indicadoresServiceBusScalerRole
  ]
}

var apiCorsPolicy = '<policies><inbound><cors allow-credentials="false"><allowed-origins><origin>https://${staticWebApp.properties.defaultHostname}</origin></allowed-origins><allowed-methods preflight-result-max-age="300"><method>*</method></allowed-methods><allowed-headers><header>*</header></allowed-headers></cors><base /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'

resource nexfleetApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = if (workloadsEnabled) {
  parent: apiManagement
  name: 'nexfleet-v1'
  properties: {
    apiType: 'http'
    displayName: 'NexFleet API'
    path: 'api'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${workloads!.outputs.gatewayFqdn}/api'
    subscriptionRequired: false
  }
}

// O APIM recusa escritas concorrentes na mesma API (PreconditionFailed): operacoes em serie.
@batchSize(1)
resource nexfleetApiOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for method in apiMethods: if (workloadsEnabled) {
  parent: nexfleetApi
  name: toLower(method)
  properties: {
    displayName: '${method} wildcard'
    method: method
    urlTemplate: '/*'
    responses: []
  }
}]

resource nexfleetApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = if (workloadsEnabled) {
  parent: nexfleetApi
  name: 'policy'
  dependsOn: [
    nexfleetApiOperations
  ]
  properties: {
    format: 'xml'
    value: apiCorsPolicy
  }
}

// Rotas fora de /api encaminhadas à raiz do Gateway: agregação do BFF e Swagger UI única
// (a UI e os OpenAPI de cada serviço ficam em /swagger-ui, /webjars, /v3/api-docs e /docs/<svc>).
var gatewayRootOperations = [
  { name: 'get-aggregated-data', method: 'GET', urlTemplate: '/aggregated-data' }
  { name: 'options-aggregated-data', method: 'OPTIONS', urlTemplate: '/aggregated-data' }
  { name: 'get-swagger-ui-html', method: 'GET', urlTemplate: '/swagger-ui.html' }
  { name: 'get-swagger-ui', method: 'GET', urlTemplate: '/swagger-ui/*' }
  { name: 'get-webjars', method: 'GET', urlTemplate: '/webjars/*' }
  { name: 'get-api-docs', method: 'GET', urlTemplate: '/v3/api-docs' }
  { name: 'get-api-docs-wildcard', method: 'GET', urlTemplate: '/v3/api-docs/*' }
  { name: 'get-docs', method: 'GET', urlTemplate: '/docs/*' }
]

resource gatewayRootApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = if (workloadsEnabled) {
  parent: apiManagement
  name: 'nexfleet-gateway-root'
  properties: {
    apiType: 'http'
    displayName: 'NexFleet agregação e documentação'
    path: ''
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${workloads!.outputs.gatewayFqdn}'
    subscriptionRequired: false
  }
  dependsOn: [
    nexfleetApiPolicy
  ]
}

@batchSize(1)
resource gatewayRootApiOperations 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = [for operation in gatewayRootOperations: if (workloadsEnabled) {
  parent: gatewayRootApi
  name: operation.name
  properties: {
    displayName: '${operation.method} ${operation.urlTemplate}'
    method: operation.method
    urlTemplate: operation.urlTemplate
    responses: []
  }
}]

resource gatewayRootApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = if (workloadsEnabled) {
  parent: gatewayRootApi
  name: 'policy'
  dependsOn: [
    gatewayRootApiOperations
  ]
  properties: {
    format: 'xml'
    value: apiCorsPolicy
  }
}

@description('Nomes calculados sem expor senhas, chaves ou connection strings.')
output resourceNames object = {
  apiManagement: apiManagement.name
  apiBaseUrl: 'https://${apiManagement.name}.azure-api.net'
  applicationInsights: applicationInsights.name
  communicationService: externalEmailEnabled ? communicationServiceName : ''
  emailProvider: emailAppSettings.EMAIL_PROVIDER
  containerAppsEnvironment: containerEnvironment.name
  containerApps: workloadsEnabled ? workloads!.outputs.names : {}
  functionApp: functionApp.name
  keyVault: keyVault.name
  logAnalytics: logAnalytics.name
  sqlServer: sqlServer.name
  sqlDatabase: sqlDatabase.name
  serviceBus: serviceBus.name
  staticWebApp: staticWebApp.name
  storageAccount: functionStorage.name
  virtualNetwork: virtualNetwork.name
}
