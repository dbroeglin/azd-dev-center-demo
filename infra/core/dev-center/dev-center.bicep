@description('The dev center name')
param name string

@description('The location to deploy the dev center to')
param location string = resourceGroup().location

@description('The configuration for the dev center')
param config devCenterConfig

@description('The tags to apply to the dev center')
param tags object = {}

@description('The principal id to add as a admin of the dev center')
param principalId string = ''
/*
@description('The name of the key vault to store secrets in')
param keyVaultName string = ''
*/

@secure()
@description('The personal access token to use to access the catalog')
param catalogToken string = ''

/*
@secure()
param catalogSecretIdentifier string = ''
*/

@description('The name of the log analytics workspace to send logs to')
param logWorkspaceName string = ''


type devCenterConfig = {
  organizationName: string
  projects: project[]
  definitions: definition[]
  catalogs: catalog[]
  environmentTypes: devCenterEnvironmentType[]
}

type project = {
  name: string
  environmentTypes: projectEnvironmentType[]
  members: memberRoleAssignment[]
  pools: devBoxPool[]
}

type devBoxPool = {
  name: string
  definition: string

  @description('[NOT IMPLEMENTED] The grace period in minutes before the Dev Box is stopped after the user disconnects')
  @minValue(60)
  @maxValue(480)
  gracePeriodMinutes: int?
}

type catalog = {
  type: 'github' | 'adoGit'
  name: string
  uri: string
  branch: string?
  path: string?
  secretIdentifier: string?
}

type definition = {
  name: string
  image: string
  sku: string
  hibernateSupport: bool?
  osStorageType: string?
}

type devCenterEnvironmentType = {
  name: string
  tags: object?
}

type projectEnvironmentType = {
  name: string
  deploymentTargetId: string?
  tags: object?
  roles: string[]
  members: memberRoleAssignment[]
}

type memberRoleAssignment = {
  user: string
  role: ('Deployment Environments User' | 'DevCenter Project Admin')
}

resource devCenter 'Microsoft.DevCenter/devcenters@2023-04-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

resource devCenterCatalog 'Microsoft.DevCenter/devcenters/catalogs@2023-04-01' = [
  for catalog in config.catalogs: {
    name: catalog.name
    parent: devCenter
    properties:  {
          gitHub: {
            branch: catalog.branch ?? 'main'
            uri: catalog.uri
            path: catalog.path ?? '/'
          }
        }
  }
]

resource environmentType 'Microsoft.DevCenter/devcenters/environmentTypes@2023-04-01' = [
  for environmentType in config.environmentTypes: {
    name: environmentType.name
    tags: empty(environmentType.tags) ? {} : environmentType.tags
    parent: devCenter
  }
]

// Default to current principal id to have Project Admin role
var defaultProjectRoleAssignments = {
  user: principalId
  role: 'DevCenter Project Admin'
}

module devCenterProject 'dev-center-project.bicep' = [
  for project in config.projects: {
    name: '${deployment().name}-${project.name}'
    params: {
      name: project.name
      location: location
      tags: tags
      devCenterName: devCenter.name
      environmentTypes: project.environmentTypes
      members: !empty(project.members) ? project.members : [defaultProjectRoleAssignments]
      pools: project.pools
    }
  }
]

resource devBoxDefinition 'Microsoft.DevCenter/devcenters/devboxdefinitions@2023-10-01-preview' = [
  for definition in config.definitions: {
    name: definition.name
    location: location
    parent: devCenter
    properties: {
      //hibernateSupport: (definition.hibernateSupport ?? false) ? 'Enabled' : 'Disabled' 
      imageReference: {
        id: '${devCenter.id}/galleries/default/images/${images[definition.image]}'
      }
      sku: {
        name: skus[definition.sku]
      }
    }
  }
]

var skus = {
  '8-vcpu-32gb-ram-256-ssd': 'general_i_8c32gb256ssd_v2'
  '8-vcpu-32gb-ram-512-ssd': 'general_i_8c32gb512ssd_v2'
  '8-vcpu-32gb-ram-1024-ssd': 'general_i_8c32gb1024ssd_v2'
  '8-vcpu-32gb-ram-2048-ssd': 'general_i_8c32gb2048ssd_v2'
  '16-vcpu-64gb-ram-254-ssd': 'general_i_16c64gb256ssd_v2'
  '16-vcpu-64gb-ram-512-ssd': 'general_i_16c64gb512ssd_v2'
  '16-vcpu-64gb-ram-1024-ssd': 'general_i_16c64gb1024ssd_v2'
  '16-vcpu-64gb-ram-2048-ssd': 'general_i_16c64gb2048ssd_v2'
  '32-vcpu-128gb-ram-512-ssd': 'general_i_32c128gb512ssd_v2'
  '32-vcpu-128gb-ram-1024-ssd': 'general_i_32c128gb1024ssd_v2'
  '32-vcpu-128gb-ram-2048-ssd': 'general_i_32c128gb2048ssd_v2'
}

var images = {
  // Windows 10
  'win-10-ent-20h2-os': 'microsoftwindowsdesktop_windows-ent-cpc_20h2-ent-cpc-os-g2'
  'win-10-ent-20h2-m365': 'microsoftwindowsdesktop_windows-ent-cpc_20h2-ent-cpc-m365-g2'
  'win-10-ent-21h2-os': 'microsoftwindowsdesktop_windows-ent-cpc_win10-21h2-ent-cpc-os-g2'
  'win-10-ent-21h2-m365': 'microsoftwindowsdesktop_windows-ent-cpc_win10-21h2-ent-cpc-m365-g2'
  'win-10-ent-22h2-os': 'microsoftwindowsdesktop_windows-ent-cpc_win10-22h2-ent-cpc-os'
  'win-10-ent-22h2-m365': 'microsoftwindowsdesktop_windows-ent-cpc_win10-22h2-ent-cpc-m365'

  // Windows 11
  'win-11-ent-21h2-os': 'microsoftwindowsdesktop_windows-ent-cpc_win11-21h2-ent-cpc-os'
  'win-11-ent-21h2-m365': 'microsoftwindowsdesktop_windows-ent-cpc_win11-21h2-ent-cpc-m365'
  'win-11-ent-22h2-os': 'microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc-os'
  'win-11-ent-22h2-m365': 'microsoftwindowsdesktop_windows-ent-cpc_win11-22h2-ent-cpc-m365'

  // Visual Studio 2019
  'vs-19-pro-win-10-m365': 'microsoftvisualstudio_visualstudio2019plustools_vs-2019-pro-general-win10-m365-gen2'
  'vs-19-ent-win-10-m365': 'microsoftvisualstudio_visualstudio2019plustools_vs-2019-ent-general-win10-m365-gen2'
  'vs-19-pro-win-11-m365': 'microsoftvisualstudio_visualstudio2019plustools_vs-2019-pro-general-win11-m365-gen2'
  'vs-19-ent-win-11-m365': 'microsoftvisualstudio_visualstudio2019plustools_vs-2019-ent-general-win11-m365-gen2'

  // Visual Studio 2022
  'vs-22-pro-win-10-m365': 'microsoftvisualstudio_visualstudioplustools_vs-2022-pro-general-win10-m365-gen2'
  'vs-22-ent-win-10-m365': 'microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win10-m365-gen2'
  'vs-22-pro-win-11-m365': 'microsoftvisualstudio_visualstudioplustools_vs-2022-pro-general-win11-m365-gen2'
  'vs-22-ent-win-11-m365': 'microsoftvisualstudio_visualstudioplustools_vs-2022-ent-general-win11-m365-gen2'
}

/*
module devCenterKeyVaultAccess '../security/keyvault-access.bicep' = if (!empty(keyVaultName)) {
  name: '${deployment().name}-keyvault-access'
  params: {
    keyVaultName: keyVaultName
    principalId: devcenter.identity.principalId
  }
}
*/

module diagnostics 'dev-center-diagnostics.bicep' = if (!empty(logWorkspaceName)) {
  name: '${deployment().name}-diagnostics'
  params: {
    devCenterName: devCenter.name
    logWorkspaceName: logWorkspaceName
  }
}
