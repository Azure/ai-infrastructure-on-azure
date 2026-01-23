# CycleCloud Event Grid to Log Analytics Integration

This Bicep deployment creates an event pipeline that captures native Azure CycleCloud events (cluster and node lifecycle events) and streams them to Log Analytics for monitoring, alerting, and analysis.

CycleCloud publishes events to a **Custom Event Grid Topic** which you configure in the CycleCloud UI. Events are sent directly to an Azure Function (via Event Grid trigger) which ingests them to Log Analytics using the DCR Logs Ingestion API. This architecture avoids the cost of Event Hub (~$22/month savings).

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│     CycleCloud      │────>│ Event Grid Custom   │────>│   Azure Function    │
│  (Native Events)    │     │      Topic          │     │ (Event Grid Trigger)│
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
                                                                  │
                                    ┌─────────────────────────────┼─────────────────────────────┐
                                    │                             ▼                             │
                                    │                   ┌─────────────────────┐                 │
                                    │                   │ Data Collection Rule│                 │
                                    │                   │   (Logs Ingestion)  │                 │
                                    │                   └─────────────────────┘                 │
                                    │                             │                             │
                                    │                             ▼                             │
                                    │                   ┌─────────────────────┐                 │
                                    │                   │   Log Analytics     │                 │
                                    │                   │ (CycleCloudEvents)  │                 │
                                    │                   └─────────────────────┘                 │
                                    └───────────────────────────────────────────────────────────┘
```

## CycleCloud Event Types

CycleCloud publishes the following native event types:

### Cluster Events

| Event Type                                  | Description                          |
| ------------------------------------------- | ------------------------------------ |
| `Microsoft.CycleCloud.ClusterStarted`       | Cluster has been started             |
| `Microsoft.CycleCloud.ClusterTerminated`    | Cluster has been terminated          |
| `Microsoft.CycleCloud.ClusterDeleted`       | Cluster has been deleted             |
| `Microsoft.CycleCloud.ClusterSizeIncreased` | Nodes added to cluster (batch event) |

### Node Events

| Event Type                             | Description                           |
| -------------------------------------- | ------------------------------------- |
| `Microsoft.CycleCloud.NodeAdded`       | Node added to cluster (appears in UI) |
| `Microsoft.CycleCloud.NodeCreated`     | VM created for node (includes timing) |
| `Microsoft.CycleCloud.NodeDeallocated` | Node VM deallocated                   |
| `Microsoft.CycleCloud.NodeStarted`     | Node restarted from deallocated state |
| `Microsoft.CycleCloud.NodeTerminated`  | Node terminated and VM deleted        |

### Event Subject Patterns

Events have subjects in the following patterns for filtering:

- `/sites/SITENAME` - Site-level events
- `/sites/SITENAME/clusters/CLUSTERNAME` - Cluster-level events
- `/sites/SITENAME/clusters/CLUSTERNAME/nodes/NODENAME` - Node-level events

## Components

| Component                          | Purpose                                                          |
| ---------------------------------- | ---------------------------------------------------------------- |
| **Event Grid Custom Topic**        | Receives events published by CycleCloud                          |
| **Azure Function**                 | Triggered by Event Grid, ingests events to Log Analytics via DCR |
| **Data Collection Endpoint**       | Entry point for Azure Monitor data ingestion                     |
| **Data Collection Rule**           | Defines schema and routes events to Log Analytics                |
| **Log Analytics Workspace**        | Stores events in custom `CycleCloudEvents_CL` table              |
| **Storage Account**                | Hosts Function App files and deployment packages                 |
| **App Service Plan**               | Consumption plan for serverless Function App                     |
| **Application Insights**           | Monitors Function App performance and errors                     |
| **User-Assigned Managed Identity** | Used by deployment script to deploy function code                |
| **Deployment Script**              | Automatically deploys Python function code via Bicep             |

## Prerequisites

- Azure subscription with Contributor access
- Azure CLI 2.50+ or Azure PowerShell 10+
- Bicep CLI 0.22+ (included with Azure CLI)
- Existing CycleCloud deployment

## Deployment

### 1. Clone and Configure

```bash
# Navigate to the bicep directory
cd infrastructure_references/azure_cyclecloud_workspace_for_slurm/bicep

# Copy and edit parameters file
cp parameters.example.json parameters.json
```

Edit `parameters.json` with your values:

- `baseName`: Unique base name for resources (e.g., `ccw-prod-events`)
- `location`: Azure region (should match your CycleCloud region)

### 2. Deploy Resources

```bash
# Create resource group
az group create \
  --name cyclecloud-events \
  --location eastus2

# Deploy Bicep template with parameters file
az deployment group create \
  --resource-group cyclecloud-events \
  --template-file ccEventGrid.bicep \
  --parameters parameters.json

# Or deploy with inline parameters
az deployment group create \
  --resource-group cyclecloud-events \
  --template-file ccEventGrid.bicep \
  --parameters baseName='ccw-events' location='eastus2'
```

### 3. Get Event Grid Topic ID

```bash
# Get the Event Grid topic ID to configure in CycleCloud
az deployment group show \
  --resource-group cyclecloud-events \
  --name ccEventGrid \
  --query properties.outputs.eventGridTopicId.value -o tsv
```

### 4. Configure CycleCloud to Publish Events

1. Log in to the CycleCloud web UI
2. Click the **Settings** gear icon in the upper left
3. Double-click **CycleCloud** in the settings list
4. Select the Event Grid topic from the dropdown (it should appear automatically if CycleCloud has access)
5. Click **Save**

![CycleCloud Event Grid Configuration](https://learn.microsoft.com/en-us/azure/cyclecloud/images/event-grid-topic.png)

> **Note**: CycleCloud needs permission to publish to the Event Grid topic. Ensure the CycleCloud managed identity or service principal has the **EventGrid Data Sender** role on the topic.

### 5. Verify Deployment

The Function App code is automatically deployed via Bicep deployment script.

```bash
# Verify the function was deployed
az functionapp function list \
  --resource-group cyclecloud-events \
  --name func-ccw-events \
  --query "[].name" -o tsv

# Get all deployment outputs
az deployment group show \
  --resource-group cyclecloud-events \
  --name ccEventGrid \
  --query properties.outputs
```

## Log Analytics Queries

### View Recent Events

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| project TimeGenerated, EventType, ClusterName, NodeName, Status, Reason, Message
| order by TimeGenerated desc
| take 100
```

### Count Events by Type

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(7d)
| summarize Count=count() by EventType
| order by Count desc
```

### Failed Operations

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where Status == "Failed"
| project TimeGenerated, EventType, ClusterName, NodeName, Reason, ErrorCode, Message
| order by TimeGenerated desc
```

### Node Creation Timeline

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(1h)
| where EventType == "Microsoft.CycleCloud.NodeCreated"
| extend CreateTime = Timing.Create, VMCreateTime = Timing.CreateVM, ConfigureTime = Timing.Configure
| project TimeGenerated, ClusterName, NodeName, VmSku, Status, CreateTime, VMCreateTime, ConfigureTime
| order by TimeGenerated desc
```

### Check if a Node is Ready

Use this query to verify if a specific node has been successfully created and is ready:

```kql
let nodeToCheck = "gpu-pg0-1";  // Replace with your node name
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where NodeName == nodeToCheck
| where EventType == "Microsoft.CycleCloud.NodeCreated"
| where Status == "Succeeded"
| project TimeGenerated, ClusterName, NodeName, VmSku, Status, 
    VMCreateTime = Timing.CreateVM, 
    ConfigureTime = Timing.Configure,
    Message
| take 1
```

To check multiple nodes at once:

```kql
let nodesToCheck = dynamic(["gpu-pg0-1", "gpu-pg0-2", "hpc-pg0-1"]);  // Replace with your node names
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where NodeName in (nodesToCheck)
| where EventType == "Microsoft.CycleCloud.NodeCreated"
| summarize arg_max(TimeGenerated, Status, VmSku, Message) by ClusterName, NodeName
| extend IsReady = (Status == "Succeeded")
| project ClusterName, NodeName, VmSku, LastEvent = TimeGenerated, Status, IsReady, Message
| order by NodeName asc
```

### Average VM Creation and Configuration Time

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where EventType == "Microsoft.CycleCloud.NodeCreated"
| where Status == "Succeeded"
| extend VMCreateSeconds = todouble(Timing.CreateVM), ConfigureSeconds = todouble(Timing.Configure)
| where isnotnull(VMCreateSeconds) and isnotnull(ConfigureSeconds)
| summarize
    TotalNodes = count(),
    AvgVMCreate = avg(VMCreateSeconds),
    MinVMCreate = min(VMCreateSeconds),
    MaxVMCreate = max(VMCreateSeconds),
    StdDevVMCreate = stdev(VMCreateSeconds),
    AvgConfigure = avg(ConfigureSeconds),
    MinConfigure = min(ConfigureSeconds),
    MaxConfigure = max(ConfigureSeconds),
    StdDevConfigure = stdev(ConfigureSeconds)
  by ClusterName, VmSku
| project ClusterName, VmSku, TotalNodes,
    AvgVMCreate = round(AvgVMCreate, 1),
    MinVMCreate = round(MinVMCreate, 1),
    MaxVMCreate = round(MaxVMCreate, 1),
    StdDevVMCreate = round(StdDevVMCreate, 1),
    AvgConfigure = round(AvgConfigure, 1),
    MinConfigure = round(MinConfigure, 1),
    MaxConfigure = round(MaxConfigure, 1),
    StdDevConfigure = round(StdDevConfigure, 1)
| order by TotalNodes desc
```

### Spot VM Evictions

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where Reason == "SpotEvicted"
| project TimeGenerated, ClusterName, NodeName, VmSku, Region
| order by TimeGenerated desc
```

### Cluster Scaling Activity

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(1h)
| where EventType == "Microsoft.CycleCloud.ClusterSizeIncreased"
| extend NodesRequested = EventData.nodesRequested, NodesAdded = EventData.nodesAdded
| project TimeGenerated, ClusterName, NodeArray, VmSku, Priority, NodesRequested, NodesAdded
| order by TimeGenerated desc
```

### Node Lifecycle Duration

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(24h)
| where EventType == "Microsoft.CycleCloud.NodeTerminated"
| extend StartedDuration = tostring(Timing.Started)
| where isnotempty(StartedDuration)
| project TimeGenerated, ClusterName, NodeName, VmSku, Priority, StartedDuration, Reason
| order by TimeGenerated desc
```

### Events by Cluster

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(7d)
| summarize
    NodeCreated=countif(EventType == "Microsoft.CycleCloud.NodeCreated"),
    NodeTerminated=countif(EventType == "Microsoft.CycleCloud.NodeTerminated"),
    Failed=countif(Status == "Failed")
  by ClusterName
| order by NodeCreated desc
```

### Cluster Start Events

```kql
CycleCloudEvents_CL
| where TimeGenerated > ago(7d)
| where EventType == "Microsoft.CycleCloud.ClusterStarted"
| project TimeGenerated, ClusterName, Status, Message
| order by TimeGenerated desc
```

## Alerting

Create alerts based on Log Analytics queries:

```bash
# Example: Alert on failed operations
az monitor scheduled-query create \
  --name "CycleCloud Failed Operations" \
  --resource-group cyclecloud-events \
  --scopes "/subscriptions/<sub-id>/resourceGroups/cyclecloud-events/providers/Microsoft.OperationalInsights/workspaces/law-ccw-events" \
  --condition "count > 0" \
  --condition-query "CycleCloudEvents_CL | where TimeGenerated > ago(15m) | where Status == 'Failed'" \
  --evaluation-frequency 5m \
  --window-size 15m \
  --severity 2 \
  --action-groups "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Insights/actionGroups/<ag>"
```

## Custom Table Schema

The `CycleCloudEvents_CL` table has the following schema optimized for CycleCloud events:

| Column             | Type     | Description                                                      |
| ------------------ | -------- | ---------------------------------------------------------------- |
| `TimeGenerated`    | datetime | Event timestamp                                                  |
| `EventType`        | string   | CycleCloud event type (e.g., `Microsoft.CycleCloud.NodeCreated`) |
| `Subject`          | string   | Event subject path                                               |
| `EventId`          | string   | Unique event identifier                                          |
| `DataVersion`      | string   | Schema version                                                   |
| `Status`           | string   | Succeeded, Failed, or Canceled                                   |
| `Reason`           | string   | Event reason (Autoscaled, UserInitiated, SpotEvicted, etc.)      |
| `Message`          | string   | Human-readable summary                                           |
| `ErrorCode`        | string   | Error code if failed                                             |
| `ClusterName`      | string   | Cluster name                                                     |
| `NodeName`         | string   | Node name                                                        |
| `NodeId`           | string   | Unique node identifier                                           |
| `NodeArray`        | string   | Nodearray name                                                   |
| `ResourceId`       | string   | Azure VM resource ID                                             |
| `SubscriptionId`   | string   | Azure subscription ID                                            |
| `Region`           | string   | Azure region                                                     |
| `VmSku`            | string   | VM size/SKU                                                      |
| `Priority`         | string   | regular or spot                                                  |
| `PlacementGroupId` | string   | Placement group ID                                               |
| `RetryCount`       | int      | Retry attempts                                                   |
| `Timing`           | dynamic  | Event timing stages (Create, CreateVM, Configure, etc.)          |
| `EventData`        | dynamic  | Full event payload                                               |

## Event Ingestion

To manually ingest events (useful for testing or custom event sources), use the Data Collection Endpoint:

```bash
# Get the logs ingestion endpoint from deployment outputs
DCE_ENDPOINT=$(az deployment group show \
  --resource-group cyclecloud-events \
  --name ccEventGrid \
  --query properties.outputs.dataCollectionEndpointLogsIngestion.value -o tsv)

DCR_IMMUTABLE_ID=$(az deployment group show \
  --resource-group cyclecloud-events \
  --name ccEventGrid \
  --query properties.outputs.dataCollectionRuleImmutableId.value -o tsv)

# Send test event
curl -X POST "${DCE_ENDPOINT}/dataCollectionRules/${DCR_IMMUTABLE_ID}/streams/Custom-CycleCloudEvents_CL?api-version=2023-01-01" \
  -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" \
  -H "Content-Type: application/json" \
  -d '[{
    "TimeGenerated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "EventType": "Test.Event",
    "Subject": "/subscriptions/test/resourceGroups/test",
    "EventId": "'$(uuidgen)'",
    "ResourceId": "/subscriptions/test/resourceGroups/test",
    "OperationName": "Test Operation",
    "Status": "Succeeded",
    "EventData": {"test": "data"}
  }]'
```

## Cost Considerations

| Component                  | Pricing Model                                            |
| -------------------------- | -------------------------------------------------------- |
| Event Grid                 | Per million operations (~$0.60/million)                  |
| Log Analytics              | Per GB ingested + retention (~$2.76/GB)                  |
| Data Collection            | Included with Log Analytics                              |
| Function App (Consumption) | Per execution + GB-seconds (~$0.01/month for low volume) |
| Storage Account            | Per GB stored + transactions (~$0.50/month)              |
| Application Insights       | Per GB ingested (~$0.10/month for low volume)            |

For typical CycleCloud workloads (100-1000 events/day), expect:

- Event Grid: ~$0.01/month
- Log Analytics: ~$2.76/GB ingested
- Function App: ~$0.01/month (consumption tier, low volume)
- Storage Account: ~$0.50/month
- Application Insights: ~$0.10/month

**Total estimated cost: ~$3-5/month** (much lower than with Event Hub)

## Troubleshooting

### Events Not Appearing in Log Analytics

1. **Verify CycleCloud is publishing events**: Check the CycleCloud logs or trigger a test action (add a node to a cluster).

2. Check Event Grid topic metrics:

   ```bash
   az monitor metrics list \
     --resource "/subscriptions/<sub>/resourceGroups/cyclecloud-events/providers/Microsoft.EventGrid/topics/evgt-ccw-events-cyclecloud" \
     --metric "PublishSuccessCount" \
     --interval PT1H
   ```

3. Verify DCR is healthy:

   ```bash
   az monitor data-collection rule show \
     --resource-group cyclecloud-events \
     --name dcr-ccw-events-cyclecloud-events
   ```

4. Check Function App logs:

   ```bash
   az functionapp log tail \
     --resource-group cyclecloud-events \
     --name func-ccw-events
   ```

5. Check Application Insights for function errors:
   ```bash
   az monitor app-insights query \
     --app appi-ccw-events \
     --resource-group cyclecloud-events \
     --analytics-query "exceptions | where timestamp > ago(1h) | project timestamp, problemId, outerMessage"
   ```

### CycleCloud Can't See Event Grid Topic

Ensure CycleCloud has the appropriate permissions:

```bash
# Get the Event Grid topic resource ID
TOPIC_ID=$(az eventgrid topic show \
  --resource-group cyclecloud-events \
  --name evgt-ccw-events-cyclecloud \
  --query id -o tsv)

# Assign Event Grid Data Sender role to CycleCloud's managed identity
az role assignment create \
  --role "EventGrid Data Sender" \
  --assignee <cyclecloud-managed-identity-principal-id> \
  --scope $TOPIC_ID
```

## Cleanup

```bash
# Delete all resources
az group delete --name cyclecloud-events --yes --no-wait
```

## Related Documentation

- [Azure Event Grid Documentation](https://learn.microsoft.com/azure/event-grid/)
- [Azure Event Hubs Documentation](https://learn.microsoft.com/azure/event-hubs/)
- [Azure Monitor Data Collection Rules](https://learn.microsoft.com/azure/azure-monitor/essentials/data-collection-rule-overview)
- [Log Analytics Custom Tables](https://learn.microsoft.com/azure/azure-monitor/logs/create-custom-table)
- [CycleCloud Documentation](https://learn.microsoft.com/azure/cyclecloud/)
