// ============================================================================
// Log Analytics Workspace Module
// ============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Azure region')
param location string

@description('Retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Tags to apply')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Custom table for CycleCloud events
resource cycleCloudEventsTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: logAnalyticsWorkspace
  name: 'CycleCloudEvents_CL'
  properties: {
    totalRetentionInDays: retentionInDays
    plan: 'Analytics'
    schema: {
      name: 'CycleCloudEvents_CL'
      columns: [
        {
          name: 'TimeGenerated'
          type: 'datetime'
          description: 'Event timestamp'
        }
        {
          name: 'EventType'
          type: 'string'
          description: 'CycleCloud event type (e.g., Microsoft.CycleCloud.NodeCreated)'
        }
        {
          name: 'Subject'
          type: 'string'
          description: 'Event subject path (e.g., /sites/SITENAME/clusters/CLUSTERNAME/nodes/NODENAME)'
        }
        {
          name: 'EventId'
          type: 'string'
          description: 'Unique event identifier'
        }
        {
          name: 'DataVersion'
          type: 'string'
          description: 'Schema version for data property'
        }
        // Common CycleCloud event data properties
        {
          name: 'Status'
          type: 'string'
          description: 'Event status: Succeeded, Failed, or Canceled'
        }
        {
          name: 'Reason'
          type: 'string'
          description: 'Reason for event: Autoscaled, UserInitiated, System, SpotEvicted, VMDisappeared, AllocationFailed'
        }
        {
          name: 'Message'
          type: 'string'
          description: 'Human-readable summary of the event'
        }
        {
          name: 'ErrorCode'
          type: 'string'
          description: 'Error code if operation failed'
        }
        // Cluster properties
        {
          name: 'ClusterName'
          type: 'string'
          description: 'Name of the cluster'
        }
        // Node properties
        {
          name: 'NodeName'
          type: 'string'
          description: 'Name of the node'
        }
        {
          name: 'NodeId'
          type: 'string'
          description: 'Unique node identifier'
        }
        {
          name: 'NodeArray'
          type: 'string'
          description: 'Nodearray the node was created from'
        }
        {
          name: 'ResourceId'
          type: 'string'
          description: 'Azure VM resource ID'
        }
        {
          name: 'SubscriptionId'
          type: 'string'
          description: 'Azure subscription ID'
        }
        {
          name: 'Region'
          type: 'string'
          description: 'Azure region'
        }
        {
          name: 'VmSku'
          type: 'string'
          description: 'VM SKU/size'
        }
        {
          name: 'Priority'
          type: 'string'
          description: 'VM priority: regular or spot'
        }
        {
          name: 'PlacementGroupId'
          type: 'string'
          description: 'Placement group ID if applicable'
        }
        {
          name: 'RetryCount'
          type: 'int'
          description: 'Number of retry attempts'
        }
        // Timing information (stored as JSON for flexibility)
        {
          name: 'Timing'
          type: 'dynamic'
          description: 'Timing information for the event stages'
        }
        // Full event payload
        {
          name: 'EventData'
          type: 'dynamic'
          description: 'Full event data payload as JSON'
        }
      ]
    }
  }
}

@description('Log Analytics Workspace resource ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace name')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace customer ID (for queries)')
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Custom table name for CycleCloud events')
output customTableName string = cycleCloudEventsTable.name
