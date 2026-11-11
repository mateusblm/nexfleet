targetScope = 'subscription'

@description('Região Azure aprovada no preflight conectado.')
param location string

@description('Região de metadados do Static Web Apps, validada separadamente da região principal.')
param staticWebLocation string = 'centralus'

@description('Nome do grupo de recursos de homologação.')
param resourceGroupName string

@description('Prefixo curto, minúsculo e sem hífen para nomes globais.')
@minLength(3)
@maxLength(12)
param resourcePrefix string

@description('Ambiente de destino. A primeira publicação aceita somente homolog.')
@allowed([
  'homolog'
])
param environmentName string = 'homolog'

@description('Limite mensal aprovado para o alerta de orçamento, na moeda da assinatura.')
@minValue(1)
param monthlyBudgetAmount int

@description('Primeiro dia do período do orçamento em ISO 8601, por exemplo 2026-11-01T00:00:00Z.')
param budgetStartDate string

@description('Fim do período do orçamento em ISO 8601.')
param budgetEndDate string

@description('Destinatários responsáveis pelos alertas de custo.')
@minLength(1)
param budgetAlertEmails array

@description('Login administrativo do servidor Azure SQL. Usado só no bootstrap dos schemas e logins dos serviços.')
param sqlAdministratorLogin string

@secure()
@description('Senha administrativa do Azure SQL recebida somente no momento do what-if/deploy.')
param sqlAdministratorPassword string

@description('IP público opcional do administrador liberado no firewall do Azure SQL. Vazio não cria a regra.')
param administratorIpAddress string = ''

@secure()
@description('Logins e senhas exclusivos dos schemas identidade, operacoes, indicadores e notificacoes; nunca usar o administrador nos workloads.')
param serviceDatabaseCredentials object

@secure()
@description('Connection string do MongoDB Atlas (mongodb+srv://...), usada somente pela Frota.')
param mongodbUri string = ''

@secure()
@description('Chave da Function calcular-eficiencia entregue somente ao BFF. Obtida depois de publicar a Function.')
param eficienciaFunctionKey string = ''

@description('Prefixo das imagens públicas no Docker Hub; o nome do serviço é acrescentado ao final.')
param containerImagePrefix string = 'docker.io/mateusblm/nexfleet-'

@description('Tag das imagens dos seis serviços. Nunca usar latest.')
param containerImageTag string = 'v1.0.0'

@secure()
@description('Chave privada RSA PKCS#8 em Base64, decodificada somente ao compor o segredo da Identidade.')
param jwtPrivateKeyBase64 string

@description('Modela os seis workloads no what-if/deploy somente depois que as imagens versionadas estiverem no Docker Hub.')
param workloadsEnabled bool = false

@description('Confirma que o bootstrap T-SQL criou os schemas e os logins por serviço antes dos workloads.')
param databaseMigrationsCompleted bool = false

@description('Mantém a sub-rede delegada do PostgreSQL legado enquanto o servidor antigo existir (sub-rede em uso não pode ser removida).')
param legacyPostgresqlSubnetEnabled bool = true

@description('Dimensionamento dos workloads: economico (padrão) ou carga, usado somente durante o CQ09.')
@allowed([
  'economico'
  'carga'
])
param workloadProfile string = 'economico'

@description('Destinatário das notificações via Azure Communication Services Email. Vazio mantém captured-local.')
param notificationRecipientEmail string = ''

@description('Rótulos comuns para governança e inventário.')
param additionalTags object = {}

@description('Trava contra implantação acidental. O valor padrão false não modela criação alguma.')
param publicationApproved bool = false

var commonTags = union(additionalTags, {
  application: 'NexFleet'
  environment: environmentName
  managedBy: 'Bicep'
  costCenter: 'NexFleet'
})

var databaseMigrationGate = !workloadsEnabled || databaseMigrationsCompleted
  ? true
  : fail('workloadsEnabled exige databaseMigrationsCompleted=true apos o bootstrap T-SQL dos schemas e logins.')

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' = if (publicationApproved) {
  name: resourceGroupName
  location: location
  tags: commonTags
}

resource monthlyBudget 'Microsoft.Consumption/budgets@2024-08-01' = if (publicationApproved) {
  name: '${resourcePrefix}-${environmentName}-monthly'
  properties: {
    amount: monthlyBudgetAmount
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate
      endDate: budgetEndDate
    }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          resourceGroupName
        ]
      }
    }
    notifications: {
      Actual_50_Percent: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: budgetAlertEmails
      }
      Actual_80_Percent: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: budgetAlertEmails
      }
      Forecast_100_Percent: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        thresholdType: 'Forecasted'
        contactEmails: budgetAlertEmails
      }
    }
  }
}

module platform './modules/platform.bicep' = if (publicationApproved && databaseMigrationGate) {
  name: 'nexfleet-${environmentName}-platform'
  scope: resourceGroup
  params: {
    location: location
    staticWebLocation: staticWebLocation
    resourcePrefix: resourcePrefix
    environmentName: environmentName
    tags: commonTags
    publisherEmail: budgetAlertEmails[0]
    sqlAdministratorLogin: sqlAdministratorLogin
    sqlAdministratorPassword: sqlAdministratorPassword
    administratorIpAddress: administratorIpAddress
    serviceDatabaseCredentials: serviceDatabaseCredentials
    mongodbUri: mongodbUri
    eficienciaFunctionKey: eficienciaFunctionKey
    containerImagePrefix: containerImagePrefix
    containerImageTag: containerImageTag
    legacyPostgresqlSubnetEnabled: legacyPostgresqlSubnetEnabled
    jwtPrivateKey: base64ToString(jwtPrivateKeyBase64)
    workloadsEnabled: workloadsEnabled
    notificationRecipientEmail: notificationRecipientEmail
    workloadProfile: workloadProfile
  }
}

@description('Grupo de recursos planejado para a homologação.')
output deployedResourceGroupName string = resourceGroupName

@description('Nomes calculados pela plataforma para revisão no what-if.')
output plannedResourceNames object = publicationApproved ? platform!.outputs.resourceNames : {}
