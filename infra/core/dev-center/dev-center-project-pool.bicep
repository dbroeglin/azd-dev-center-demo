@description('The pool name')
param name string

@description('The parent project name')
param projectName string

@description('The location of the resource')
param location string = resourceGroup().location

@description('The tags of the resource')
param tags object = {}

@description('Dev Box pool configuration')
param config devBoxPool

type devBoxPool = {
  name: string
  definition: string

  @description('[NOT IMPLEMENTED] The grace period in minutes before the Dev Box is stopped after the user disconnects')
  @minValue(60)
  @maxValue(480)
  gracePeriodMinutes: int?
}

resource project 'Microsoft.DevCenter/projects@2023-10-01-preview' existing = {
  name: projectName
}

resource pool 'Microsoft.DevCenter/projects/pools@2023-10-01-preview' = {
  name: name
  location: location
  tags: tags
  parent: project
  properties: {
    devBoxDefinitionName: config.definition
    licenseType: 'Windows_Client'
    localAdministrator: 'Enabled' // TODO
    virtualNetworkType: 'Managed'
    managedVirtualNetworkRegions: [ location ]
    networkConnectionName: 'managedNetwork'
  } 
  
  resource schedule 'schedules@2023-10-01-preview' = {
    name: 'default'
    properties: {
      frequency: 'Daily'
      state: 'Enabled'
      time: '19:00'
      timeZone: 'Europe/Paris'
      type: 'StopDevBox'
    }
  }
}
