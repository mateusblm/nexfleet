@description('Região dos workloads.')
param location string

@description('Rótulos comuns.')
param tags object

@description('Prefixo de nomes.')
param baseName string

@description('Resource ID do Container Apps Environment.')
param environmentId string

@description('Prefixo das imagens públicas, por exemplo docker.io/mateusblm/nexfleet-.')
param imagePrefix string

@description('Tag versionada das seis imagens.')
param imageTag string

@description('URL JDBC do Azure SQL com TLS obrigatório; o schema vem do login de cada serviço.')
param sqlJdbcUrl string

@secure()
@description('Credenciais exclusivas por schema; o login administrativo é proibido nos workloads.')
param databaseCredentials object

@secure()
@description('Connection string do MongoDB Atlas da Frota.')
param mongodbUri string

@description('URL HTTPS da Function calcular-eficiencia chamada pelo BFF.')
param eficienciaFunctionUrl string

@secure()
@description('Chave da Function calcular-eficiencia, entregue somente ao BFF.')
param eficienciaFunctionKey string

@secure()
@description('Chave privada RSA PKCS#8 montada somente no serviço Identidade.')
param jwtPrivateKey string

@description('FQDN do Service Bus sem protocolo.')
param serviceBusNamespace string

@description('Nome curto do namespace Service Bus, usado pela regra KEDA do Indicadores.')
param serviceBusName string

@description('Identidades gerenciadas, uma para cada serviço.')
param identities object

@description('economico: 0.5 vCPU, 0 a 2 réplicas. carga: 1 vCPU, 0 a 4 réplicas, usado somente na janela de um teste de carga.')
@allowed([
  'economico'
  'carga'
])
param workloadProfile string = 'economico'

var carga = workloadProfile == 'carga'
var sizing = {
  cpu: carga ? '1.0' : '0.5'
  memory: carga ? '2Gi' : '1Gi'
  maxReplicas: carga ? 4 : 2
}

var commonSpring = [
  { name: 'PORT', value: '8080' }
  { name: 'SPRING_PROFILES_ACTIVE', value: 'jwt-rsa' }
]
module identidade './container-app.bicep' = {
  name: 'container-identidade'
  params: {
    name: 'ca-identidade-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}identidade:${imageTag}'
    identityResourceId: identities.identidade.id
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: concat([
        { name: 'db-user', value: databaseCredentials.identidade.login }
        { name: 'db-password', value: databaseCredentials.identidade.password }
      ], [
        { name: 'jwt-private-key', value: jwtPrivateKey }
      ])
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: sqlJdbcUrl }
      { name: 'DB_USER', secretRef: 'db-user' }
      { name: 'DB_PASSWORD', secretRef: 'db-password' }
      { name: 'AUTH_JWT_PRIVATE_KEY', value: 'file:/run/secrets/identidade-jwt.pem' }
      { name: 'AZURE_CLIENT_ID', value: identities.identidade.clientId }
    ])
    volumes: [
      {
        name: 'jwt-key'
        storageType: 'Secret'
        secrets: [
          { secretRef: 'jwt-private-key', path: 'identidade-jwt.pem' }
        ]
      }
    ]
    volumeMounts: [
      { volumeName: 'jwt-key', mountPath: '/run/secrets' }
    ]
  }
}

module frota './container-app.bicep' = {
  name: 'container-frota'
  params: {
    name: 'ca-frota-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}frota:${imageTag}'
    identityResourceId: identities.frota.id
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'mongodb-uri', value: mongodbUri }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'MONGODB_URI', secretRef: 'mongodb-uri' }
      { name: 'IDENTIDADE_URL', value: 'https://${identidade.outputs.fqdn}' }
      { name: 'AZURE_CLIENT_ID', value: identities.frota.clientId }
    ])
  }
}

module operacoes './container-app.bicep' = {
  name: 'container-operacoes'
  params: {
    name: 'ca-operacoes-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}operacoes:${imageTag}'
    identityResourceId: identities.operacoes.id
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'db-user', value: databaseCredentials.operacoes.login }
        { name: 'db-password', value: databaseCredentials.operacoes.password }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: sqlJdbcUrl }
      { name: 'DB_USER', secretRef: 'db-user' }
      { name: 'DB_PASSWORD', secretRef: 'db-password' }
      { name: 'IDENTIDADE_URL', value: 'https://${identidade.outputs.fqdn}' }
      { name: 'FROTA_URL', value: 'https://${frota.outputs.fqdn}' }
      { name: 'MESSAGING_PROVIDER', value: 'servicebus' }
      { name: 'SERVICEBUS_FULLY_QUALIFIED_NAMESPACE', value: serviceBusNamespace }
      { name: 'SERVICEBUS_TOPIC', value: 'nexfleet-eventos-v1' }
      { name: 'AZURE_CLIENT_ID', value: identities.operacoes.clientId }
    ])
  }
}

module indicadores './container-app.bicep' = {
  name: 'container-indicadores'
  params: {
    name: 'ca-indicadores-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}indicadores:${imageTag}'
    identityResourceId: identities.indicadores.id
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    // Consumidor único da assinatura; a regra KEDA abaixo o acorda quando chegam eventos.
    maxReplicas: 1
    extraScaleRules: [
      {
        name: 'servicebus-indicadores'
        custom: {
          type: 'azure-servicebus'
          metadata: {
            namespace: serviceBusName
            topicName: 'nexfleet-eventos-v1'
            subscriptionName: 'indicadores-v1'
            messageCount: '5'
          }
          // KEDA autentica com a identidade gerenciada do próprio app, sem connection string.
          identity: identities.indicadores.id
        }
      }
    ]
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'db-user', value: databaseCredentials.indicadores.login }
        { name: 'db-password', value: databaseCredentials.indicadores.password }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: sqlJdbcUrl }
      { name: 'DB_USER', secretRef: 'db-user' }
      { name: 'DB_PASSWORD', secretRef: 'db-password' }
      { name: 'IDENTIDADE_URL', value: 'https://${identidade.outputs.fqdn}' }
      { name: 'MESSAGING_PROVIDER', value: 'servicebus' }
      { name: 'SERVICEBUS_FULLY_QUALIFIED_NAMESPACE', value: serviceBusNamespace }
      { name: 'SERVICEBUS_TOPIC', value: 'nexfleet-eventos-v1' }
      { name: 'SERVICEBUS_INDICADORES_SUBSCRIPTION', value: 'indicadores-v1' }
      { name: 'AZURE_CLIENT_ID', value: identities.indicadores.clientId }
    ])
  }
}

module bff './container-app.bicep' = {
  name: 'container-bff'
  params: {
    name: 'ca-bff-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}bff:${imageTag}'
    identityResourceId: identities.bff.id
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'eficiencia-function-key', value: eficienciaFunctionKey }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'EFICIENCIA_FUNCTION_URL', value: eficienciaFunctionUrl }
      { name: 'EFICIENCIA_FUNCTION_KEY', secretRef: 'eficiencia-function-key' }
      { name: 'IDENTIDADE_URL', value: 'https://${identidade.outputs.fqdn}' }
      { name: 'FROTA_URL', value: 'https://${frota.outputs.fqdn}' }
      { name: 'OPERACOES_URL', value: 'https://${operacoes.outputs.fqdn}' }
      { name: 'INDICADORES_URL', value: 'https://${indicadores.outputs.fqdn}' }
      { name: 'AZURE_CLIENT_ID', value: identities.bff.clientId }
    ])
  }
}

module gateway './container-app.bicep' = {
  name: 'container-gateway'
  params: {
    name: 'ca-gateway-${baseName}'
    location: location
    tags: tags
    environmentId: environmentId
    image: '${imagePrefix}gateway:${imageTag}'
    identityResourceId: identities.gateway.id
    externalIngress: true
    // Sem custo fixo: todos escalam a zero, inclusive no perfil de carga.
    minReplicas: 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: []
    }
    environmentVariables: concat(commonSpring, [
      { name: 'BFF_URL', value: 'https://${bff.outputs.fqdn}' }
      { name: 'AZURE_CLIENT_ID', value: identities.gateway.clientId }
    ])
  }
}

@description('FQDN público do API Gateway.')
output gatewayFqdn string = gateway.outputs.fqdn

@description('Nomes dos seis Container Apps.')
output names object = {
  gateway: gateway.outputs.name
  bff: bff.outputs.name
  identidade: identidade.outputs.name
  frota: frota.outputs.name
  operacoes: operacoes.outputs.name
  indicadores: indicadores.outputs.name
}
