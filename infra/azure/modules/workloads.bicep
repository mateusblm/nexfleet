@description('Região dos workloads.')
param location string

@description('Rótulos comuns.')
param tags object

@description('Prefixo de nomes.')
param baseName string

@description('Resource ID do Container Apps Environment.')
param environmentId string

@description('Login server do ACR.')
param registryServer string

@description('Tag versionada das seis imagens.')
param imageTag string

@description('FQDN privado do PostgreSQL.')
param postgresqlHost string

@secure()
@description('Credenciais exclusivas por banco; o login administrativo é proibido nos workloads.')
param databaseCredentials object

@secure()
@description('Chave privada RSA PKCS#8 montada somente no serviço Identidade.')
param jwtPrivateKey string

@description('FQDN do Service Bus sem protocolo.')
param serviceBusNamespace string

@description('Identidades gerenciadas, uma para cada serviço.')
param identities object

@description('economico: 0.5 vCPU, até 2 réplicas, escala a zero onde permitido. carga: 1 vCPU, 1 a 4 réplicas, usado somente na janela do CQ09.')
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
    image: '${registryServer}/identidade:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.identidade.id
    minReplicas: carga ? 1 : 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: concat([
        { name: 'db-password', value: databaseCredentials.identidade.password }
      ], [
        { name: 'jwt-private-key', value: jwtPrivateKey }
      ])
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: 'jdbc:postgresql://${postgresqlHost}:5432/identidade?sslmode=require' }
      { name: 'DB_USER', value: databaseCredentials.identidade.login }
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
    image: '${registryServer}/frota:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.frota.id
    minReplicas: carga ? 1 : 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'db-password', value: databaseCredentials.frota.password }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: 'jdbc:postgresql://${postgresqlHost}:5432/frota?sslmode=require' }
      { name: 'DB_USER', value: databaseCredentials.frota.login }
      { name: 'DB_PASSWORD', secretRef: 'db-password' }
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
    image: '${registryServer}/operacoes:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.operacoes.id
    minReplicas: 1
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'db-password', value: databaseCredentials.operacoes.password }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: 'jdbc:postgresql://${postgresqlHost}:5432/operacoes?sslmode=require' }
      { name: 'DB_USER', value: databaseCredentials.operacoes.login }
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
    image: '${registryServer}/indicadores:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.indicadores.id
    minReplicas: 1
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: [
        { name: 'db-password', value: databaseCredentials.indicadores.password }
      ]
    }
    environmentVariables: concat(commonSpring, [
      { name: 'DB_URL', value: 'jdbc:postgresql://${postgresqlHost}:5432/indicadores?sslmode=require' }
      { name: 'DB_USER', value: databaseCredentials.indicadores.login }
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
    image: '${registryServer}/bff:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.bff.id
    minReplicas: carga ? 1 : 0
    maxReplicas: sizing.maxReplicas
    cpu: sizing.cpu
    memory: sizing.memory
    secrets: {
      values: []
    }
    environmentVariables: concat(commonSpring, [
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
    image: '${registryServer}/gateway:${imageTag}'
    registryServer: registryServer
    identityResourceId: identities.gateway.id
    externalIngress: true
    minReplicas: 1
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
