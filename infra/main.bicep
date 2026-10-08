targetScope = 'resourceGroup'

@description('Azure region for the application and monitoring resources.')
param location string = resourceGroup().location

@description('Region supporting the selected Foundry chat model and deployment SKU.')
param aiLocation string = location

@minLength(3)
@maxLength(20)
@description('Lowercase letters, digits and hyphens used as a resource name prefix.')
param namePrefix string = 'email-intake'

@description('Microsoft Entra application registration client ID. The application fails closed outside Development when empty.')
param azureAdClientId string

@description('Optional HTTPS Key Vault secret URI for the Entra client secret, never the secret value. Grant the web app identity secret-read access to this existing vault separately.')
param azureAdClientSecretUri string = ''

@description('Optional existing Foundry OAuth Work IQ connection resource ID. OAuth consent and connection provisioning are performed separately.')
param foundryWorkIqConnectionId string = ''

@description('Foundry chat deployment name used by the application.')
param modelDeploymentName string = 'gpt-4.1'

@description('OpenAI chat model name. Availability depends on the region and subscription.')
param modelName string = 'gpt-4.1'

@description('Chat model version.')
param modelVersion string = '2025-04-14'

@description('Chat deployment SKU supported by the selected model and region.')
param modelDeploymentSku string = 'GlobalStandard'

@minValue(1)
@description('Chat model deployment capacity in units defined by the selected model SKU; requires subscription quota.')
param modelCapacity int = 10

@description('Paid App Service plan SKU supporting always-on Linux hosting.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v3'
  'P2v3'
  'P3v3'
])
param appServicePlanSku string = 'B1'

@description('Tags applied to resources.')
param tags object = {}

var suffix = uniqueString(resourceGroup().id)
var resourceName = '${namePrefix}-${suffix}'
var foundryProjectName = 'email-intake'
var projectEndpoint = foundryProject.properties.endpoints['AI Foundry API']
var azureAiUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
var cognitiveServicesUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${resourceName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourceName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: '${resourceName}-ai'
  location: aiLocation
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: '${resourceName}-ai'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: foundryProjectName
  location: aiLocation
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Email intake'
    description: 'Email intake agent project'
  }
}

resource chatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = {
  parent: foundryAccount
  name: modelDeploymentName
  sku: {
    name: modelDeploymentSku
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'NoAutoUpgrade'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: '${resourceName}-doc'
  location: aiLocation
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: '${resourceName}-doc'
    disableLocalAuth: true
    publicNetworkAccess: 'Enabled'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${resourceName}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: appServicePlanSku
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

var appSettings = [
  { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
  { name: 'Foundry__ProjectEndpoint', value: projectEndpoint }
  { name: 'Foundry__ModelDeploymentName', value: modelDeploymentName }
  { name: 'Foundry__AgentName', value: 'email-intake' }
  { name: 'Foundry__WorkIqConnectionId', value: foundryWorkIqConnectionId }
  { name: 'DocumentIntelligence__Endpoint', value: documentIntelligence.properties.endpoint }
  { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsights.properties.ConnectionString }
  // The application explicitly uses the Azure public-cloud Entra authority.
  #disable-next-line no-hardcoded-env-urls
  { name: 'AzureAd__Instance', value: 'https://login.microsoftonline.com/' }
  { name: 'AzureAd__TenantId', value: tenant().tenantId }
  { name: 'AzureAd__ClientId', value: azureAdClientId }
  { name: 'AzureAd__CallbackPath', value: '/signin-oidc' }
]

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: resourceName
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      appSettings: concat(appSettings, empty(azureAdClientSecretUri) ? [] : [
        {
          name: 'AzureAd__ClientSecret'
          value: '@Microsoft.KeyVault(SecretUri=${azureAdClientSecretUri})'
        }
      ])
    }
  }
}

resource ftpPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource scmPublishingPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: webApp
  name: 'scm'
  properties: {
    allow: false
  }
}

// Account scope covers project agent creation/calls and account-level model inference, without granting Contributor.
resource appFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: foundryAccount
  name: guid(foundryAccount.id, webApp.id, azureAiUserRoleId)
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: azureAiUserRoleId
  }
}

resource appDocumentIntelligenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: documentIntelligence
  name: guid(documentIntelligence.id, webApp.id, cognitiveServicesUserRoleId)
  properties: {
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cognitiveServicesUserRoleId
  }
}

output webUrl string = 'https://${webApp.properties.defaultHostName}'
output foundryProjectEndpoint string = projectEndpoint
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint
output deploymentName string = chatDeployment.name
output webAppName string = webApp.name
output webAppPrincipalId string = webApp.identity.principalId
output foundryProjectResourceId string = foundryProject.id
