// ============================================================================
// Data Collection Endpoint and Data Collection Rule Module
// Ingests CycleCloud events into Log Analytics via DCR Logs Ingestion API
// ============================================================================

@description('Base name for resources')
param baseName string

@description('Azure region')
param location string

@description('Log Analytics Workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Tags to apply')
param tags object = {}

// Data Collection Endpoint
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: 'dce-${baseName}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    description: 'Data Collection Endpoint for CycleCloud events'
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Data Collection Rule for Event Hub to Log Analytics
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-${baseName}-cyclecloud-events'
  location: location
  tags: tags
  kind: 'Direct'
  properties: {
    description: 'DCR for ingesting CycleCloud events from Event Hub to Log Analytics'
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-CycleCloudEvents_CL': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'EventType'
            type: 'string'
          }
          {
            name: 'Subject'
            type: 'string'
          }
          {
            name: 'EventId'
            type: 'string'
          }
          {
            name: 'DataVersion'
            type: 'string'
          }
          {
            name: 'Status'
            type: 'string'
          }
          {
            name: 'Reason'
            type: 'string'
          }
          {
            name: 'Message'
            type: 'string'
          }
          {
            name: 'ErrorCode'
            type: 'string'
          }
          {
            name: 'ClusterName'
            type: 'string'
          }
          {
            name: 'NodeName'
            type: 'string'
          }
          {
            name: 'NodeId'
            type: 'string'
          }
          {
            name: 'NodeArray'
            type: 'string'
          }
          {
            name: 'ResourceId'
            type: 'string'
          }
          {
            name: 'SubscriptionId'
            type: 'string'
          }
          {
            name: 'Region'
            type: 'string'
          }
          {
            name: 'VmSku'
            type: 'string'
          }
          {
            name: 'Priority'
            type: 'string'
          }
          {
            name: 'PlacementGroupId'
            type: 'string'
          }
          {
            name: 'RetryCount'
            type: 'int'
          }
          {
            name: 'Timing'
            type: 'dynamic'
          }
          {
            name: 'EventData'
            type: 'dynamic'
          }
        ]
      }
    }
    dataSources: {}
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspaceId
          name: 'logAnalyticsDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Custom-CycleCloudEvents_CL'
        ]
        destinations: [
          'logAnalyticsDestination'
        ]
        transformKql: 'source'
        outputStream: 'Custom-CycleCloudEvents_CL'
      }
    ]
  }
}

@description('Data Collection Endpoint resource ID')
output dataCollectionEndpointId string = dataCollectionEndpoint.id

@description('Data Collection Endpoint name')
output dataCollectionEndpointName string = dataCollectionEndpoint.name

@description('Data Collection Endpoint configuration access endpoint')
output dataCollectionEndpointConfigurationAccess string = dataCollectionEndpoint.properties.configurationAccess.endpoint

@description('Data Collection Endpoint logs ingestion endpoint')
output dataCollectionEndpointLogsIngestion string = dataCollectionEndpoint.properties.logsIngestion.endpoint

@description('Data Collection Rule resource ID')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Data Collection Rule name')
output dataCollectionRuleName string = dataCollectionRule.name

@description('Data Collection Rule immutable ID')
output dataCollectionRuleImmutableId string = dataCollectionRule.properties.immutableId
