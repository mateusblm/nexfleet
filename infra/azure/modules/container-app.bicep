@description('Nome do Container App.')
param name string

@description('Região do workload.')
param location string

@description('Rótulos comuns.')
param tags object

@description('Resource ID do Container Apps Environment.')
param environmentId string

@description('Imagem pública e versionada do serviço (Docker Hub), puxada sem credencial de registry.')
param image string

@description('Resource ID da identidade gerenciada usada pelo workload (Service Bus e DefaultAzureCredential).')
param identityResourceId string

@description('Expõe o ingress para a internet somente no Gateway.')
param externalIngress bool = false

@description('Réplicas mínimas. Zero por padrão: o app sobe na primeira requisição HTTP.')
@minValue(0)
param minReplicas int = 0

@description('Réplicas máximas.')
@minValue(1)
param maxReplicas int = 2

@description('vCPU do contêiner, como texto decimal (0.5 ou 1.0).')
param cpu string = '0.5'

@description('Memória do contêiner, compatível com a vCPU (1Gi para 0.5; 2Gi para 1.0).')
param memory string = '1Gi'

@description('Regras de escala adicionais (por exemplo KEDA azure-servicebus), somadas à regra HTTP.')
param extraScaleRules array = []

@description('Variáveis não sigilosas do contêiner.')
param environmentVariables array = []

@secure()
@description('Objeto com a propriedade values contendo os segredos no formato { name, value }.')
param secrets object

@description('Volumes, inclusive volumes baseados em secrets.')
param volumes array = []

@description('Montagens de volume do contêiner.')
param volumeMounts array = []

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: externalIngress
        allowInsecure: false
        targetPort: 8080
        transport: 'http'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: secrets.values
    }
    template: {
      containers: [
        {
          name: name
          image: image
          env: environmentVariables
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 10
              failureThreshold: 18
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/actuator/health/readiness'
                port: 8080
                scheme: 'HTTP'
              }
              periodSeconds: 10
              failureThreshold: 3
            }
          ]
          volumeMounts: volumeMounts
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: concat([
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '25'
              }
            }
          }
        ], extraScaleRules)
      }
      volumes: volumes
    }
  }
}

@description('Resource ID do Container App.')
output id string = app.id

@description('FQDN do ingress do Container App.')
output fqdn string = app.properties.configuration.ingress.fqdn

@description('Nome efetivo do Container App.')
output name string = app.name
