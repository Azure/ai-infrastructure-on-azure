# Deploying Azure CycleCloud Workspace for Slurm

## Table of Contents

1. [Overview](#1-overview)
2. [Prerequisites](#2-prerequisites)
3. [Deployment with deploy-ccws.sh](#3-deployment-with-deploy-ccwssh)
   1. [Basic Usage](#31-basic-usage)
   2. [Selecting Availability Zones](#32-selecting-availability-zones)
   3. [Example With Marketplace Acceptance and Automatic Deployment](#33-example-with-marketplace-acceptance-and-automatic-deployment)
   4. [Generated Artifacts](#34-generated-artifacts)
   5. [Optional Parameters](#35-optional-parameters)
   6. [Script Reference (Docstring Style)](#36-script-reference-docstring-style)
   7. [Non-Interactive Deployment](#37-non-interactive-deployment)
   8. [Re-Running / Modifying](#38-re-running--modifying)
   9. [Troubleshooting](#39-troubleshooting)
   10. [Manual Deployment (Optional)](#310-manual-deployment-optional)

## 1. Overview

This section of the repository contains the guidance to deploy Azure CycleCloud
Workspace for Slurm environments.

The templates contained in this folder have some deployment examples with
different features and storage types.

The deployment guide follows what described in the
[official Azure CycleCloud Workspace for Slurm documentation pages](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/ccws/deploy-with-cli?view=cyclecloud-8).

## 2. Prerequisites

In order to deploy the infrastructure described in this section of the guide in
an existing Azure Subscription, be sure to have:

- A working installation of
  [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
- Contributor on the Subscription
- User Access Administrator on the Subscription
- Be sure that `az account show` is displaying the right subscription. In case,
  fix the subscription with
  `az account set --subscription "your-subscription-name"`

## 3. Deployment with `deploy-ccws.sh`

Instead of manually editing and generating a parameters JSON file, this
repository provides an automation helper script: `scripts/deploy-ccws.sh`. The
script:

- Clones the official Azure CycleCloud Workspace for Slurm repository at a
  chosen ref/commit.

> [!WARNING] This guide intentionally uses a **specific commit SHA** of the
> Azure CycleCloud Workspace for Slurm repository to pull in hotfixes that may
> not yet be part of the latest tagged release. Pinning the commit ensures
> reproducible deployments and avoids regressions from upstream changes. If user
> switches to `--workspace-ref main` without a `--workspace-commit` override
> user may pick up newer code paths that have not been validated in this
> environment. Always re-run validation (storage mounts, Slurm job submission,
> NCCL tests) after changing the commit. Default **workspace reference** in the
> current repository is the `main` branch of the Azure CycleCloud Workspace for
> Slurm repository.

- User can specify a specific `commit-id` or `branch` for checkout.
- Builds an `output.json` parameters file for the Bicep template.
- Optionally prompts for availability zones only if the region supports zonal
  SKUs.
- Can immediately deploy the environment (or let user review first).

### 3.1. Basic Usage

```bash
./scripts/deploy-ccws.sh \
  --subscription-id <sub-id> \
  --resource-group <rg-name> \
  --location <region> \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 \
  --hpc-sku Standard_HB176rs_v4 \
  --gpu-sku Standard_ND96amsr_A100_v4 \
  --specify-az
```

User will be interactively prompted for availability zones only if:

1. User supplied `--specify-az`, and
2. The region contains at least one zonal-capable VM SKU (auto-detected via
   `az vm list-skus`).
3. If availability zones are specified using the CLI commands for each partition
   and for storage, it will not prompt for them.

If the region does not support zones (or `az`/`jq` are missing), the script will
fall back silently to non-zonal deployment and produce empty `availabilityZone`
arrays.

### 3.2. Selecting Availability Zones

Choosing an Availability Zone impacts both **storage latency** and **overall
workload performance**:

- Co-locate compute partitions (HTC/HPC/GPU) with shared storage (ANF / AMLFS)
  in the **same zone** whenever possible to minimize cross-zone latency.
- Cross-zone access can introduce higher I/O latency for metadata-heavy or
  small-block operations.

When prompted, press Enter to skip (no zone) or provide a number like `1`. For
ANF and AMLFS, the script uses manual prompts because their zone capabilities
are not derived from the VM SKU query. If user skips, the deployment uses
region-level (non-zonal) placement. AMLFS will default to zone `1`.

### 3.3. Example With Marketplace Acceptance and Automatic Deployment

```bash
./scripts/deploy-ccws.sh \
  --subscription-id <sub-id> \
  --resource-group <rg-name> \
  --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 \
  --hpc-sku Standard_HB176rs_v4 \
  --gpu-sku Standard_ND96amsr_A100_v4 \
  --anf-sku Premium --anf-size 2 \
  --data-filesystem --amlfs-sku AMLFS-Durable-Premium-500 --amlfs-size 4 \
  --accept-marketplace \
  --deploy
```

### 3.4. Generated Artifacts

- `output.json` – parameter file used for the Bicep deployment.
- Random deployment name previewed in the summary section.
- Summary of chosen SKUs and zones printed for validation.

### 3.5. Optional Parameters

The `deploy-ccws.sh` script supports numerous optional flags to customize the
deployment. Below is a comprehensive reference for all available optional
parameters:

#### General Configuration

- **`--admin-username <username>`** (default: `hpcadmin`)
  - Username for the CycleCloud administrator account
  - Used for SSH access and CycleCloud UI login

#### CycleCloud Infrastructure SKUs

- **`--scheduler-sku <sku>`** (default: `Standard_D4as_v5`)

  - VM SKU for the CycleCloud scheduler node
  - Controls the scheduler's compute capacity

- **`--login-sku <sku>`** (default: `Standard_D2as_v5`)
  - VM SKU for the login node
  - Entry point for users to access the cluster

#### Workspace Repository Configuration

- **`--workspace-ref <branch|tag>`** (default: `main`)

  - Git reference (branch or tag) to checkout from the Azure CycleCloud
    Workspace for Slurm repository
  - Examples: `main`, `v2025.09.15`, `feature-branch`

- **`--workspace-commit <sha>`**

  - Pin to a specific commit SHA (creates detached HEAD)
  - Overrides `--workspace-ref` if both are provided
  - Recommended for reproducible deployments
  - Example: `a1b2c3d4e5f6...`

- **`--workspace-dir <path>`**
  - Directory where the workspace repository will be cloned
  - Default: `./cyclecloud-slurm-workspace` under script directory
  - Useful for managing multiple workspace versions

#### Availability Zones

- **`--no-az`**

  - Explicitly disable availability zones for all resources (default behavior)
  - When set, all availability zone configurations are omitted from deployment
  - This is the default if neither `--no-az` nor `--specify-az` is provided

- **`--specify-az`**

  - Enable interactive prompts for availability zones
  - Only prompts if the region supports zonal SKUs
  - Mutually exclusive with `--no-az`

- **`--htc-az <zone>`**

  - Explicitly set availability zone for HTC partition (e.g., `1`, `2`, `3`)
  - Suppresses interactive prompt for HTC partition
  - Requires `--specify-az` to be set

- **`--hpc-az <zone>`**

  - Explicitly set availability zone for HPC partition
  - Suppresses interactive prompt for HPC partition
  - Requires `--specify-az` to be set

- **`--gpu-az <zone>`**
  - Explicitly set availability zone for GPU partition
  - Suppresses interactive prompt for GPU partition
  - Requires `--specify-az` to be set

#### Compute Partition Configuration

- **`--htc-max-nodes <count>`**

  - Maximum number of nodes for HTC (High Throughput Computing) partition
  - Must be a positive integer
  - Interactive prompt if omitted

- **`--hpc-max-nodes <count>`**

  - Maximum number of nodes for HPC (High Performance Computing) partition
  - Must be a positive integer
  - Interactive prompt if omitted

- **`--gpu-max-nodes <count>`**

  - Maximum number of nodes for GPU partition
  - Must be a positive integer
  - Interactive prompt if omitted

- **`--htc-use-spot`**
  - Use Azure Spot (preemptible) VMs for HTC partition
  - Flag parameter (no value required)
  - Default: disabled (use regular on-demand VMs)
  - Provides cost savings with interruption tolerance

- **`--slurm-no-start`**
  - Do not start the Slurm cluster automatically after deployment
  - Flag parameter (no value required)
  - Default: cluster starts automatically
  - Useful when you want to configure the cluster before starting it

#### Network Configuration

- **`--network-address-space <cidr>`** (default: `10.0.0.0/24`)

  - Virtual network CIDR address space
  - Must be valid CIDR notation
  - Example: `10.1.0.0/16`

- **`--bastion`**
  - Enable Azure Bastion deployment
  - Flag parameter (no value required)
  - Default: disabled
  - Provides secure RDP/SSH access without public IPs

#### Azure NetApp Files (ANF) Configuration

All ANF parameters must be provided together to enable ANF storage:

- **`--anf-sku <sku>`** (default: `Premium`)

  - ANF service level: `Standard`, `Premium`, or `Ultra`
  - Determines performance tier and pricing
  - Example: `Premium`

- **`--anf-size <size_in_TiB>`** (default: `2`)

  - Capacity pool size in TiB (minimum: 2 TiB)
  - Must be an integer ≥ 1
  - Example: `4` for 4 TiB

- **`--anf-az <zone>`**
  - Availability zone for ANF deployment
  - Should match compute partition zones for optimal latency
  - Example: `1`

#### Azure Managed Lustre File System (AMLFS) Configuration

AMLFS provides an additional high-performance data filesystem. It is **disabled by default**.

- **`--data-filesystem`**

  - Enable Azure Managed Lustre data filesystem
  - Flag parameter (no value required)
  - Default: disabled
  - When enabled, AMLFS will be deployed with the parameters below

- **`--amlfs-sku <sku>`** (default: `AMLFS-Durable-Premium-500`)

  - AMLFS SKU type (only used when `--data-filesystem` is enabled)
  - Available options: `AMLFS-Durable-Premium-40`, `AMLFS-Durable-Premium-125`,
    `AMLFS-Durable-Premium-250`, `AMLFS-Durable-Premium-500`
  - Number indicates MB/s/TiB throughput
  - Example: `AMLFS-Durable-Premium-500`

- **`--amlfs-size <size_in_TiB>`** (default: `4`)

  - File system size in TiB (only used when `--data-filesystem` is enabled)
  - Must be an integer ≥ 4 TiB
  - Example: `8` for 8 TiB

- **`--amlfs-az <zone>`**
  - Availability zone for AMLFS deployment (only used when `--data-filesystem` is enabled)
  - Defaults to zone `1` if not specified
  - Example: `1`

#### Monitoring Configuration

- **`--monitoring`**
  - Enable monitoring for the cluster
  - Flag parameter (no value required)
  - Default: disabled
  - When enabled, requires `--mon-ingestion-endpoint` and `--mon-dcr-id`

- **`--mon-ingestion-endpoint <endpoint>`**
  - Monitoring ingestion endpoint URL
  - Required when `--monitoring` is enabled
  - Example: `https://your-monitor-xxxxx.region-1.metrics.ingest.monitor.azure.com/dataCollectionRules/dcr-xxxxx/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24`

- **`--mon-dcr-id <dcr-id>`**
  - Data Collection Rule resource ID
  - Required when `--monitoring` is enabled
  - Format: `/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Insights/dataCollectionRules/<dcr-name>`

#### Microsoft Entra ID Configuration

- **`--entra-id`**
  - Enable Microsoft Entra ID authentication
  - Flag parameter (no value required)
  - Default: disabled
  - When enabled, requires `--entra-app-umi` and `--entra-app-id`

- **`--entra-app-umi <umi-id>`**
  - User Managed Identity resource ID used in federated credentials of the registered Entra ID application for user authentication
  - Required when `--entra-id` is enabled
  - Format: `/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.ManagedIdentity/userAssignedIdentities/<identity-name>`
  - Example: `/subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/myResourceGroup/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity`

- **`--entra-app-id <app-id>`**
  - Application (client) ID of the registered Entra ID application used to authenticate users
  - Required when `--entra-id` is enabled
  - Format: GUID
  - Example: `12345678-1234-1234-1234-123456789abc`

#### Database Configuration (Slurm Accounting)

The script supports two modes for database configuration:

**Mode 1: Auto-create MySQL Flexible Server** (use `--create-accounting-mysql`)

- **`--create-accounting-mysql`**

  - Flag to automatically create a minimal MySQL Flexible Server
  - Requires `--db-name`, `--db-user`, `--db-password` (but NOT `--db-id`)
  - Server is created in the specified resource group and location

- **`--db-generate-name`**

  - Automatically generate a random database name
  - Only valid with `--create-accounting-mysql`
  - Format: `ccdb-<random-hex>`
  - Ignored if `--db-name` is already provided

- **`--db-name <name>`**

  - MySQL Flexible Server instance name (for auto-creation or existing server)
  - Example: `myccdb`

- **`--db-user <username>`**

  - Database administrator username for Slurm accounting
  - Example: `dbadmin`

- **`--db-password <password>`**
  - Password for the database user
  - **Security Note**: Prefer using environment variables for sensitive values
  - Example: `'DbP@ssw0rd!'`

**Mode 2: Use Existing MySQL Flexible Server**

To use an existing server, provide **all four** of these parameters (validated
as all-or-nothing):

- **`--db-name <name>`** - MySQL Flexible Server instance name
- **`--db-user <username>`** - Database administrator username
- **`--db-password <password>`** - Password for the database user
- **`--db-id <resource_id>`** - Full Azure resource ID of the MySQL Flexible
  Server
  - Format:
    `/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.DBforMySQL/flexibleServers/<server-name>`
  - Example:
    `/subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/myResourceGroup/providers/Microsoft.DBforMySQL/flexibleServers/myccdb`

If none of the database flags are provided, `databaseConfig` defaults to:

```json
"databaseConfig": { "value": { "type": "disabled" } }
```

#### Open OnDemand Portal Configuration

- **`--open-ondemand`**

  - Enable Open OnDemand web portal deployment
  - Flag parameter (no value required)
  - Default: disabled
  - **Requires `--entra-id` to be enabled**
  - Requires `--ood-user-domain` when enabled

- **`--ood-sku <sku>`** (default: `Standard_D4as_v5`)

  - VM SKU for the Open OnDemand portal server
  - Example: `Standard_D8as_v5`

- **`--ood-user-domain <domain>`**

  - User domain for Open OnDemand authentication
  - Required when `--open-ondemand` is enabled
  - Example: `contoso.com`

- **`--ood-fqdn <fqdn>`**

  - Fully Qualified Domain Name for Open OnDemand portal
  - Optional; defaults to empty string
  - Only included in parameters when `--open-ondemand` is enabled
  - Must contain at least one dot and no spaces if provided
  - Example: `ood.contoso.com`

- **`--ood-no-start`**

  - Do not start the Open OnDemand cluster automatically
  - Flag parameter (no value required)
  - Default: cluster starts automatically
  - Useful when you want to configure the cluster before starting it

**Note:** The following values are automatically taken from Entra ID configuration:
- Application (client) ID from `--entra-app-id`
- User Managed Identity from `--entra-app-umi`
- Tenant ID is automatically retrieved from the active Azure subscription

#### Deployment Control

- **`--accept-marketplace`**

  - Automatically accept Azure Marketplace terms
  - Sets `acceptMarketplaceTerms=true` in parameters
  - Required for first-time deployment of certain OS SKUs
  - Avoids manual marketplace agreement step

- **`--deploy`**

  - Perform deployment immediately after generating `output.json`
  - Skips interactive confirmation prompt
  - Useful for automated/scripted deployments

- **`--output-file <path>`**
  - Custom path for the generated parameters file
  - Default: `output.json` in script directory
  - Useful for managing multiple deployment configurations

#### Example: Full Configuration with All Optional Parameters

```bash
./scripts/deploy-ccws.sh \
  --subscription-id <sub-id> \
  --resource-group <rg-name> \
  --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub \
  --admin-password 'YourP@ssw0rd!' \
  --admin-username myadmin \
  --htc-sku Standard_F2s_v2 \
  --hpc-sku Standard_HB176rs_v4 \
  --gpu-sku Standard_ND96amsr_A100_v4 \
  --scheduler-sku Standard_D8as_v5 \
  --login-sku Standard_D4as_v5 \
  --htc-az 1 \
  --hpc-az 1 \
  --gpu-az 1 \
  --htc-max-nodes 10 \
  --hpc-max-nodes 5 \
  --gpu-max-nodes 2 \
  --htc-use-spot \
  --network-address-space 10.1.0.0/16 \
  --bastion \
  --anf-sku Premium \
  --anf-size 4 \
  --anf-az 1 \
  --amlfs-sku AMLFS-Durable-Premium-500 \
  --amlfs-size 8 \
  --amlfs-az 1 \
  --monitoring \
  --mon-ingestion-endpoint https://ccw-mon-xxxxx.swedencentral-1.metrics.ingest.monitor.azure.com/dataCollectionRules/dcr-xxxxx/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24 \
  --mon-dcr-id /subscriptions/12345678/resourceGroups/myRG/providers/Microsoft.Insights/dataCollectionRules/myDCR \
  --entra-id \
  --entra-app-umi /subscriptions/12345678/resourceGroups/myRG/providers/Microsoft.ManagedIdentity/userAssignedIdentities/myIdentity \
  --entra-app-id 12345678-1234-1234-1234-123456789abc \
  --create-accounting-mysql \
  --db-name myccdb \
  --db-user dbadmin \
  --db-password 'DbP@ssw0rd!' \
  --open-ondemand \
  --ood-sku Standard_D8as_v5 \
  --ood-user-domain contoso.com \
  --ood-fqdn ood.contoso.com \

  --workspace-ref main \
  --workspace-commit a1b2c3d4 \
  --output-file my-deployment-params.json \
  --accept-marketplace \
  --specify-az \
  --deploy
```

> [!WARNING]  
> Check all parameters carefully before proceeding with deployment, especially
> storage sizes and SKUs, as they impact performance and cost.

> [!TIP] For production deployments:
>
> - Store sensitive values (passwords, keys) in environment variables
> - Use `--workspace-commit` to pin to a tested commit SHA
> - Co-locate compute and storage in the same availability zone
> - Test with `--deploy` omitted first to review generated `output.json`
> - Consider using `--htc-use-spot` for cost-effective HTC workloads that
>   tolerate interruptions
> - Enable `--bastion` for secure access without public IPs on VMs

### 3.6. Script Reference (Docstring Style)

Below is a docstring-style summary of `deploy-ccws.sh` for quick reference:

```
deploy-ccws.sh - Generate and optionally deploy an Azure CycleCloud Workspace for Slurm environment.

USAGE:
  deploy-ccws.sh \
    --subscription-id <subId> --resource-group <rg> --location <region> \
    --ssh-public-key-file <path> --admin-password <password> \
    --htc-sku <sku> --hpc-sku <sku> --gpu-sku <sku> [options]

REQUIRED PARAMETERS:
  --subscription-id        Azure subscription ID
  --resource-group         Target resource group name
  --location               Azure region (used for all resources)
  --ssh-public-key-file    Path to OpenSSH public key file
  --admin-password         Admin password for CycleCloud UI / cluster DB
  --htc-sku                HTC partition VM SKU (or interactive prompt)
  --hpc-sku                HPC partition VM SKU (or interactive prompt)
  --gpu-sku                GPU partition VM SKU (or interactive prompt)

OPTIONAL PARAMETERS:
  # General Configuration
  --admin-username         Admin username (default: hpcadmin)
  --scheduler-sku          Scheduler node VM SKU (default: Standard_D4as_v5)
  --login-sku              Login node VM SKU (default: Standard_D2as_v5)

  # Workspace Repository
  --workspace-ref <ref>    Git ref (branch/tag) to checkout (default: main)
  --workspace-commit <sha> Explicit commit (detached HEAD override)
  --workspace-dir <path>   Clone destination (default: ./cyclecloud-slurm-workspace under script dir)
  --output-file <path>     Output parameters file path (default: output.json in script dir)

  # Availability Zones
  --specify-az             Enable interactive AZ prompting (only if region has zonal SKUs)
  --htc-az / --hpc-az / --gpu-az  Explicit AZ override; suppresses interactive prompt

  # Compute Partitions
  --htc-max-nodes <count>  Maximum nodes for HTC partition (interactive if omitted)
  --hpc-max-nodes <count>  Maximum nodes for HPC partition (interactive if omitted)
  --gpu-max-nodes <count>  Maximum nodes for GPU partition (interactive if omitted)
  --htc-use-spot           Use Spot (preemptible) VMs for HTC partition (flag)

  # Network Configuration
  --network-address-space <cidr>  Virtual network CIDR (default: 10.0.0.0/24)
  --bastion                Enable Azure Bastion deployment (flag)

  # Storage - Azure NetApp Files
  --anf-sku <tier>         NetApp Files service level: Standard|Premium|Ultra (default: Premium)
  --anf-size <TiB>         NetApp Files capacity in TiB (default: 2)
  --anf-az <zone>          Availability zone for ANF (optional; interactive if omitted)

  # Storage - Azure Managed Lustre
  --amlfs-sku <tier>       Lustre tier: AMLFS-Durable-Premium-{40|125|250|500} (default: 500)
  --amlfs-size <TiB>       Lustre capacity in TiB (default: 4)
  --amlfs-az <zone>        Availability zone for AMLFS (optional; defaults to 1 if region supports zones)

  # Database Configuration (Slurm Accounting)
  --create-accounting-mysql    Auto-create MySQL Flexible Server (requires --db-name, --db-user, --db-password)
  --db-generate-name           Generate random database name (with --create-accounting-mysql)
  --db-name <name>             MySQL server name
  --db-user <username>         Database admin username
  --db-password <password>     Database admin password
  --db-id <resourceId>         Existing MySQL server resource ID (for existing server mode)

  # Open OnDemand Portal
  --open-ondemand              Enable Open OnDemand web portal (flag)
  --ood-sku <sku>              Open OnDemand VM SKU (default: Standard_D4as_v5)
  --ood-user-domain <domain>   User domain for OOD authentication (required with --open-ondemand)
  --ood-fqdn <fqdn>            Fully Qualified Domain Name for OOD (optional)
  --ood-auto-register          Auto-register new Entra ID application (flag)
  --ood-app-id <appId>         Existing Entra ID app ID (when not auto-registering)
  --ood-managed-identity-id <id>  Existing managed identity resource ID (when not auto-registering)

  # Deployment Control
  --accept-marketplace     Accept marketplace terms automatically
  --deploy                 Perform deployment after generating output.json
  --help                   Show usage information

INTERACTIVE PROMPTS:
  If HTC/HPC/GPU SKUs or max nodes are not provided via CLI, the script will prompt interactively.
  Availability zone prompts occur only when --specify-az is set and region supports zones.

BEHAVIOR:
  * Auto-discovers zonal availability using `az vm list-skus` + `jq`.
  * Skips AZ prompts if region lacks zonal SKUs or tools are missing.
  * Generates parameter file with conditional database and storage sections.
  * Interactive confirmation unless --deploy provided.
  * Passwords (admin and database) are NOT persisted in output.json for security.

DATABASE MODES:
  1. Auto-create: Use --create-accounting-mysql with --db-name, --db-user, --db-password
  2. Existing server: Provide all four: --db-name, --db-user, --db-password, --db-id
  3. Disabled: Omit all database parameters

OUTPUT ARTIFACT:
  output.json containing all deployment parameters for the Bicep template.

EXIT CODES:
  0 Success
  1 Missing required arguments or validation failure

SECURITY NOTES:
  * Avoid committing generated output.json containing passwords.
  * Prefer environment variables for sensitive values.
  * Admin and database passwords must be passed via CLI during deployment.
```

### 3.7. Non-Interactive Deployment

To avoid interactive zone prompts and deploy without availability zones (default behavior):

```bash
./scripts/deploy-ccws.sh --subscription-id <sub-id> --resource-group <rg> --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 --gpu-sku Standard_ND96amsr_A100_v4 \
  --deploy
```

To explicitly disable availability zones:

```bash
./scripts/deploy-ccws.sh --subscription-id <sub-id> --resource-group <rg> --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 --gpu-sku Standard_ND96amsr_A100_v4 \
  --no-az \
  --deploy
```

To specify zones via command line without prompts:

```bash
./scripts/deploy-ccws.sh --subscription-id <sub-id> --resource-group <rg> --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 --htc-az 1 --hpc-sku Standard_HB176rs_v4 --hpc-az 1 \
  --gpu-sku Standard_ND96amsr_A100_v4 --gpu-az 1 \
  --specify-az \
  --deploy
```

### 3.8. Re-Running / Modifying

User can re-run the script with different SKUs or zone selections; it will
regenerate `output.json`. Delete or move the file if user wants to keep multiple
versions.

### 3.9. Troubleshooting

- Missing zones: Ensure `jq` is installed and that your Azure CLI is up to date.
- Permission errors: Verify subscription context (`az account show`) and role
  assignments.
- Marketplace errors: Include `--accept-marketplace` if required for first-time
  OS SKU usage.

### 3.10. Manual Deployment (Optional)

If the user only wants the parameters file and prefer manual deployment:

```bash
az deployment sub create --name <name> --location <region> \
  --template-file cyclecloud-slurm-workspace/bicep/mainTemplate.bicep \
  --parameters @output.json
```
