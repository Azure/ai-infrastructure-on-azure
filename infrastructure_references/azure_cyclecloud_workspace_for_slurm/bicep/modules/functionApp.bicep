// ============================================================================
// Azure Function App Module
// Bridges Event Grid to Log Analytics via Data Collection Rule
// Includes inline code deployment via zip deployment
// ============================================================================

@description('Base name for resources')
param baseName string

@description('Azure region')
param location string

@description('Data Collection Endpoint logs ingestion URL')
param dceLogsIngestionEndpoint string

@description('Data Collection Rule immutable ID')
param dcrImmutableId string

@description('Tags to apply')
param tags object = {}

// Storage account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('stfn${replace(baseName, '-', '')}', 24)
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'asp-${baseName}'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Linux
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${baseName}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-${baseName}'
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      pythonVersion: '3.11'
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower('func-${baseName}')
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'DCE_ENDPOINT'
          value: dceLogsIngestionEndpoint
        }
        {
          name: 'DCR_IMMUTABLE_ID'
          value: dcrImmutableId
        }
        {
          name: 'LOG_STREAM_NAME'
          value: 'Custom-CycleCloudEvents_CL'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Blob container for function code deployment
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'function-releases'
  properties: {
    publicAccess: 'None'
  }
}

// Deployment script to create and upload the function zip
resource deployFunctionCode 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'deploy-function-${baseName}'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deploymentIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.50.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'FUNCTION_APP_NAME'
        value: functionApp.name
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
      {
        name: 'STORAGE_ACCOUNT'
        value: storageAccount.name
      }
      {
        name: 'CONTAINER_NAME'
        value: deploymentContainer.name
      }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e
      
      # Create function code files
      mkdir -p /tmp/functionapp/EventGridTrigger
      
      # host.json
      cat > /tmp/functionapp/host.json << 'HOSTJSON'
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
HOSTJSON

      # requirements.txt
      cat > /tmp/functionapp/requirements.txt << 'REQUIREMENTS'
azure-functions
azure-identity
azure-monitor-ingestion
REQUIREMENTS

      # function.json for Event Grid trigger
      cat > /tmp/functionapp/EventGridTrigger/function.json << 'FUNCTIONJSON'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "event",
      "direction": "in"
    }
  ]
}
FUNCTIONJSON

      # __init__.py - the main function code for Event Grid trigger
      cat > /tmp/functionapp/EventGridTrigger/__init__.py << 'INITPY'
"""
Azure Function: Event Grid to Log Analytics Bridge
Receives events directly from Event Grid and ingests to Log Analytics via DCR
"""
import azure.functions as func
import json
import logging
import os
from datetime import datetime

from azure.identity import DefaultAzureCredential
from azure.monitor.ingestion import LogsIngestionClient
from azure.core.exceptions import HttpResponseError

DCE_ENDPOINT = os.environ.get("DCE_ENDPOINT")
DCR_IMMUTABLE_ID = os.environ.get("DCR_IMMUTABLE_ID")
LOG_STREAM_NAME = os.environ.get("LOG_STREAM_NAME", "Custom-CycleCloudEvents_CL")


def transform_event(event: func.EventGridEvent) -> dict:
    """Transform Event Grid event to Log Analytics schema."""
    data = event.get_json() if event.get_json() else {}
    return {
        "TimeGenerated": event.event_time.isoformat() if event.event_time else datetime.utcnow().isoformat() + "Z",
        "EventType": event.event_type or "",
        "Subject": event.subject or "",
        "EventId": event.id or "",
        "DataVersion": event.data_version or "1",
        "Status": data.get("status", ""),
        "Reason": data.get("reason", ""),
        "Message": data.get("message", ""),
        "ErrorCode": data.get("errorCode", ""),
        "ClusterName": data.get("clusterName", ""),
        "NodeName": data.get("nodeName", ""),
        "NodeId": data.get("nodeId", ""),
        "NodeArray": data.get("nodeArray", ""),
        "ResourceId": data.get("resourceId", ""),
        "SubscriptionId": data.get("subscriptionId", ""),
        "Region": data.get("region", ""),
        "VmSku": data.get("vmSku", ""),
        "Priority": data.get("priority", ""),
        "PlacementGroupId": data.get("placementGroupId", ""),
        "RetryCount": data.get("retryCount", 0),
        "Timing": data.get("timing", {}),
        "EventData": data
    }


def main(event: func.EventGridEvent):
    """Process a single Event Grid event and ingest to Log Analytics."""
    if not DCE_ENDPOINT or not DCR_IMMUTABLE_ID:
        logging.error("DCE_ENDPOINT or DCR_IMMUTABLE_ID not configured")
        return

    logging.info(f"Processing event: {event.event_type} - {event.subject}")
    
    try:
        log_entry = transform_event(event)
        logs = [log_entry]
        
        credential = DefaultAzureCredential()
        client = LogsIngestionClient(endpoint=DCE_ENDPOINT, credential=credential)
        client.upload(rule_id=DCR_IMMUTABLE_ID, stream_name=LOG_STREAM_NAME, logs=logs)
        logging.info(f"Successfully ingested event {event.id} to Log Analytics")
    except HttpResponseError as e:
        logging.error(f"Failed to ingest log: {e.message}")
        raise
    except Exception as e:
        logging.error(f"Unexpected error during ingestion: {e}")
        raise
INITPY

      # Create zip file
      cd /tmp/functionapp
      zip -r /tmp/functionapp.zip .
      
      # Upload to blob storage
      az storage blob upload \
        --account-name $STORAGE_ACCOUNT \
        --container-name $CONTAINER_NAME \
        --name functionapp.zip \
        --file /tmp/functionapp.zip \
        --overwrite \
        --auth-mode login
      
      # Deploy to function app using zip deployment
      az functionapp deployment source config-zip \
        --resource-group $RESOURCE_GROUP \
        --name $FUNCTION_APP_NAME \
        --src /tmp/functionapp.zip
      
      echo "Function deployed successfully"
    '''
  }
  dependsOn: [
    roleAssignmentStorage
    roleAssignmentContributor
  ]
}

// User-assigned managed identity for deployment script
resource deploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-deploy-${baseName}'
  location: location
  tags: tags
}

// Role assignment: deployment identity needs Storage Blob Data Contributor on storage account
resource roleAssignmentStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, deploymentIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment: deployment identity needs Contributor on function app for deployment
resource roleAssignmentContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, deploymentIdentity.id, 'Contributor')
  scope: functionApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: deploymentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Function App resource ID')
output functionAppId string = functionApp.id

@description('Function App managed identity principal ID')
output functionAppPrincipalId string = functionApp.identity.principalId
