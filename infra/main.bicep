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

//
// optional parameters
//
@description('Name of the Dev Center. If not provided, a name will be generated from dev-center.yaml.')
param devCenterName string = ''

@description('Resource group name to use. If not provided, a name will be generated.')
param resourceGroupName string = ''

var abbrs = loadJsonContent('./abbreviations.json')

// tags that should be applied to all resources.
var tags = {
  // Tag all resources with the environment name.
  'azd-env-name': environmentName
}

// Generate a unique token to be used in naming resources.
// Remove linter suppression after using.
#disable-next-line no-unused-vars
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.1.5' = {
  name: 'virtualNetwork'
  scope: rg
  params: {
    name: '${abbrs.networkVirtualNetworks}${resourceToken}'
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

module workspace 'br/public:avm/res/operational-insights/workspace:0.3.4' = {
  name: 'workspace'
  scope: rg
  params: {
    // Required parameters
    name: '${abbrs.operationalInsightsWorkspaces}-${devCenterConfig.organizationName}-${resourceToken}'	
    // Non-required parameters
    location: location
  }
}

// Add resources to be provisioned below.
var devCenterConfig = loadYamlContent('./dev-center.yaml')
module devcenter 'core/dev-center/dev-center.bicep' = {
  name: 'devCenter'
  scope: rg
  params: {
    name: !empty(devCenterName) ? devCenterName : 'dc-${devCenterConfig.organizationName}-${resourceToken}'
    location: location
    tags: tags
    config: devCenterConfig
    catalogToken: catalogToken
    //keyVaultName: !empty(catalogToken) ? keyVault.outputs.name : ''
    logWorkspaceName: workspace.outputs.name
    principalId: principalId
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
