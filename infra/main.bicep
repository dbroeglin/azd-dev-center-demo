targetScope = 'subscription'

// The main bicep module to provision Azure resources.
// For a more complete walkthrough to understand how this file works with azd,
// see https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/make-azd-compatible?pivots=azd-create

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@secure()
@description('GitHub PAT used to access the catalog (optional if public)')
param catalogToken string = ''

@description('Principal Id of the user or service principal that will have access to the Dev Center.')
param principalId string

@description('Optional name of the organization to create (overides devcenter.yaml organizationName)')
param organizationName string = ''

//
// optional parameters
//
@description('Resource group name to use. If not provided, a name will be generated.')
param resourceGroupName string = ''

var abbreviations = loadJsonContent('./abbreviations.json')

// tags that should be applied to all resources.
var tags = {
  // Tag all resources with the environment name.
  'azd-env-name': environmentName
}


// Generate a unique token to be used in naming resources.
// Remove linter suppression after using.
#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

@description('Name of the environment with only alphanumeric characters. Used for resource names that require alphanumeric characters only.')
var alphaNumericEnvironmentName = replace(replace(environmentName, '-', ''), ' ', '')

// load YAML config, allow for organizationName to be overridden by parameter
var devCenterConfig  = loadYamlContent('./dev-center.yaml')

var _organizationName = empty(organizationName) ? devCenterConfig.organizationName : organizationName
var _keyVaultName = take('${abbreviations.keyVaultVaults}${take(alphaNumericEnvironmentName, 8)}${resourceToken}', 24)
var _devCenterName = 'dc-${toLower(_organizationName)}'

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbreviations.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.1.5' = {
  name: 'virtualNetwork'
  scope: resourceGroup
  params: {
    name: '${abbreviations.networkVirtualNetworks}${resourceToken}'
    location: location
    tags: tags
    addressPrefixes: [
      '10.0.0.0/16'
    ]
    subnets: [
      {
        name: 'default'
        addressPrefix: '10.0.1.0/24'
      }
    ]
  }
} 

module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.3.4' = {
  name: 'logAnalyticsWorkspace'
  scope: resourceGroup
  params: {
    name: '${abbreviations.operationalInsightsWorkspaces}${_organizationName}-${resourceToken}'	
    location: location
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.6.1' = {
  name: 'keyVault'
  scope: resourceGroup
  params: {
    name: _keyVaultName
    enablePurgeProtection: true
    location: location
    enableRbacAuthorization: true
    secrets: [
      {
        name: 'catalogToken'
        value: catalogToken
      }
    ]
  }
}

/** Assign Key Vault Administrator role to the user who is deploying */
module keyVaultRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.0' = {
  name:  guid(subscription().id, keyVault.name, principalId)
  scope: resourceGroup
  params: {
    resourceId: keyVault.outputs.resourceId
    principalId: principalId
    roleDefinitionId: '00482a5a-887f-4fb3-b363-3b7fe8e74483' // Key Vault Administrator
  }
}

module devCenter 'core/dev-center/dev-center.bicep' = {
  name: 'devCenter'
  scope: resourceGroup
  params: {
    name: _devCenterName
    location: location
    tags: tags
    config: devCenterConfig
    keyVaultName: keyVault.outputs.name
    logWorkspaceName: logAnalyticsWorkspace.outputs.name
    principalId: principalId
  }
}

resource devCenterRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, devCenter.name, 'managed-identity') 
  scope: subscription()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635') // Owner
    principalId: devCenter.outputs.principalId
  }
}

// Add outputs from the deployment here, if needed.
//
// This allows the outputs to be referenced by other bicep deployments in the deployment pipeline,
// or by the local machine as a way to reference created resources in Azure for local development.
// Secrets should not be added here.
//
// Outputs are automatically saved in the local azd environment .env file.
// To see these outputs, run `azd env get-values`,  or `azd env get-values --output json` for json output.
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_DEV_CENTER_NAME string = devCenter.outputs.name
