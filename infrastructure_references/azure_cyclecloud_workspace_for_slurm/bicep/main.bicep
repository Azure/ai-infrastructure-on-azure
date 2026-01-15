// ============================================================================
// CycleCloud Event Grid to Log Analytics Integration
// Direct Event Grid to Function App pipeline (no Event Hub)
// 
// CycleCloud publishes native events (NodeCreated, ClusterStarted, etc.) to
// a Custom Event Grid Topic. Events are sent directly to Azure Function
// which ingests them to Log Analytics via DCR.
// ============================================================================

targetScope = 'resourceGroup'

@description('Base name for all resources')
param baseName string

@description('Azure region for resources')
param location string = resourceGroup().location

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 90

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// Modules
// ============================================================================

module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'logAnalytics-${baseName}'
  params: {
    name: 'law-${baseName}'
    location: location
    retentionInDays: logRetentionDays
    tags: tags
  }
}

module dataCollection 'modules/dataCollection.bicep' = {
  name: 'dataCollection-${baseName}'
  params: {
    baseName: baseName
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// Function App to receive Event Grid events and ingest to Log Analytics
module functionApp 'modules/functionApp.bicep' = {
  name: 'functionApp-${baseName}'
  params: {
    baseName: baseName
    location: location
    dceLogsIngestionEndpoint: dataCollection.outputs.dataCollectionEndpointLogsIngestion
    dcrImmutableId: dataCollection.outputs.dataCollectionRuleImmutableId
    tags: tags
  }
}

// Event Grid with subscription to Function App (must be created after function app)
module eventGrid 'modules/eventGrid.bicep' = {
  name: 'eventGrid-${baseName}'
  params: {
    baseName: baseName
    location: location
    functionAppId: functionApp.outputs.functionAppId
    tags: tags
  }
}

// Role assignment: Function App needs Monitoring Metrics Publisher role on DCR
resource dcrRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'func-${baseName}', 'Monitoring Metrics Publisher')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb') // Monitoring Metrics Publisher
    principalId: functionApp.outputs.functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalytics.outputs.workspaceName

@description('Data Collection Endpoint ID')
output dataCollectionEndpointId string = dataCollection.outputs.dataCollectionEndpointId

@description('Data Collection Rule ID')
output dataCollectionRuleId string = dataCollection.outputs.dataCollectionRuleId

@description('Data Collection Rule Immutable ID')
output dataCollectionRuleImmutableId string = dataCollection.outputs.dataCollectionRuleImmutableId

@description('Data Collection Endpoint Logs Ingestion URL')
output dataCollectionEndpointLogsIngestion string = dataCollection.outputs.dataCollectionEndpointLogsIngestion

@description('Event Grid Custom Topic ID')
output eventGridTopicId string = eventGrid.outputs.topicId

@description('Event Grid Custom Topic Endpoint - Configure this in CycleCloud Settings')
output eventGridTopicEndpoint string = eventGrid.outputs.topicEndpoint

@description('Event Grid Subscription ID')
output eventGridSubscriptionId string = eventGrid.outputs.subscriptionId

@description('Function App Name')
output functionAppName string = functionApp.outputs.functionAppName

@description('Function App Principal ID')
output functionAppPrincipalId string = functionApp.outputs.functionAppPrincipalId
