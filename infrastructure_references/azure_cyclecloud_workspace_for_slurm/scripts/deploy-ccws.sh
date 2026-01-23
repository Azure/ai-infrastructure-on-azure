#!/usr/bin/env bash
set -euo pipefail
###############################################
# Azure CycleCloud Workspace for Slurm Deployment Helper
# Generates an output.json parameters file for Bicep deployment
# Clones azure/cyclecloud-slurm-workspace at a ref
# Applies availability zone substitutions
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_FILE="${SCRIPT_DIR}/output.json"
WORKSPACE_REPO_URL="https://github.com/azure/cyclecloud-slurm-workspace.git"

usage() {
	cat <<EOF
================================================================================
Azure CycleCloud Workspace for Slurm Deployment Helper
Generate and optionally deploy an Azure CycleCloud Workspace for Slurm
================================================================================

USAGE:
  $0 \\
    --subscription-id <subId> --resource-group <rg> --location <region> \\
    --ssh-public-key-file <path> --admin-password <password> \\
    --htc-sku <sku> --hpc-sku <sku> --gpu-sku <sku> [options]

REQUIRED PARAMETERS:
  --subscription-id              Azure subscription ID
  --resource-group               Target resource group name
  --location                     Azure region (used for all resources)
  --ssh-public-key-file          Path to SSH public key file (OpenSSH format)
  --admin-password               Admin password (for CycleCloud workspace UI / cluster DB)
  --htc-sku                      HTC partition VM SKU (or interactive prompt)
  --hpc-sku                      HPC partition VM SKU (or interactive prompt)
  --gpu-sku                      GPU partition VM SKU (or interactive prompt)

OPTIONAL PARAMETERS:

  General Configuration:
    --admin-username <name>      Admin username (default: hpcadmin)
    --cluster-name <name>        Slurm cluster name (default: ccw)

  CycleCloud Infrastructure SKUs:
    --scheduler-sku <sku>        Scheduler node VM SKU (default: Standard_D4as_v5)
    --login-sku <sku>            Login node VM SKU (default: Standard_D2as_v5)

  OS Image Configuration:
    --scheduler-image <image>    Scheduler node OS image (default: cycle.image.ubuntu24)
    --login-image <image>        Login node OS image (default: cycle.image.ubuntu24)
    --ood-image <image>          Open OnDemand node OS image (default: cycle.image.ubuntu24)
    --htc-image <image>          HTC partition OS image (default: cycle.image.ubuntu24)
    --hpc-image <image>          HPC partition OS image (default: cycle.image.ubuntu24)
    --gpu-image <image>          GPU partition OS image (default: cycle.image.ubuntu24)

  Workspace Repository:
    --workspace-ref <ref>        Git ref (branch/tag) to checkout (default to latest release)
    --workspace-commit <sha>     Explicit commit (detached HEAD override)
    --workspace-dir <path>       Clone destination (default: ./cyclecloud-slurm-workspace)
    --output-file <path>         Output parameters file path (default: ${DEFAULT_OUTPUT_FILE})

  Availability Zones:
    --no-az                      Disable availability zones entirely (default behavior)
    --specify-az                 Enable interactive AZ prompting (allows manual zone entry even if auto-discovery fails)
    --htc-az <zone>              Explicit AZ for HTC partition (suppresses interactive prompt)
    --hpc-az <zone>              Explicit AZ for HPC partition (suppresses interactive prompt)
    --gpu-az <zone>              Explicit AZ for GPU partition (suppresses interactive prompt)

  Compute Partition Configuration:
    --htc-max-nodes <count>      Maximum nodes for HTC partition (interactive if omitted)
    --hpc-max-nodes <count>      Maximum nodes for HPC partition (interactive if omitted)
    --gpu-max-nodes <count>      Maximum nodes for GPU partition (interactive if omitted)
    --htc-use-spot               Use Spot (preemptible) VMs for HTC partition (flag)
    --slurm-no-start             Do not start Slurm cluster automatically (default: start cluster)

  Network Configuration:
    --network-address-space <cidr>  Virtual network CIDR (default: 10.0.0.0/24)
    --bastion                    Enable Azure Bastion deployment (flag)

  Storage - Azure NetApp Files:
    --anf-sku <tier>             ANF service level: Standard|Premium|Ultra (default: Premium)
    --anf-size <TiB>             ANF capacity in TiB (integer, default: 2, minimum: 1)
    --anf-az <zone>              Availability zone for ANF (optional; interactive if omitted)

  Storage - Azure Managed Lustre:
    --data-filesystem            Enable Azure Managed Lustre data filesystem (disabled by default)
    --amlfs-sku <tier>           AMLFS tier: AMLFS-Durable-Premium-{40|125|250|500} (default: 500)
    --amlfs-size <TiB>           AMLFS capacity in TiB (integer, default: 4, minimum: 4)
    --amlfs-az <zone>            Availability zone for AMLFS (defaults to 1)

  Monitoring:
    --monitoring                 Enable monitoring (disabled by default)
    --mon-ingestion-endpoint <endpoint>  Monitoring ingestion endpoint (required with --monitoring)
    --mon-dcr-id <dcr-id>        Data Collection Rule ID (required with --monitoring)

  Microsoft Entra ID:
    --entra-id                   Enable Microsoft Entra ID (disabled by default)
    --entra-app-umi <umi-id>     User Managed Identity resource ID used in federated credentials 
                                 of the registered Entra ID application for user authentication 
                                 (required with --entra-id)
    --entra-app-id <app-id>      Application (client) ID of the registered Entra ID application 
                                 used to authenticate users (required with --entra-id)

  Database Configuration (Slurm Accounting):
    Mode 1 - Auto-create MySQL Flexible Server:
      --create-accounting-mysql  Auto-create MySQL server (requires --db-name, --db-user, --db-password)
      --db-generate-name         Generate random database name (with --create-accounting-mysql)
      --db-name <name>           MySQL server name
      --db-user <username>       Database admin username
      --db-password <password>   Database admin password

    Mode 2 - Use Existing MySQL Flexible Server:
      --db-name <name>           MySQL server name
      --db-user <username>       Database admin username
      --db-password <password>   Database admin password
      --db-id <resourceId>       Full Azure resource ID of existing MySQL server
                                 (all four parameters required together)

  Open OnDemand Portal:
    --open-ondemand              Enable Open OnDemand web portal (flag)
                                 Requires --entra-id to be enabled
    --ood-sku <sku>              OOD VM SKU (default: Standard_D4as_v5)
    --ood-user-domain <domain>   User domain for OOD authentication (required with --open-ondemand)
    --ood-fqdn <fqdn>            Fully Qualified Domain Name for OOD (optional)
    --ood-no-start               Do not start OOD cluster automatically (default: start cluster)

  Deployment Control:
    --accept-marketplace         Accept marketplace terms automatically
    --deploy                     Perform deployment after generating output.json
    --silent                     Skip interactive confirmation prompts (default: interactive when --deploy not set)
		--debug                      Enable verbose debug logging
    --help                       Show this usage information

INTERACTIVE PROMPTS:
  If HTC/HPC/GPU SKUs or max nodes are not provided via CLI, the script will
  prompt interactively. Availability zone prompts occur only when --specify-az
  is set and the region supports zonal SKUs.

BEHAVIOR:
  * Auto-discovers zonal availability using 'az vm list-skus' + 'jq'
  * Skips AZ prompts if region lacks zonal SKUs or tools are missing
  * Generates parameter file with conditional database and storage sections
  * Interactive confirmation unless --deploy or --silent provided
  * Passwords (admin and database) are NOT persisted in output.json for security

DATABASE MODES:
  1. Auto-create: Use --create-accounting-mysql with --db-name, --db-user, --db-password
  2. Existing server: Provide all four: --db-name, --db-user, --db-password, --db-id
  3. Disabled: Omit all database parameters

OUTPUT ARTIFACT:
  output.json containing all deployment parameters for the Bicep template

EXIT CODES:
  0  Success
  1  Missing required arguments or validation failure

SECURITY NOTES:
  * Avoid committing generated output.json containing passwords
  * Prefer environment variables for sensitive values
  * Admin and database passwords must be passed via CLI during deployment

EXAMPLES:

  Basic deployment with interactive zone prompts:
    $0 --subscription-id SUB --resource-group rg-ccw --location eastus \\
       --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \\
       --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 \\
       --gpu-sku Standard_ND96amsr_A100_v4 --specify-az

  Deployment with custom OS images:
    $0 --subscription-id SUB --resource-group rg-ccw --location eastus \\
       --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \\
       --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 \\
       --gpu-sku Standard_ND96amsr_A100_v4 \\
       --scheduler-image cycle.image.ubuntu22 \\
       --login-image cycle.image.ubuntu22 \\
       --htc-image cycle.image.ubuntu22 \\
       --hpc-image cycle.image.ubuntu22 \\
       --gpu-image cycle.image.ubuntu22 \\
       --ood-image cycle.image.ubuntu22 --deploy

  Full deployment with all features:
    $0 --subscription-id SUB --resource-group rg-ccw --location eastus \\
       --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \\
       --htc-sku Standard_F2s_v2 --htc-az 1 --htc-max-nodes 100 --htc-use-spot \\
       --hpc-sku Standard_HB176rs_v4 --hpc-az 1 --hpc-max-nodes 50 \\
       --gpu-sku Standard_ND96amsr_A100_v4 --gpu-az 1 --gpu-max-nodes 20 \\
       --network-address-space 10.1.0.0/16 --bastion \\
       --anf-sku Premium --anf-size 4 --anf-az 1 \\
       --data-filesystem --amlfs-sku AMLFS-Durable-Premium-500 --amlfs-size 8 --amlfs-az 1 \\
       --create-accounting-mysql --db-name myccdb --db-user dbadmin --db-password 'DbP@ss!' \\
       --entra-id --entra-app-umi YOUR_UMI_RESOURCE_ID --entra-app-id YOUR_ENTRA_APP_ID \\
       --open-ondemand --ood-user-domain contoso.com --ood-fqdn ood.contoso.com \\
       --entra-id --entra-app-umi YOUR_UMI_RESOURCE_ID --entra-app-id YOUR_ENTRA_APP_ID \\
       --accept-marketplace --specify-az --deploy

  With existing database and custom workspace commit:
    $0 --subscription-id SUB --resource-group rg-ccw --location eastus \\
       --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \\
       --htc-sku Standard_F2s_v2 --hpc-sku Standard_HB176rs_v4 \\
       --gpu-sku Standard_ND96amsr_A100_v4 \\
       --db-name myccdb --db-user dbadmin --db-password 'DbP@ss!' \\
       --db-id /subscriptions/SUB/resourceGroups/RG/providers/Microsoft.DBforMySQL/flexibleServers/myccdb \\
       --workspace-commit a1b2c3d4e5f6 --deploy

================================================================================
EOF
}

# Default values
ADMIN_USERNAME="hpcadmin"
CLUSTER_NAME="ccw"
SCHEDULER_SKU="Standard_D4as_v5"
LOGIN_SKU="Standard_D2as_v5"
HTC_SKU=""
HPC_SKU=""
GPU_SKU=""
SCHEDULER_IMAGE="cycle.image.ubuntu24"
LOGIN_IMAGE="cycle.image.ubuntu24"
OOD_IMAGE="cycle.image.ubuntu24"
HTC_IMAGE="cycle.image.ubuntu24"
HPC_IMAGE="cycle.image.ubuntu24"
GPU_IMAGE="cycle.image.ubuntu24"
# Retrieve latest releas tag, default to main
LATEST_RELEASE_TAG="$(curl -s https://api.github.com/repos/azure/cyclecloud-slurm-workspace/releases/latest | jq -r .tag_name 2>/dev/null || echo "main")"
WORKSPACE_REF="${WORKSPACE_REF:-$LATEST_RELEASE_TAG}" # allow pre-set env var to override default
WORKSPACE_COMMIT=""
OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"
WORKSPACE_DIR="${SCRIPT_DIR}/cyclecloud-slurm-workspace"
ACCEPT_MARKETPLACE="false"
DO_DEPLOY="false"
ANF_SKU="Premium"
ANF_SIZE="2"
ANF_AZ=""
AMLFS_SKU="AMLFS-Durable-Premium-500"
AMLFS_SIZE="4"
AMLFS_AZ=""
DATA_FILESYSTEM_ENABLED="false"
MONITORING_ENABLED="false"
MON_INGESTION_ENDPOINT=""
MON_DCR_ID=""
ENTRA_ID_ENABLED="false"
ENTRA_APP_UMI=""
ENTRA_APP_ID=""
NO_AZ="true"
SPECIFY_AZ="false"
COMPUTE_SKUS_CACHE=""
DB_NAME=""
DB_USERNAME=""
DB_PASSWORD=""
DB_ID=""
DB_ENABLED="false"
NETWORK_ADDRESS_SPACE="10.0.0.0/24"
NETWORK_BASTION="false"
HTC_MAX_NODES=""
HPC_MAX_NODES=""
GPU_MAX_NODES=""
HTC_USE_SPOT="false"
SLURM_START_CLUSTER="true"
OOD_ENABLED="false"
OOD_SKU="Standard_D4as_v5"
OOD_USER_DOMAIN=""
OOD_FQDN=""
OOD_START_CLUSTER="true"
CREATE_ACCOUNTING_MYSQL="false"
DB_GENERATE_NAME="false"
SILENT="false"
DEBUG_ENABLED="false"

# Debug logging helper (only emits when --debug is specified)
debug_log() {
	if [[ "$DEBUG_ENABLED" == "true" ]]; then
		echo "[DEBUG] $*" >&2
	fi
}

# Parse args
while [[ $# -gt 0 ]]; do
	case "$1" in
	--subscription-id)
		SUBSCRIPTION_ID="$2"
		shift 2
		;;
	--resource-group)
		RESOURCE_GROUP="$2"
		shift 2
		;;
	--location)
		LOCATION="$2"
		shift 2
		;;
	--ssh-public-key-file)
		SSH_KEY_FILE="$2"
		shift 2
		;;
	--admin-password)
		ADMIN_PASSWORD="$2"
		shift 2
		;;
	--admin-username)
		ADMIN_USERNAME="$2"
		shift 2
		;;
	--cluster-name)
		CLUSTER_NAME="$2"
		shift 2
		;;
	--htc-sku)
		HTC_SKU="$2"
		shift 2
		;;
	--htc-az)
		HTC_AZ="$2"
		shift 2
		;;
	--hpc-sku)
		HPC_SKU="$2"
		shift 2
		;;
	--hpc-az)
		HPC_AZ="$2"
		shift 2
		;;
	--gpu-sku)
		GPU_SKU="$2"
		shift 2
		;;
	--gpu-az)
		GPU_AZ="$2"
		shift 2
		;;
	--htc-image)
		HTC_IMAGE="$2"
		shift 2
		;;
	--hpc-image)
		HPC_IMAGE="$2"
		shift 2
		;;
	--gpu-image)
		GPU_IMAGE="$2"
		shift 2
		;;
	--scheduler-sku)
		SCHEDULER_SKU="$2"
		shift 2
		;;
	--login-sku)
		LOGIN_SKU="$2"
		shift 2
		;;
	--scheduler-image)
		SCHEDULER_IMAGE="$2"
		shift 2
		;;
	--login-image)
		LOGIN_IMAGE="$2"
		shift 2
		;;
	--workspace-ref)
		WORKSPACE_REF="$2"
		shift 2
		;;
	--workspace-commit)
		WORKSPACE_COMMIT="$2"
		shift 2
		;;
	--workspace-dir)
		WORKSPACE_DIR="$2"
		shift 2
		;;
	--output-file)
		OUTPUT_FILE="$2"
		shift 2
		;;
	--anf-sku)
		ANF_SKU="$2"
		shift 2
		;;
	--anf-size)
		ANF_SIZE="$2"
		shift 2
		;;
	--anf-az)
		ANF_AZ="$2"
		shift 2
		;;
	--amlfs-sku)
		AMLFS_SKU="$2"
		shift 2
		;;
	--amlfs-size)
		AMLFS_SIZE="$2"
		shift 2
		;;
	--amlfs-az)
		AMLFS_AZ="$2"
		shift 2
		;;
	--network-address-space)
		NETWORK_ADDRESS_SPACE="$2"
		shift 2
		;;
	--bastion)
		NETWORK_BASTION="true"
		shift 1
		;;
	--data-filesystem)
		DATA_FILESYSTEM_ENABLED="true"
		shift 1
		;;
	--monitoring)
		MONITORING_ENABLED="true"
		shift 1
		;;
	--mon-ingestion-endpoint)
		MON_INGESTION_ENDPOINT="$2"
		shift 2
		;;
	--mon-dcr-id)
		MON_DCR_ID="$2"
		shift 2
		;;
	--entra-id)
		ENTRA_ID_ENABLED="true"
		shift 1
		;;
	--entra-app-umi)
		ENTRA_APP_UMI="$2"
		shift 2
		;;
	--entra-app-id)
		ENTRA_APP_ID="$2"
		shift 2
		;;
	--htc-use-spot)
		HTC_USE_SPOT="true"
		shift 1
		;;
	--slurm-no-start)
		SLURM_START_CLUSTER="false"
		shift 1
		;;
	--open-ondemand)
		OOD_ENABLED="true"
		shift 1
		;;
	--ood-sku)
		OOD_SKU="$2"
		shift 2
		;;
	--ood-image)
		OOD_IMAGE="$2"
		shift 2
		;;
	--ood-user-domain)
		OOD_USER_DOMAIN="$2"
		shift 2
		;;
	--ood-fqdn)
		OOD_FQDN="$2"
		shift 2
		;;
	--ood-no-start)
		OOD_START_CLUSTER="false"
		shift 1
		;;
	--htc-max-nodes)
		HTC_MAX_NODES="$2"
		shift 2
		;;
	--hpc-max-nodes)
		HPC_MAX_NODES="$2"
		shift 2
		;;
	--gpu-max-nodes)
		GPU_MAX_NODES="$2"
		shift 2
		;;
	--db-name)
		DB_NAME="$2"
		shift 2
		;;
	--db-user)
		DB_USERNAME="$2"
		shift 2
		;;
	--db-password)
		DB_PASSWORD="$2"
		shift 2
		;;
	--db-id)
		DB_ID="$2"
		shift 2
		;;
	--create-accounting-mysql)
		CREATE_ACCOUNTING_MYSQL="true"
		shift 1
		;;
	--db-generate-name)
		DB_GENERATE_NAME="true"
		shift 1
		;;
	--no-az)
		NO_AZ="true"
		SPECIFY_AZ="false"
		shift 1
		;;
	--specify-az)
		SPECIFY_AZ="true"
		NO_AZ="false"
		shift 1
		;;
	--accept-marketplace)
		ACCEPT_MARKETPLACE="true"
		shift 1
		;;
	--deploy)
		DO_DEPLOY="true"
		shift 1
		;;
	--debug)
		DEBUG_ENABLED="true"
		shift 1
		;;
	--silent)
		SILENT="true"
		shift 1
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage
		exit 1
		;;
	esac
done

required=(SUBSCRIPTION_ID RESOURCE_GROUP LOCATION SSH_KEY_FILE ADMIN_PASSWORD)
missing=()
for var in "${required[@]}"; do
	if [[ -z "${!var:-}" ]]; then missing+=("$var"); fi
done
if ((${#missing[@]})); then
	echo "Missing required arguments: ${missing[*]}" >&2
	usage
	exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then
	echo "SSH key file not found: $SSH_KEY_FILE" >&2
	exit 1
fi
SSH_PUBLIC_KEY="$(tr -d '\n' <"$SSH_KEY_FILE")"
# Generate database name if requested
if [[ "$DB_GENERATE_NAME" == "true" ]]; then
	if [[ "$CREATE_ACCOUNTING_MYSQL" != "true" ]]; then
		echo "[ERROR] --db-generate-name requires --create-accounting-mysql (auto-create mode)." >&2
		exit 1
	fi
	if [[ -n "$DB_NAME" ]]; then
		echo "[INFO] --db-generate-name ignored because --db-name already provided: $DB_NAME" >&2
	else
		# Generate a random db name (lowercase, starts with ccdb-) length 12
		if command -v openssl >/dev/null 2>&1; then
			DB_NAME="ccdb-$(openssl rand -hex 4)"
		else
			DB_NAME="ccdb-$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || echo $RANDOM)"
		fi
		echo "[INFO] Generated database name: $DB_NAME" >&2
	fi
fi
# Prompting & validation for required compute SKUs if omitted
prompt_for_sku() {
	local var_name="$1" label="$2" sku_value
	while true; do
		read -r -p "Enter ${label} VM SKU (e.g. Standard_D4as_v5): " sku_value
		if [[ -z "$sku_value" ]]; then
			echo "[WARN] Empty value not allowed for ${label} SKU; please provide a valid Azure VM SKU." >&2
			continue
		fi
		load_compute_skus
		if validate_sku "$sku_value"; then
			eval "$var_name=\"$sku_value\""
			break
		else
			echo "[ERROR] SKU '$sku_value' not found in discovered list for region '${LOCATION}'." >&2
			if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
				# If discovery failed entirely, accept user input with warning
				echo "[WARN] Skipping validation due to empty SKU cache; proceeding with user-provided '$sku_value'." >&2
				eval "$var_name=\"$sku_value\""
				break
			fi
		fi
	done
}

validate_sku() {
	local candidate="$1"
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		return 1
	fi
	# Extract names before ':' and look for exact match
	if echo "$COMPUTE_SKUS_CACHE" | cut -d':' -f1 | grep -Fx "$candidate" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

if [[ -z "$NETWORK_ADDRESS_SPACE" || "$NETWORK_ADDRESS_SPACE" != */* ]]; then
	echo "[ERROR] --network-address-space must be a CIDR string. Provided: $NETWORK_ADDRESS_SPACE" >&2
	exit 1
fi

# Validate compute max nodes (must be positive integer)
# Validation helpers for max nodes
validate_max_nodes() {
	local val="$1" label="$2"
	if [[ -z "$val" ]]; then
		return 1
	fi
	if ! [[ "$val" =~ ^[0-9]+$ ]]; then
		echo "[ERROR] ${label} max nodes must be a positive integer. Provided: $val" >&2
		return 1
	fi
	if ((val < 1)); then
		echo "[ERROR] ${label} max nodes must be >= 1. Provided: $val" >&2
		return 1
	fi
	return 0
}

prompt_for_max_nodes() {
	local var_name="$1" label="$2" input
	while true; do
		read -r -p "Enter max nodes for ${label} partition: " input
		if validate_max_nodes "$input" "$label"; then
			eval "$var_name=\"$input\""
			break
		else
			echo "[INFO] Please enter a positive integer (>=1)." >&2
		fi
	done
}

# Database handling: existing server vs auto-create
if [[ "$CREATE_ACCOUNTING_MYSQL" == "true" ]]; then
	# Auto-create path requires name, user, password only.
	if [[ -z "$DB_NAME" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" ]]; then
		echo "[ERROR] --create-accounting-mysql requires --db-name, --db-user, and --db-password." >&2
		exit 1
	fi
	if ! command -v az >/dev/null 2>&1; then
		echo "[ERROR] az CLI not found; cannot create MySQL Flexible Server automatically." >&2
		exit 1
	fi
	echo "[INFO] Auto-creating minimal MySQL Flexible Server '$DB_NAME' for Slurm accounting..." >&2
	# Ensure subscription context
	az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null || echo "[WARN] Unable to set subscription (login may be required)." >&2
	# Ensure resource group exists (create if missing)
	if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
		echo "[INFO] Resource group '$RESOURCE_GROUP' already exists." >&2
	else
		echo "[INFO] Resource group '$RESOURCE_GROUP' not found; creating in location '$LOCATION'." >&2
		if ! az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null 2>&1; then
			echo "[ERROR] Failed to create resource group '$RESOURCE_GROUP'." >&2
			exit 1
		fi
		echo "[INFO] Created resource group '$RESOURCE_GROUP'." >&2
	fi
	# Attempt creation (idempotent: if already exists, skip error)
	if az mysql flexible-server show -n "$DB_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
		echo "[INFO] MySQL Flexible Server '$DB_NAME' already exists; skipping creation." >&2
	else
		if ! az mysql flexible-server create \
			--name "$DB_NAME" \
			--resource-group "$RESOURCE_GROUP" \
			--location "$LOCATION" \
			--admin-user "$DB_USERNAME" \
			--admin-password "$DB_PASSWORD" \
			--sku-name Standard_B1ms \
			--tier Burstable \
			--storage-size 20 \
			--high-availability Disabled \
			--public-access None >/dev/null 2>&1; then
			echo "[ERROR] Failed to create MySQL Flexible Server '$DB_NAME'." >&2
			exit 1
		fi
		echo "[INFO] Created MySQL Flexible Server '$DB_NAME'." >&2
	fi
	# Fetch resource ID
	DB_ID="$(az mysql flexible-server show -n "$DB_NAME" -g "$RESOURCE_GROUP" --query id -o tsv 2>/dev/null || echo "")"
	if [[ -z "$DB_ID" ]]; then
		echo "[ERROR] Unable to retrieve resource ID for MySQL Flexible Server '$DB_NAME'." >&2
		exit 1
	fi
	DB_ENABLED="true"
	echo "[INFO] Database configuration enabled (privateEndpoint) via auto-created server." >&2
elif [[ -n "$DB_NAME" || -n "$DB_USERNAME" || -n "$DB_PASSWORD" || -n "$DB_ID" ]]; then
	# Existing server path: require all four values
	if [[ -z "$DB_NAME" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" || -z "$DB_ID" ]]; then
		echo "[ERROR] Database parameters require --db-name, --db-user, --db-password, and --db-id all set (or use --create-accounting-mysql)." >&2
		exit 1
	fi
	DB_ENABLED="true"
	echo "[INFO] Database configuration enabled (privateEndpoint) using existing server ID." >&2
fi

# Load (and cache) VM SKU zone information for the target region using az + jq.
# Populates COMPUTE_SKUS_CACHE as lines of the form:
#   Standard_D4as_v5:1 2 3
# or (no zones):
#   Standard_F2s_v2:
# Safe fallbacks if az or jq are missing or the command fails.
load_compute_skus() {
	# If already populated, skip re-fetching
	if [[ -n "$COMPUTE_SKUS_CACHE" ]]; then
		return 0
	fi
	if ! command -v az >/dev/null 2>&1; then
		echo "[ERROR] az CLI not found; zone discovery cannot proceed." >&2
		COMPUTE_SKUS_CACHE=""
		exit 1
	fi
	if ! command -v jq >/dev/null 2>&1; then
		echo "[ERROR] jq not found; zone discovery cannot proceed." >&2
		COMPUTE_SKUS_CACHE=""
		exit 1
	fi
	echo "[INFO] Discovering VM SKUs and zones for region '${LOCATION}'..." >&2

	# Build JMESPath query to filter SKUs (include all SKUs that need validation)

	local query_filter=""
	local filter_parts=()
	local all_skus_specified="true"

	# Track which SKUs are specified; if any expected SKU is missing, skip filtering.
	if [[ -n "$HTC_SKU" ]]; then
		filter_parts+=("name=='$HTC_SKU'")
	else
		all_skus_specified="false"
	fi
	if [[ -n "$HPC_SKU" ]]; then
		filter_parts+=("name=='$HPC_SKU'")
	else
		all_skus_specified="false"
	fi
	if [[ -n "$GPU_SKU" ]]; then
		filter_parts+=("name=='$GPU_SKU'")
	else
		all_skus_specified="false"
	fi
	if [[ -n "$SCHEDULER_SKU" ]]; then
		filter_parts+=("name=='$SCHEDULER_SKU'")
	else
		all_skus_specified="false"
	fi
	if [[ -n "$LOGIN_SKU" ]]; then
		filter_parts+=("name=='$LOGIN_SKU'")
	else
		all_skus_specified="false"
	fi
	if [[ "$OOD_ENABLED" == "true" ]]; then
		if [[ -n "$OOD_SKU" ]]; then
			filter_parts+=("name=='$OOD_SKU'")
		else
			all_skus_specified="false"
		fi
	fi

	# If any expected SKU is not specified, or no SKUs at all are set, skip filtering.
	if [[ "$all_skus_specified" != "true" || ${#filter_parts[@]} -eq 0 ]]; then
		debug_log "At least one SKU not specified; loading all SKUs without filtering."
		query_filter="value[?locationInfo!=null]"
	else
		# Build OR condition by joining with ||
		local condition=""
		for part in "${filter_parts[@]}"; do
			if [[ -z "$condition" ]]; then
				condition="$part"
			else
				condition="$condition || $part"
			fi
		done
		query_filter="value[?$condition]"
		debug_log "Loading SKUs with filter: HTC=$HTC_SKU, HPC=$HPC_SKU, GPU=$GPU_SKU, SCHEDULER=$SCHEDULER_SKU, LOGIN=$LOGIN_SKU, OOD=$OOD_SKU"
	fi
	local raw
	if ! raw=$(az rest --method get --url "/subscriptions/{subscriptionId}/providers/Microsoft.Compute/skus?api-version=2021-07-01&\$filter=location eq '${LOCATION}'" --query "$query_filter" -o json 2>/dev/null); then
		echo "[ERROR] az rest call to list SKUs failed; zone discovery cannot proceed." >&2
		COMPUTE_SKUS_CACHE=""
		return 1
	fi

	# Build mapping SKU:space_separated_zones (empty after colon if none)
	COMPUTE_SKUS_CACHE="$(echo "$raw" | jq -r '
		.[]
		| . as $sku
		| ($sku.locationInfo
			| map(select(.zones!=null))
			| map(.zones[])
			| unique
			| join(" ")
		  ) as $zones
		| "\($sku.name):\($zones)"
	')"
	local count
	count="$(echo "$COMPUTE_SKUS_CACHE" | wc -l | tr -d ' ')"
	echo "[INFO] Cached zone info for ${count} SKUs." >&2
}

# Fetch space-separated availability zones for a given SKU from the cached data.
# Usage: fetch_region_zones <region> <sku>
fetch_region_zones() {
	local sku="$1"
	# Troubleshooting / debug logging for SKU zone extraction
	if [[ -z "$sku" ]]; then
		echo "[ERROR] fetch_region_zones called with empty SKU argument." >&2
		exit 1
	fi
	debug_log "fetch_region_zones: attempting zone lookup for SKU='${sku}' in region='${LOCATION}'."
	# Ensure cache loaded
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		debug_log "COMPUTE_SKUS_CACHE empty prior to load; invoking load_compute_skus."
		load_compute_skus
	fi
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		debug_log "COMPUTE_SKUS_CACHE still empty after load attempt; returning no zones."
		return 1
	fi
	local line zones
	# Exact match on SKU name followed by colon
	line="$(echo "$COMPUTE_SKUS_CACHE" | grep -E "^${sku}:" || true)"
	if [[ -z "$line" ]]; then
		debug_log "SKU '${sku}' not found in cached list (cache lines: $(echo "$COMPUTE_SKUS_CACHE" | wc -l | tr -d ' '))."
		echo ""
		return 0
	fi
	zones="${line#*:}"
	if [[ -z "$zones" ]]; then
		debug_log "SKU '${sku}' found but zones list empty (non‑zonal SKU or discovery limitation)."
		echo ""
		return 0
	fi
	debug_log "SKU '${sku}' zones resolved: ${zones}"
	echo "$zones"
}

# Determine if the current region appears to have any availability zone capable VM SKUs.
# Returns 0 (success) if at least one SKU lists one or more zones; 1 otherwise.
# Usage: if region_has_zone_support; then echo "Region supports AZ"; else echo "No AZ support"; fi
# Assumes load_compute_skus has already been called when SPECIFY_AZ is true.
region_has_zone_support() {
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		# No data -> assume no zone support (could also be tooling missing).
		return 1
	fi
	# Look for any line with colon followed by at least one digit (zone number 1..N)
	if echo "$COMPUTE_SKUS_CACHE" | grep -Eq ':[0-9]'; then
		return 0
	else
		return 1
	fi
}

# Generate a random lowercase alphanumeric name with prefix
generate_random_name() {
	local prefix="ccw"
	local rand=""
	if command -v openssl >/dev/null 2>&1; then
		rand="$(openssl rand -hex 4)"
	else
		rand="$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || echo "$RANDOM")"
	fi
	echo "${prefix}-${rand}"
}

prompt_zone() {
	local label="$1" sku="$2" current="$3" zones="$4"
	local region="$LOCATION"
	if [[ -n "$current" ]]; then
		echo "[INFO] $label array $sku availability zone set through commandline to: $current" >&2
		echo "$current"
		return 0
	fi

	read -r -p "Select availability zone (e.g. 1) for $label SKU '$sku' or press Enter for none: " sel
	if [[ -n "$sel" ]]; then
		if [[ -n "$zones" ]]; then
			if echo "$zones" | tr '\t' ' ' | tr ' ' '\n' | grep -Fx "$sel" >/dev/null 2>&1; then
				echo "$sel"
				return 0
			else
				echo "[WARN] '$sel' is not in discovered zones list; proceeding anyway." >&2
				echo "$sel"
				return 0
			fi
		else
			echo "$sel"
			return 0
		fi
	else
		echo ""
		return 0
	fi
}

# Manual zone prompt for storage (ANF / AMLFS) without auto-discovery
prompt_zone_manual() {
	local label="$1" current="$2"
	if [[ -n "$current" ]]; then
		echo "[INFO] $label availability zone preset: $current" >&2
		echo "$current"
		return 0
	fi
	echo "[INFO] ${label}: availability zone not auto-discovered. Typical zonal regions use 1,2,3. Leave blank for none." >&2
	read -r -p "Enter availability zone for ${label} (blank for none): " sel
	if [[ -n "$sel" ]]; then echo "$sel"; else echo ""; fi
}

# Validate monitoring requirements early (before AZ checks)
if [[ "$MONITORING_ENABLED" == "true" ]]; then
	if [[ -z "$MON_INGESTION_ENDPOINT" ]]; then
		echo "[ERROR] --monitoring requires --mon-ingestion-endpoint to be specified." >&2
		exit 1
	fi
	if [[ -z "$MON_DCR_ID" ]]; then
		echo "[ERROR] --monitoring requires --mon-dcr-id to be specified." >&2
		exit 1
	fi
fi

# Validate Entra ID requirements
if [[ "$ENTRA_ID_ENABLED" == "true" ]]; then
	if [[ -z "$ENTRA_APP_UMI" ]]; then
		echo "[ERROR] --entra-id requires --entra-app-umi to be specified." >&2
		exit 1
	fi
	if [[ -z "$ENTRA_APP_ID" ]]; then
		echo "[ERROR] --entra-id requires --entra-app-id to be specified." >&2
		exit 1
	fi
	# Get tenant ID from active subscription (used for both Entra ID and OOD)
	TENANT_ID=$(az account show --query tenantId -o tsv 2>/dev/null || echo "")
	if [[ -z "$TENANT_ID" ]]; then
		echo "[ERROR] Unable to retrieve tenant ID from active subscription." >&2
		exit 1
	fi
	echo "[INFO] Retrieved tenant ID: ${TENANT_ID}" >&2
fi

# Validate Open OnDemand requirements early (before AZ checks)
if [[ "$OOD_ENABLED" == "true" ]]; then
	if [[ "$ENTRA_ID_ENABLED" != "true" ]]; then
		echo "[ERROR] --open-ondemand requires --entra-id to be enabled." >&2
		exit 1
	fi
	if [[ -z "$OOD_USER_DOMAIN" ]]; then
		echo "[ERROR] --open-ondemand requires --ood-user-domain to be specified." >&2
		exit 1
	fi
	if [[ -z "$OOD_SKU" ]]; then
		echo "[ERROR] --ood-sku may not be empty when Open OnDemand is enabled." >&2
		exit 1
	fi
	# Basic FQDN validation (optional): if provided, must contain at least one dot and no spaces
	if [[ -n "$OOD_FQDN" ]]; then
		if [[ "$OOD_FQDN" =~ [[:space:]] ]]; then
			echo "[ERROR] --ood-fqdn may not contain whitespace. Provided: $OOD_FQDN" >&2
			exit 1
		fi
		if [[ ! "$OOD_FQDN" =~ \. ]]; then
			echo "[WARN] --ood-fqdn '$OOD_FQDN' does not appear to be a FQDN (missing dot). Proceeding anyway." >&2
		fi
	fi
fi

# Validate all VM SKUs exist in the target region
validate_all_skus() {
	echo "[INFO] Validating all VM SKUs exist in region '${LOCATION}'..." >&2
	
	# Ensure SKU cache is loaded
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		load_compute_skus
	fi
	
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		echo "[ERROR] Unable to load VM SKU information for region '${LOCATION}'. Cannot validate SKUs." >&2
		exit 1
	fi
	
	local validation_failed=false
	local skus_to_validate=()
	
	# Collect all SKUs that need validation
	skus_to_validate+=("${SCHEDULER_SKU}:Scheduler")
	skus_to_validate+=("${LOGIN_SKU}:Login")
	skus_to_validate+=("${HTC_SKU}:HTC")
	skus_to_validate+=("${HPC_SKU}:HPC") 
	skus_to_validate+=("${GPU_SKU}:GPU")
	
	# Add OOD SKU if Open OnDemand is enabled
	if [[ "$OOD_ENABLED" == "true" ]]; then
		skus_to_validate+=("${OOD_SKU}:OpenOnDemand")
	fi
	
	# Validate each SKU
	for sku_entry in "${skus_to_validate[@]}"; do
		local sku="${sku_entry%%:*}"
		local label="${sku_entry##*:}"
		
		if ! validate_sku "$sku"; then
			echo "[ERROR] ${label} SKU '${sku}' is not available in region '${LOCATION}'" >&2
			validation_failed=true
		else
			echo "[INFO] ✓ ${label} SKU '${sku}' validated in region '${LOCATION}'" >&2
		fi
	done
	
	if [[ "$validation_failed" == "true" ]]; then
		echo "[ERROR] One or more VM SKUs are not available in the target region. Please choose different SKUs or a different region." >&2
		echo "[INFO] Available SKUs in region '${LOCATION}':" >&2
		echo "$COMPUTE_SKUS_CACHE" | cut -d':' -f1 | head -20
		if [[ $(echo "$COMPUTE_SKUS_CACHE" | wc -l) -gt 20 ]]; then
			echo "... (showing first 20, total: $(echo "$COMPUTE_SKUS_CACHE" | wc -l))" >&2
		fi
		exit 1
	fi
	
	echo "[INFO] All VM SKUs validated successfully for region '${LOCATION}'" >&2
}

# Only load compute SKUs if we need zone discovery or if any SKU is empty
if [[ "$SPECIFY_AZ" == "true" \
	|| -z "${HTC_SKU:-}" \
	|| -z "${HPC_SKU:-}" \
	|| -z "${GPU_SKU:-}" \
	|| -z "${SCHEDULER_SKU:-}" \
	|| -z "${LOGIN_SKU:-}" \
	|| ( "$OOD_ENABLED" == "true" && -z "${OOD_SKU:-}" )
 ]]; then
	load_compute_skus
fi

# Prompt for SKUs if missing
if [[ -z "${HTC_SKU:-}" ]]; then
	echo "[INFO] HTC SKU not provided via CLI; entering interactive prompt." >&2
	prompt_for_sku HTC_SKU "HTC"
fi
if [[ -z "${HPC_SKU:-}" ]]; then
	echo "[INFO] HPC SKU not provided via CLI; entering interactive prompt." >&2
	prompt_for_sku HPC_SKU "HPC"
fi
if [[ -z "${GPU_SKU:-}" ]]; then
	echo "[INFO] GPU SKU not provided via CLI; entering interactive prompt." >&2
	prompt_for_sku GPU_SKU "GPU"
fi

# Prompt for max nodes if missing
if ! validate_max_nodes "$HTC_MAX_NODES" "HTC"; then
	echo "[INFO] HTC max nodes not provided; entering interactive prompt." >&2
	prompt_for_max_nodes HTC_MAX_NODES "HTC"
fi
if ! validate_max_nodes "$HPC_MAX_NODES" "HPC"; then
	echo "[INFO] HPC max nodes not provided; entering interactive prompt." >&2
	prompt_for_max_nodes HPC_MAX_NODES "HPC"
fi
if ! validate_max_nodes "$GPU_MAX_NODES" "GPU"; then
	echo "[INFO] GPU max nodes not provided; entering interactive prompt." >&2
	prompt_for_max_nodes GPU_MAX_NODES "GPU"
fi

# Validate all VM SKUs exist in the target region before proceeding
validate_all_skus

if [[ "$NO_AZ" == "true" ]]; then
	# Check if user specified any zone parameters along with --no-az
	if [[ -n "${HTC_AZ:-}" || -n "${HPC_AZ:-}" || -n "${GPU_AZ:-}" || -n "${ANF_AZ:-}" || -n "${AMLFS_AZ:-}" ]]; then
		echo "[ERROR] --no-az and zone specifications (--htc-az, --hpc-az, --gpu-az, --anf-az, --amlfs-az) are mutually exclusive. Please remove either --no-az or the zone parameters." >&2
		exit 1
	fi
	echo "[INFO] --no-az specified; disabling all availability zones." >&2
	HTC_AZ=""
	HPC_AZ=""
	GPU_AZ=""
	ANF_AZ=""
	AMLFS_AZ=""
elif [[ "$SPECIFY_AZ" == "true" ]]; then
	# User explicitly requested zone prompting - always prompt even if auto-discovery doesn't find zones
	POTENTIAL_HTC_AZ="$(fetch_region_zones "$HTC_SKU")"
	POTENTIAL_HPC_AZ="$(fetch_region_zones "$HPC_SKU")"
	POTENTIAL_GPU_AZ="$(fetch_region_zones "$GPU_SKU")"

	if [[ -n "$POTENTIAL_HTC_AZ" ]]; then echo "[INFO] HTC array $HTC_SKU available zones: $POTENTIAL_HTC_AZ" >&2; else echo "[INFO] $HTC_SKU has no zonal availability in region $LOCATION (manual entry allowed)" >&2; fi
	if [[ -n "$POTENTIAL_HPC_AZ" ]]; then echo "[INFO] HPC array $HPC_SKU available zones: $POTENTIAL_HPC_AZ" >&2; else echo "[INFO] $HPC_SKU has no zonal availability in region $LOCATION (manual entry allowed)" >&2; fi
	if [[ -n "$POTENTIAL_GPU_AZ" ]]; then echo "[INFO] GPU array $GPU_SKU available zones: $POTENTIAL_GPU_AZ" >&2; else echo "[INFO] $GPU_SKU has no zonal availability in region $LOCATION (manual entry allowed)" >&2; fi

	# Only prompt for partitions where a zone wasn't provided on CLI
	HTC_AZ="$(prompt_zone HTC "${HTC_SKU}" "${HTC_AZ:-}" "${POTENTIAL_HTC_AZ}")"
	HPC_AZ="$(prompt_zone HPC "${HPC_SKU}" "${HPC_AZ:-}" "${POTENTIAL_HPC_AZ}")"
	GPU_AZ="$(prompt_zone GPU "${GPU_SKU}" "${GPU_AZ:-}" "${POTENTIAL_GPU_AZ}")"

	ANF_AZ="$(prompt_zone_manual ANF "${ANF_AZ:-}")"

	# Only prompt for AMLFS zone if data filesystem is enabled
	if [[ "$DATA_FILESYSTEM_ENABLED" == "true" ]]; then
		AMLFS_AZ="$(prompt_zone_manual AMLFS "${AMLFS_AZ:-}")"
	fi
else
	# SPECIFY_AZ not true
	if [[ -n "${HTC_AZ:-}" || -n "${HPC_AZ:-}" || -n "${GPU_AZ:-}" || -n "${ANF_AZ:-}" || -n "${AMLFS_AZ:-}" ]]; then
		echo "[ERROR] Availability zone(s) provided via CLI but --specify-az flag not set. Re-run with --specify-az to enforce AZ placement." >&2
		exit 1
	else
		echo "[INFO] --specify-az not provided and no AZs specified; proceeding with no AZ enforcement (availabilityZone arrays will be empty)." >&2
		HTC_AZ=""
		HPC_AZ=""
		GPU_AZ=""
		ANF_AZ=""
		AMLFS_AZ=""
	fi
fi

# Default AMLFS zone to 1 if none provided (AMLFS requires a zone)
if [[ "$DATA_FILESYSTEM_ENABLED" == "true" ]]; then
	if [[ -z "${AMLFS_AZ}" ]]; then
		echo "[INFO] AMLFS zone not specified; defaulting to '1'." >&2
		AMLFS_AZ="1"
	fi
fi

# Prepare JSON fragments for optional availability zone (include leading comma when present)
if [[ -n "${HTC_AZ}" ]]; then HTC_ZONES_JSON=", \"availabilityZone\": [\"${HTC_AZ}\"]"; else HTC_ZONES_JSON=""; fi
if [[ -n "${HPC_AZ}" ]]; then HPC_ZONES_JSON=", \"availabilityZone\": [\"${HPC_AZ}\"]"; else HPC_ZONES_JSON=""; fi
if [[ -n "${GPU_AZ}" ]]; then GPU_ZONES_JSON=", \"availabilityZone\": [\"${GPU_AZ}\"]"; else GPU_ZONES_JSON=""; fi
if [[ -n "${ANF_AZ}" ]]; then ANF_ZONES_JSON=", \"availabilityZone\": [\"${ANF_AZ}\"]"; else ANF_ZONES_JSON=""; fi
if [[ -n "${AMLFS_AZ}" ]]; then AMLFS_ZONES_JSON=", \"availabilityZone\": [\"${AMLFS_AZ}\"]"; else AMLFS_ZONES_JSON=""; fi

# Validate ANF inputs
if ! [[ "$ANF_SIZE" =~ ^[0-9]+$ ]]; then
	echo "[ERROR] --anf-size must be an integer (TiB). Provided: $ANF_SIZE" >&2
	exit 1
fi
if ((ANF_SIZE < 1)); then
	echo "[ERROR] --anf-size must be >= 1 TiB. Provided: $ANF_SIZE" >&2
	exit 1
fi
case "$ANF_SKU" in
Standard | Premium | Ultra) ;;
*)
	echo "[ERROR] --anf-sku must be one of Standard|Premium|Ultra. Provided: $ANF_SKU" >&2
	exit 1
	;;
esac

# Validate AMLFS inputs (only if data filesystem is enabled)
if [[ "$DATA_FILESYSTEM_ENABLED" == "true" ]]; then
	if ! [[ "$AMLFS_SIZE" =~ ^[0-9]+$ ]]; then
		echo "[ERROR] --amlfs-size must be an integer (TiB). Provided: $AMLFS_SIZE" >&2
		exit 1
	fi
	if ((AMLFS_SIZE < 4)); then
		echo "[ERROR] --amlfs-size must be >= 4 TiB. Provided: $AMLFS_SIZE" >&2
		exit 1
	fi
	case "$AMLFS_SKU" in
	AMLFS-Durable-Premium-40 | AMLFS-Durable-Premium-125 | AMLFS-Durable-Premium-250 | AMLFS-Durable-Premium-500) ;;
	*)
		echo "[ERROR] --amlfs-sku must be one of AMLFS-Durable-Premium-40|AMLFS-Durable-Premium-125|AMLFS-Durable-Premium-250|AMLFS-Durable-Premium-500. Provided: $AMLFS_SKU" >&2
		exit 1
		;;
	esac
fi

# Clone workspace repo if not present
if [[ -d "$WORKSPACE_DIR/.git" ]]; then
	echo "[INFO] Workspace repo already present at $WORKSPACE_DIR"
else
	echo "[INFO] Cloning workspace repo to $WORKSPACE_DIR"
	git clone "$WORKSPACE_REPO_URL" "$WORKSPACE_DIR"
fi

pushd "$WORKSPACE_DIR" >/dev/null
echo "[INFO] Checking out ref $WORKSPACE_REF"
git fetch --all --tags --force
if [[ -n "$WORKSPACE_COMMIT" ]]; then
	echo "[INFO] Workspace commit override specified: $WORKSPACE_COMMIT"
	# Verify commit exists
	if git rev-parse --verify "$WORKSPACE_COMMIT^{commit}" >/dev/null 2>&1; then
		git checkout "$WORKSPACE_COMMIT" || {
			echo "[ERROR] Failed to checkout commit $WORKSPACE_COMMIT" >&2
			exit 1
		}
		echo "[INFO] Checked out commit $WORKSPACE_COMMIT (detached HEAD)"
	else
		echo "[ERROR] Commit $WORKSPACE_COMMIT not found in repository" >&2
		exit 1
	fi
else
	git checkout "$WORKSPACE_REF" || {
		echo "[ERROR] Failed to checkout ref $WORKSPACE_REF" >&2
		exit 1
	}
fi

echo "[INFO] Generating output.json at $OUTPUT_FILE"
if [[ "$DB_ENABLED" == "true" ]]; then
	# Only include databaseConfig; databaseAdminPassword is now passed via CLI to avoid persisting secrets.
	DB_JSON_DATABASE_CONFIG='"databaseConfig": { "value": { "type": "privateEndpoint", "databaseUser": "'"${DB_USERNAME}"'", "dbInfo": { "name": "'"${DB_NAME}"'", "id": "'"${DB_ID}"'", "location": "'"${LOCATION}"'", "subscriptionName": "" } } },'
else
	DB_JSON_DATABASE_CONFIG='"databaseConfig": { "value": { "type": "disabled" } },'
fi

# Construct Open OnDemand JSON fragment (minimal when disabled)
if [[ "$OOD_ENABLED" == "true" ]]; then
	OOD_JSON='"ood": { "value": { "type": "enabled", "startCluster": '"${OOD_START_CLUSTER}"', "sku": "'"${OOD_SKU}"'", "osImage": "'"${OOD_IMAGE}"'", "userDomain": "'"${OOD_USER_DOMAIN}"'", "fqdn": "'"${OOD_FQDN}"'", "registerEntraIDApp": false, "appId": "'"${ENTRA_APP_ID}"'", "appManagedIdentityId": "'"${ENTRA_APP_UMI}"'", "appTenantId": "'"${TENANT_ID}"'" } },'
else
	OOD_JSON='"ood": { "value": { "type": "disabled" } },'
fi

# Construct AMLFS JSON fragment (conditional on enabled flag)
if [[ "$DATA_FILESYSTEM_ENABLED" == "true" ]]; then
	AMLFS_JSON='"additionalFilesystem": { "value": { "type": "aml-new", "lustreTier": "'"${AMLFS_SKU}"'", "lustreCapacityInTib": '${AMLFS_SIZE}', "mountPath": "/data"'"${AMLFS_ZONES_JSON}"' } },'
else
	AMLFS_JSON='"additionalFilesystem": { "value": { "type": "disabled" } },'
fi

# Construct monitoring JSON fragment (conditional on enabled flag)
if [[ "$MONITORING_ENABLED" == "true" ]]; then
	MONITORING_JSON='"monitoring": { "value": { "type": "enabled", "ingestionEndpoint": "'"${MON_INGESTION_ENDPOINT}"'", "dcrId": "'"${MON_DCR_ID}"'" } },'
else
	MONITORING_JSON='"monitoring": { "value": { "type": "disabled" } },'
fi

# Construct Entra SSO JSON fragment (conditional on enabled flag)
if [[ "$ENTRA_ID_ENABLED" == "true" ]]; then
	ENTRA_ID_JSON='"entraIdInfo": { "value": { "type": "enabled", "managedIdentityId": "'"${ENTRA_APP_UMI}"'", "clientId": "'"${ENTRA_APP_ID}"'", "tenantId": "'"${TENANT_ID}"'" } },'
else
	ENTRA_ID_JSON='"entraIdInfo": { "value": { "type": "disabled" } },'
fi

# Retrieve Slurm default version from workspace UI definitions file
if ! SLURM_VERSION=$(jq -r '.. | objects | select(.name == "slurmVersion") | .defaultValue' "$WORKSPACE_DIR/uidefinitions/createUiDefinition.json"); then
	echo "[ERROR] Failed to extract Slurm default version from '$WORKSPACE_DIR/uidefinitions/createUiDefinition.json' using jq." >&2
	echo "Please ensure the file exists, is valid JSON, and contains an entry with name \"slurmVersion\" and a defaultValue." >&2
	exit 1
fi

if [[ -z "${SLURM_VERSION}" || "${SLURM_VERSION}" == "null" ]]; then
	echo "[ERROR] Extracted Slurm default version is empty or null from '$WORKSPACE_DIR/uidefinitions/createUiDefinition.json'." >&2
	echo "Please verify the 'slurmVersion' entry has a non-empty defaultValue." >&2
	exit 1
fi
cat >"$OUTPUT_FILE" <<EOF
{
	"\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
	"contentVersion": "1.0.0.0",
	"parameters": {
		"location": { "value": "${LOCATION}" },
		"adminUsername": { "value": "${ADMIN_USERNAME}" },
		"adminSshPublicKey": { "value": "${SSH_PUBLIC_KEY}" },
		"clusterName": { "value": "${CLUSTER_NAME}" },
		"ccVMName": { "value": "ccw-cyclecloud-vm" },
		"ccVMSize": { "value": "${SCHEDULER_SKU}" },
		"resourceGroup": { "value": "${RESOURCE_GROUP}" },
		"sharedFilesystem": { "value": { "type": "anf-new", "anfServiceTier": "${ANF_SKU}", "anfCapacityInTiB": ${ANF_SIZE}${ANF_ZONES_JSON} } },
		${AMLFS_JSON}
		"network": { "value": { "type": "new", "addressSpace": "${NETWORK_ADDRESS_SPACE}", "bastion": ${NETWORK_BASTION}, "createNatGateway": true } },
		"storagePrivateDnsZone": { "value": { "type": "new" } },
		${DB_JSON_DATABASE_CONFIG}
		"acceptMarketplaceTerms": { "value": ${ACCEPT_MARKETPLACE} },
		"slurmSettings": { "value": { "startCluster": ${SLURM_START_CLUSTER}, "version": "${SLURM_VERSION}", "healthCheckEnabled": false } },
		"schedulerNode": { "value": { "sku": "${SCHEDULER_SKU}", "osImage": "${SCHEDULER_IMAGE}" } },
		"loginNodes": { "value": { "sku": "${LOGIN_SKU}", "osImage": "${LOGIN_IMAGE}", "initialNodes": 1, "maxNodes": 1 } },
		"htc": { "value": { "sku": "${HTC_SKU}", "maxNodes": ${HTC_MAX_NODES}, "osImage": "${HTC_IMAGE}", "useSpot": ${HTC_USE_SPOT}${HTC_ZONES_JSON} } },
		"hpc": { "value": { "sku": "${HPC_SKU}", "maxNodes": ${HPC_MAX_NODES}, "osImage": "${HPC_IMAGE}"${HPC_ZONES_JSON} } },
		"gpu": { "value": { "sku": "${GPU_SKU}", "maxNodes": ${GPU_MAX_NODES}, "osImage": "${GPU_IMAGE}"${GPU_ZONES_JSON} } },
		${OOD_JSON}
		${MONITORING_JSON}
		${ENTRA_ID_JSON}
		"tags": { "value": {} }
	}
}
EOF

RANDOM_NAME="$(generate_random_name)"
echo "[INFO] Generated random name: ${RANDOM_NAME}"

echo "[INFO] output.json generation complete"
echo "[INFO] Path: $OUTPUT_FILE"
echo "[INFO] To deploy manually (passwords not persisted in output.json):" >&2
if [[ "$DB_ENABLED" == "true" ]]; then
	echo "       az deployment sub create --name $RANDOM_NAME --location $LOCATION \"" >&2
	echo "          --template-file $WORKSPACE_DIR/bicep/mainTemplate.bicep --parameters @\"$OUTPUT_FILE\" adminPassword=\"<ADMIN_PASSWORD>\" databaseAdminPassword=\"<DB_ADMIN_PASSWORD>\"" >&2
	echo "       (replace <ADMIN_PASSWORD> and <DB_ADMIN_PASSWORD> with actual values; neither was written to $OUTPUT_FILE)" >&2
else
	echo "       az deployment sub create --name $RANDOM_NAME --location $LOCATION \"" >&2
	echo "          --template-file $WORKSPACE_DIR/bicep/mainTemplate.bicep --parameters @\"$OUTPUT_FILE\" adminPassword=\"<ADMIN_PASSWORD>\" databaseAdminPassword=\"\"" >&2
	echo "       (replace <ADMIN_PASSWORD>; databaseAdminPassword empty and not persisted)" >&2
fi

echo ""
echo "================ Deployment Configuration Summary ================"
echo "Subscription ID:        ${SUBSCRIPTION_ID}"
echo "Resource Group:         ${RESOURCE_GROUP}"
echo "Region:                 ${LOCATION}"
echo "Workspace Ref:          ${WORKSPACE_REF}"
echo "Workspace Commit:       ${WORKSPACE_COMMIT:-<none>}"
echo "Scheduler SKU:          ${SCHEDULER_SKU}"
echo "Login SKU:              ${LOGIN_SKU}"
echo "Slurm Start Cluster:    ${SLURM_START_CLUSTER}"
echo "HTC SKU / AZ / Max:     ${HTC_SKU} / ${HTC_AZ:-<none>} / ${HTC_MAX_NODES}"
echo "HTC Use Spot:           ${HTC_USE_SPOT}"
echo "Open OnDemand Enabled:  ${OOD_ENABLED}"
echo "Open OnDemand SKU:      ${OOD_SKU}"
echo "Open OnDemand Domain:   ${OOD_USER_DOMAIN:-<none>}"
echo "Open OnDemand FQDN:     ${OOD_FQDN:-<none>}"
echo "OOD Start Cluster:      ${OOD_START_CLUSTER}"
echo "HPC SKU / AZ / Max:     ${HPC_SKU} / ${HPC_AZ:-<none>} / ${HPC_MAX_NODES}"
echo "GPU SKU / AZ / Max:     ${GPU_SKU} / ${GPU_AZ:-<none>} / ${GPU_MAX_NODES}"
echo "ANF Tier / Size / AZ:   ${ANF_SKU} / ${ANF_SIZE} / ${ANF_AZ:-<none>}"
echo "Data Filesystem:        ${DATA_FILESYSTEM_ENABLED}"
if [[ "$DATA_FILESYSTEM_ENABLED" == "true" ]]; then
	echo "AMLFS Tier / Size / AZ: ${AMLFS_SKU} / ${AMLFS_SIZE} / ${AMLFS_AZ:-<none>}"
fi
echo "Monitoring Enabled:     ${MONITORING_ENABLED}"
if [[ "$MONITORING_ENABLED" == "true" ]]; then
	echo "Mon Ingestion Endpoint: ${MON_INGESTION_ENDPOINT}"
	echo "Mon DCR ID:             ${MON_DCR_ID}"
fi
echo "Entra ID Enabled:       ${ENTRA_ID_ENABLED}"
if [[ "$ENTRA_ID_ENABLED" == "true" ]]; then
	echo "Entra App UMI:          ${ENTRA_APP_UMI}"
	echo "Entra App ID:           ${ENTRA_APP_ID}"
fi
echo "Accept Marketplace:     ${ACCEPT_MARKETPLACE}"
echo "Network Address Space:  ${NETWORK_ADDRESS_SPACE}"
echo "Bastion Enabled:        ${NETWORK_BASTION}"
echo "Scheduler Image:        ${SCHEDULER_IMAGE}"
echo "Login Image:            ${LOGIN_IMAGE}"
echo "HTC Image:              ${HTC_IMAGE}"
echo "HPC Image:              ${HPC_IMAGE}"
echo "GPU Image:              ${GPU_IMAGE}"
echo "Open OnDemand Image:    ${OOD_IMAGE}"
echo "Scheduler Image:        ${SCHEDULER_IMAGE}"
echo "Login Image:            ${LOGIN_IMAGE}"
echo "HTC Image:              ${HTC_IMAGE}"
echo "HPC Image:              ${HPC_IMAGE}"
echo "GPU Image:              ${GPU_IMAGE}"
echo "Open OnDemand Image:    ${OOD_IMAGE}"
echo "HTC Max Nodes:          ${HTC_MAX_NODES}"
echo "HPC Max Nodes:          ${HPC_MAX_NODES}"
echo "GPU Max Nodes:          ${GPU_MAX_NODES}"
echo "Deployment Name (preview): ${RANDOM_NAME}"
echo "Admin Password Persisted:  false (must pass via CLI parameter)"
echo "Output Parameters File: ${OUTPUT_FILE}"
echo "Template Path:          ${WORKSPACE_DIR}/bicep/mainTemplate.bicep"
if [[ "$DB_ENABLED" == "true" ]]; then
	echo "Database Enabled:       true (privateEndpoint)"
	echo "Database Name:          ${DB_NAME}"
	echo "Database User:          ${DB_USERNAME}"
	echo "Database Resource ID:   ${DB_ID}"
	echo "MySQL Auto-Created:     ${CREATE_ACCOUNTING_MYSQL}"
	echo "DB Name Generated:      ${DB_GENERATE_NAME}"
	echo "DB Admin Password Persisted: false (passed via CLI)"
else
	echo "Database Enabled:       false"
fi
echo "=================================================================="
echo ""
if [[ "$DO_DEPLOY" != "true" ]]; then
	if [[ "$SILENT" == "true" ]]; then
		echo "[INFO] Silent mode enabled. Skipping deployment confirmation." >&2
	else
		echo "[INFO] Deployment flag not set. Prompting for interactive confirmation..." >&2
		COMMIT_DISPLAY="${WORKSPACE_COMMIT:-$WORKSPACE_REF}"
		if [[ -n "${WORKSPACE_COMMIT}" ]]; then
			COMMIT_URL="https://github.com/azure/cyclecloud-slurm-workspace/commit/${WORKSPACE_COMMIT}"
		else
			COMMIT_URL="https://github.com/azure/cyclecloud-slurm-workspace/tree/${WORKSPACE_REF}"
		fi
		echo "[INFO] About to deploy using repository ref: ${COMMIT_DISPLAY}" >&2
		echo "[INFO] Commit/Ref URL: ${COMMIT_URL}" >&2
		echo "[INFO] Verify this commit contains required hotfixes before proceeding." >&2
		read -r -p "Confirm deployment of ${COMMIT_DISPLAY}? (y/N): " REPLY
		case "$REPLY" in
		[yY])
			echo "[INFO] User confirmed interactive deployment."
			DO_DEPLOY="true"
			;;
		*)
			echo "[INFO] User did not confirm deployment (response: '$REPLY'). Exiting now."
			exit 0
			;;
		esac
	fi
fi

if [[ "$DO_DEPLOY" == "true" ]]; then
	echo "[INFO] Reasserting Azure subscription context: $SUBSCRIPTION_ID"
	az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null || echo "[WARN] Unable to set subscription (login required)."
	echo "[INFO] Performing az deployment sub create"
	if [[ "$DB_ENABLED" == "true" ]]; then
		az deployment sub create --name "$RANDOM_NAME" --location "$LOCATION" --template-file "$WORKSPACE_DIR/bicep/mainTemplate.bicep" --parameters @"$OUTPUT_FILE" adminPassword="$ADMIN_PASSWORD" databaseAdminPassword="$DB_PASSWORD" --debug || {
			echo "[ERROR] Deployment failed" >&2
			exit 1
		}
	else
		az deployment sub create --name "$RANDOM_NAME" --location "$LOCATION" --template-file "$WORKSPACE_DIR/bicep/mainTemplate.bicep" --parameters @"$OUTPUT_FILE" adminPassword="$ADMIN_PASSWORD" databaseAdminPassword="" --debug || {
			echo "[ERROR] Deployment failed" >&2
			exit 1
		}
	fi
	echo "[INFO] Deployment finished successfully"
fi

exit 0
