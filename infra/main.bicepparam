using './main.bicep'

param namePrefix = 'email-intake'
param location = 'eastus2'
param aiLocation = 'eastus2'

// Supply an Entra app registration client ID before deploying application code.
// An empty value intentionally leaves the Production application fail-closed.
param azureAdClientId = ''

// Only a Key Vault secret URI belongs here, never a plaintext client secret.
// Grant the web app managed identity secret-read access on the existing vault.
param azureAdClientSecretUri = ''

// Set an existing Foundry OAuth connection resource ID after provisioning and consenting to Work IQ.
param foundryWorkIqConnectionId = ''

param modelDeploymentName = 'gpt-4.1'
param modelName = 'gpt-4.1'
param modelVersion = '2025-04-14'
param modelDeploymentSku = 'GlobalStandard'
param modelCapacity = 10
param appServicePlanSku = 'B1'
