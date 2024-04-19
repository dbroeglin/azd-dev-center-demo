@description('The dev center name')
param devCenterName string

@description('The project name')
param name string

@description('The environment types to create')
param environmentTypes environmentType[]

@description('The members to give access to the project')
param members memberRoleAssignment[]

@description('The location of the resource')
param location string = resourceGroup().location

@description('The tags of the resource')
param tags object = {}

@description('The maximum number of dev boxes per user in this project')
param maxDevBoxesPerUser int = 50

@description('The Dev Box pools to create')
param pools devBoxPool[]

type devBoxPool = {
  name: string
  definition: string

  @description('[NOT IMPLEMENTED] The grace period in minutes before the Dev Box is stopped after the user disconnects')
  @minValue(60)
  @maxValue(480)
  gracePeriodMinutes: int?
}

type environmentType = {
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

resource devCenter 'Microsoft.DevCenter/devcenters@2023-04-01' existing = {
  name: devCenterName
}

resource project 'Microsoft.DevCenter/projects@2023-04-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    devCenterId: devCenter.id
    maxDevBoxesPerUser: maxDevBoxesPerUser
  }
}

module pool 'dev-center-project-pool.bicep' = [for pool in pools: {
  name: '${deployment().name}-pool-${pool.name}'
  params: {
    name: pool.name
    location: location
    projectName: project.name
    config: pool
  }
}]

/*
// Default roles for environment type will be owner unless explicitly specified
var defaultEnvironmentTypeRoles = [ 'Owner' ]

module projectEnvType 'project-environment-type.bicep' = [for envType in environmentTypes: {
  name: '${deployment().name}-${envType.name}'
  params: {
    devCenterName: devCenterName
    projectName: project.name
    deploymentTargetId: envType.deploymentTargetId
    name: envType.name
    location: location
    tags: envType.tags == null ? {} : envType.tags
    roles: !empty(envType.roles) ? envType.roles : defaultEnvironmentTypeRoles
    members: !empty(envType.members) ? envType.members : []
  }
}]
*/

var roleResourceIDs = {
  'Deployment Environments User': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18e40d4e-8d2e-438d-97e1-9528336e149c')
  'DevCenter Project Admin': subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '331c37c6-af14-46d9-b9f4-e1909e1b95a0')
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for member in members: {
  name: guid(project.id, roleResourceIDs[member.role], member.user)
  scope: project
  properties: {
    principalId: member.user
    roleDefinitionId: roleResourceIDs[member.role]
  }
}]
