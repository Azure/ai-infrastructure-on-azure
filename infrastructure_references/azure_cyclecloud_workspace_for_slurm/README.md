# Deploying Azure CycleCloud Workspace for Slurm

This section of the repository contains the guidance to deploy Azure CycleCloud Workspace for Slurm environments.

The templates contained in this folder have some deployment examples with different features and storage types.

The deployment guide follows what described in the [official Azure CycleCloud Workspace for Slurm documentation pages](https://learn.microsoft.com/en-us/azure/cyclecloud/how-to/ccws/deploy-with-cli?view=cyclecloud-8).

## Prequisites

In order to deploy the infrastructure described in this section of the guide in an existing Azure Subscription, be sure to have:

- A working installation of [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt)
- Contributor on the Subscription
- User Access Administrator on the Subscription
- Be sure that `az account show` is displaying the right subscription. In case, fix the subscription with `az account set --subscription "your-subscription-name"`

## Create a MySQL Flexible server (optional)

Optionally, user can decide to deploy a MySQL Flexible server for Slurm job accounting. This should exist before the deployment.

In order to deploy the smallest MySQL Flexible server, with the lowest tier:

```bash
az mysql flexible-server create \
  --name $DB_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --location $LOCATION \
  --admin-user $DB_USERNAME \
  --admin-password $DB_PASSWORD \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 20 \
  --high-availability Disabled \
   --public-access 'None'
```

Let's then export the ID in a variable for the subsequent steps:

```bash
export MYSQL_ID=$( az mysql flexible-server show -n $DB_NAME -g $RESOURCE_GROUP_NAME --query "id" --output tsv)
```

## Deployment with `deploy-ccws.sh`

Instead of manually editing and generating a parameters JSON file, this repository provides an automation helper script: `scripts/deploy-ccws.sh`. The script:

* Clones the official CycleCloud Slurm Workspace repository at a chosen ref/commit.
  
> [!WARNING]
> This guide intentionally uses a **specific commit SHA** of the Azure CycleCloud Slurm Workspace repository to pull in hotfixes that may not yet be part of the latest tagged release. Pinning the commit ensures reproducible deployments and avoids regressions from upstream changes. If user switches to `--workspace-ref main` without a `--workspace-commit` override user may pick up newer code paths that have not been validated in this environment. Always re-run validation (storage mounts, Slurm job submission, NCCL tests) after changing the commit. Default **commit SHA** in the current repository includes some fix on top of `2025.09.15` for AMLFS networking and availbility zone enforcement. 

* User can specify a specific `commit-id` or `branch` for checkout. 
* Builds an `output.json` parameters file for the Bicep template.
* Optionally prompts for availability zones only if the region supports zonal SKUs.
* Can immediately deploy the environment (or let user review first).

### Prerequisites

* Azure CLI installed and logged in (`az login`).
* Proper role assignments on the subscription: Contributor + User Access Administrator.
* SSH public key file (OpenSSH format) available locally.
* (Optional) MySQL Flexible Server already provisioned if user plans to enable accounting in templates requiring it.

### Basic Usage

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
2. The region contains at least one zonal-capable VM SKU (auto-detected via `az vm list-skus`).
3. If availability zones are specified using the CLI commands for each partition and for storage, it will not prompt for them.

If the region does not support zones (or `az`/`jq` are missing), the script will fall back silently to non-zonal deployment and produce empty `availabilityZone` arrays.

### Selecting Availability Zones

Choosing an Availability Zone impacts both **storage latency** and **overall workload performance**:

* Co-locate compute partitions (HTC/HPC/GPU) with shared storage (ANF / AMLFS) in the **same zone** whenever possible to minimize cross-zone latency.
* Cross-zone access can introduce higher I/O latency for metadata-heavy or small-block operations.

When prompted, press Enter to skip (no zone) or provide a number like `1`. For ANF and AMLFS, the script uses manual prompts because their zone capabilities are not derived from the VM SKU query. If user skips, the deployment uses region-level (non-zonal) placement. AMLFS will default to zone `1`.

### Example With Marketplace Acceptance and Automatic Deployment

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
  --amlfs-sku AMLFS-Durable-Premium-500 --amlfs-size 4 \
  --accept-marketplace \
  --specify-az \
  --deploy
```

### Generated Artifacts

* `output.json` – parameter file used for the Bicep deployment.
* Random deployment name previewed in the summary section.
* Summary of chosen SKUs and zones printed for validation.

### Optional Flags

* `--workspace-ref <branch|tag>`: Choose a git ref (default: `main`).
* `--workspace-commit <sha>`: Pin to a specific commit (detached HEAD).
* `--scheduler-sku`, `--login-sku`: Override default CycleCloud scheduler/login node sizes.
* `--accept-marketplace`: Sets `acceptMarketplaceTerms=true` in parameters.
* `--deploy`: Perform deployment immediately without interactive confirmation.

### Optional Database Configuration

If users want to enable Slurm accounting with an existing MySQL Flexible Server, supply all of the following flags. They are validated as an all-or-nothing set; if any is missing the script exits with an error.

Required together:

* `--db-name` – The MySQL Flexible Server name
* `--db-user` – The database administrator/user for accounting
* `--db-password` – The password for the database user
* `--db-id` – The full Azure resource ID of the MySQL Flexible Server (e.g. `/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DBforMySQL/flexibleServers/<name>`)

If none of the flags are provided, `databaseConfig` defaults to:

```json
"databaseConfig": { "value": { "type": "disabled" } }
```

Example with database enabled:

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
  --db-name myccdb \
  --db-user dbadmin \
  --db-password 'DbP@ssw0rd!' \
  --db-id /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.DBforMySQL/flexibleServers/myccdb \
  --deploy
```

> [!TIP]
> For security, prefer storing the database password in an environment variable and referencing it.

### Script Reference (Docstring Style)

Below is a docstring-style summary of `deploy-ccws.sh` for quick reference:

```
deploy-ccws.sh - Generate and optionally deploy an Azure CycleCloud Slurm Workspace environment.

USAGE:
  deploy-ccws.sh \
    --subscription-id <subId> --resource-group <rg> --location <region> \
    --ssh-public-key-file <path> --admin-password <password> \
    --htc-sku <sku> --hpc-sku <sku> --gpu-sku <sku> [options]

REQUIRED PARAMETERS:
  --subscription-id        Azure subscription ID
  --resource-group         Target resource group name
  --location               Azure region
  --ssh-public-key-file    Path to OpenSSH public key file
  --admin-password         Admin password for CycleCloud UI / cluster DB
  --htc-sku                HTC partition VM SKU
  --hpc-sku                HPC partition VM SKU
  --gpu-sku                GPU partition VM SKU

OPTIONAL PARAMETERS:
  --admin-username         (default: hpcadmin)
  --scheduler-sku          (default: Standard_D4as_v5)
  --login-sku              (default: Standard_D2as_v5)
  --htc-az / --hpc-az / --gpu-az  Explicit AZ override; suppresses interactive prompt
  --anf-sku / --anf-size / --anf-az        NetApp Files config
  --amlfs-sku / --amlfs-size / --amlfs-az  Azure Managed Lustre config
  --specify-az             Enable interactive AZ prompting (only if region has zonal SKUs)
  --accept-marketplace     Accept marketplace terms automatically
  --workspace-ref <ref>    Git ref (branch/tag) to checkout (default: main)
  --workspace-commit <sha> Explicit commit (detached HEAD override)
  --workspace-dir <path>   Clone destination (default: script dir)
  --output-file <path>     Output parameters file path (default: output.json in script dir)
  --db-name / --db-user / --db-password / --db-id  Enable privateEndpoint DB config (all required)
  --deploy                 Perform deployment after generating output.json

BEHAVIOR:
  * Auto-discovers zonal availability using `az vm list-skus` + `jq`.
  * Skips AZ prompts if region lacks zonal SKUs or tools are missing.
  * Generates parameter file with conditional database and storage sections.
  * Interactive confirmation unless --deploy provided.

OUTPUT ARTIFACT:
  output.json containing all deployment parameters for the Bicep template.

EXIT CODES:
  0 Success
  1 Missing required arguments or validation failure

SECURITY NOTES:
  * Avoid committing generated output.json containing passwords.
  * Prefer environment variables for sensitive values.
```

### Non-Interactive Deployment

To avoid interactive zone prompts entirely, omit `--specify-az` or specify them with the corresponding command line options:

```bash
./scripts/deploy-ccws.sh --subscription-id <sub-id> --resource-group <rg> --location eastus \
  --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \
  --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 --gpu-sku Standard_ND96amsr_A100_v4 --deploy
```

### Re-Running / Modifying

User can re-run the script with different SKUs or zone selections; it will regenerate `output.json`. Delete or move the file if user wants to keep multiple versions.

### Troubleshooting

* Missing zones: Ensure `jq` is installed and that your Azure CLI is up to date.
* Permission errors: Verify subscription context (`az account show`) and role assignments.
* Marketplace errors: Include `--accept-marketplace` if required for first-time SKU usage.

### Manual Deployment (Optional)

If the user only wants the parameters file and prefer manual deployment:

```bash
az deployment sub create --name <name> --location <region> \
  --template-file cyclecloud-slurm-workspace/bicep/mainTemplate.bicep \
  --parameters @output.json
```