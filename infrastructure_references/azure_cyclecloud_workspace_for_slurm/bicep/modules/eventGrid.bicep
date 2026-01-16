// ============================================================================
// Event Grid Custom Topic and Subscription Module
// CycleCloud publishes native events to a Custom Topic
// Events are routed directly to Azure Function for processing into Log Analytics
// ============================================================================

@description('Base name for resources')
param baseName string

@description('Azure region')
param location string

@description('Function App resource ID for Event Grid subscription')
param functionAppId string

@description('Tags to apply')
param tags object = {}

// CycleCloud native event types
var cycleCloudEventTypes = [
  // Cluster events
  'Microsoft.CycleCloud.ClusterStarted'
  'Microsoft.CycleCloud.ClusterTerminated'
  'Microsoft.CycleCloud.ClusterDeleted'
  'Microsoft.CycleCloud.ClusterSizeIncreased'
  // Node events
  'Microsoft.CycleCloud.NodeAdded'
  'Microsoft.CycleCloud.NodeCreated'
  'Microsoft.CycleCloud.NodeDeallocated'
  'Microsoft.CycleCloud.NodeStarted'
  'Microsoft.CycleCloud.NodeTerminated'
]

// Event Grid Custom Topic - CycleCloud will publish events here
resource customTopic 'Microsoft.EventGrid/topics@2024-06-01-preview' = {
  name: 'evgt-${baseName}-cyclecloud'
  location: location
  tags: tags
  properties: {
    inputSchema: 'EventGridSchema'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    dataResidencyBoundary: 'WithinGeopair'
  }
}

// Event Grid Subscription to route events to Azure Function
resource eventSubscription 'Microsoft.EventGrid/topics/eventSubscriptions@2024-06-01-preview' = {
  parent: customTopic
  name: 'evgs-${baseName}-to-function'
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionAppId}/functions/EventGridTrigger'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: cycleCloudEventTypes
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

@description('Event Grid Custom Topic ID - Configure this in CycleCloud Settings')
output topicId string = customTopic.id
