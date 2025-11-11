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

  CycleCloud Infrastructure SKUs:
    --scheduler-sku <sku>        Scheduler node VM SKU (default: Standard_D4as_v5)
    --login-sku <sku>            Login node VM SKU (default: Standard_D2as_v5)

  Workspace Repository:
    --workspace-ref <ref>        Git ref (branch/tag) to checkout (default: main)
    --workspace-commit <sha>     Explicit commit (detached HEAD override)
    --workspace-dir <path>       Clone destination (default: ./cyclecloud-slurm-workspace)
    --output-file <path>         Output parameters file path (default: ${DEFAULT_OUTPUT_FILE})

  Availability Zones:
    --specify-az                 Enable interactive AZ prompting (only if region has zonal SKUs)
    --htc-az <zone>              Explicit AZ for HTC partition (suppresses interactive prompt)
    --hpc-az <zone>              Explicit AZ for HPC partition (suppresses interactive prompt)
    --gpu-az <zone>              Explicit AZ for GPU partition (suppresses interactive prompt)

  Compute Partition Configuration:
    --htc-max-nodes <count>      Maximum nodes for HTC partition (interactive if omitted)
    --hpc-max-nodes <count>      Maximum nodes for HPC partition (interactive if omitted)
    --gpu-max-nodes <count>      Maximum nodes for GPU partition (interactive if omitted)
    --htc-use-spot               Use Spot (preemptible) VMs for HTC partition (flag)

  Network Configuration:
    --network-address-space <cidr>  Virtual network CIDR (default: 10.0.0.0/24)
    --bastion                    Enable Azure Bastion deployment (flag)

  Storage - Azure NetApp Files:
    --anf-sku <tier>             ANF service level: Standard|Premium|Ultra (default: Premium)
    --anf-size <TiB>             ANF capacity in TiB (integer, default: 2, minimum: 1)
    --anf-az <zone>              Availability zone for ANF (optional; interactive if omitted)

  Storage - Azure Managed Lustre:
    --amlfs-sku <tier>           AMLFS tier: AMLFS-Durable-Premium-{40|125|250|500} (default: 500)
    --amlfs-size <TiB>           AMLFS capacity in TiB (integer, default: 4, minimum: 4)
    --amlfs-az <zone>            Availability zone for AMLFS (defaults to 1 if region supports zones)

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
    --ood-sku <sku>              OOD VM SKU (default: Standard_D4as_v5)
    --ood-user-domain <domain>   User domain for OOD authentication (required with --open-ondemand)
    --ood-fqdn <fqdn>            Fully Qualified Domain Name for OOD (optional)
    --ood-auto-register          Auto-register new Entra ID application (flag)
    --ood-app-id <appId>         Existing Entra ID app ID (when not auto-registering)
    --ood-managed-identity-id <id>  Existing managed identity resource ID (when not auto-registering)

  Deployment Control:
    --accept-marketplace         Accept marketplace terms automatically
    --deploy                     Perform deployment after generating output.json
    --help                       Show this usage information

INTERACTIVE PROMPTS:
  If HTC/HPC/GPU SKUs or max nodes are not provided via CLI, the script will
  prompt interactively. Availability zone prompts occur only when --specify-az
  is set and the region supports zonal SKUs.

BEHAVIOR:
  * Auto-discovers zonal availability using 'az vm list-skus' + 'jq'
  * Skips AZ prompts if region lacks zonal SKUs or tools are missing
  * Generates parameter file with conditional database and storage sections
  * Interactive confirmation unless --deploy provided
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

  Full deployment with all features:
    $0 --subscription-id SUB --resource-group rg-ccw --location eastus \\
       --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password 'YourP@ssw0rd!' \\
       --htc-sku Standard_F2s_v2 --htc-az 1 --htc-max-nodes 100 --htc-use-spot \\
       --hpc-sku Standard_HB176rs_v4 --hpc-az 1 --hpc-max-nodes 50 \\
       --gpu-sku Standard_ND96amsr_A100_v4 --gpu-az 1 --gpu-max-nodes 20 \\
       --network-address-space 10.1.0.0/16 --bastion \\
       --anf-sku Premium --anf-size 4 --anf-az 1 \\
       --amlfs-sku AMLFS-Durable-Premium-500 --amlfs-size 8 --amlfs-az 1 \\
       --create-accounting-mysql --db-name myccdb --db-user dbadmin --db-password 'DbP@ss!' \\
       --open-ondemand --ood-user-domain contoso.com --ood-fqdn ood.contoso.com \\
       --ood-auto-register --accept-marketplace --deploy

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
SCHEDULER_SKU="Standard_D4as_v5"
LOGIN_SKU="Standard_D2as_v5"
HTC_SKU=""
HPC_SKU=""
GPU_SKU=""
WORKSPACE_REF="${WORKSPACE_REF:-main}" # allow pre-set env var to override default
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
OOD_ENABLED="false"
OOD_SKU="Standard_D4as_v5"
OOD_USER_DOMAIN=""
OOD_FQDN=""
OOD_AUTO_REGISTER="false"
OOD_APP_ID=""
OOD_MANAGED_IDENTITY_ID=""
CREATE_ACCOUNTING_MYSQL="false"
DB_GENERATE_NAME="false"

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
	--scheduler-sku)
		SCHEDULER_SKU="$2"
		shift 2
		;;
	--login-sku)
		LOGIN_SKU="$2"
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
	--htc-use-spot)
		HTC_USE_SPOT="true"
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
	--ood-user-domain)
		OOD_USER_DOMAIN="$2"
		shift 2
		;;
	--ood-fqdn)
		OOD_FQDN="$2"
		shift 2
		;;
	--ood-auto-register)
		OOD_AUTO_REGISTER="true"
		shift 1
		;;
	--ood-app-id)
		OOD_APP_ID="$2"
		shift 2
		;;
	--ood-managed-identity-id)
		OOD_MANAGED_IDENTITY_ID="$2"
		shift 2
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
	--specify-az)
		SPECIFY_AZ="true"
		shift 1
		;;
	--no-az)
		echo "[WARN] --no-az deprecated; use --specify-az for prompting zones (invert semantics)." >&2
		SPECIFY_AZ="true"
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
	local raw
	if ! raw="$(az vm list-skus --location "${LOCATION}" --resource-type virtualMachines -o json 2>/dev/null)"; then
		echo "[ERROR] az vm list-skus failed; zone discovery cannot proceed." >&2
		COMPUTE_SKUS_CACHE=""
		return 1
	fi
	# Build mapping SKU:space_separated_zones (empty after colon if none)
	COMPUTE_SKUS_CACHE="$(echo "$raw" | jq -r '
		.[]
		| select(.locationInfo!=null)
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
	echo "[DEBUG] fetch_region_zones: attempting zone lookup for SKU='${sku}' in region='${LOCATION}'." >&2
	# Ensure cache loaded
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		echo "[DEBUG] COMPUTE_SKUS_CACHE empty prior to load; invoking load_compute_skus." >&2
		load_compute_skus
	fi
	if [[ -z "$COMPUTE_SKUS_CACHE" ]]; then
		echo "[DEBUG] COMPUTE_SKUS_CACHE still empty after load attempt; returning no zones." >&2
		return 1
	fi
	local line zones
	# Exact match on SKU name followed by colon
	line="$(echo "$COMPUTE_SKUS_CACHE" | grep -E "^${sku}:" || true)"
	if [[ -z "$line" ]]; then
		echo "[DEBUG] SKU '${sku}' not found in cached list (cache lines: $(echo "$COMPUTE_SKUS_CACHE" | wc -l | tr -d ' '))." >&2
		exit 1
	fi
	zones="${line#*:}"
	if [[ -z "$zones" ]]; then
		echo "[DEBUG] SKU '${sku}' found but zones list empty (non‑zonal SKU or discovery limitation)." >&2
		exit 1
	fi
	echo "[DEBUG] SKU '${sku}' zones resolved: ${zones}" >&2
	echo "$zones"
}

# Determine if the current region appears to have any availability zone capable VM SKUs.
# Returns 0 (success) if at least one SKU lists one or more zones; 1 otherwise.
# Usage: if region_has_zone_support; then echo "Region supports AZ"; else echo "No AZ support"; fi
region_has_zone_support() {
	# Ensure cache is loaded (will handle missing az/jq gracefully).
	load_compute_skus
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

load_compute_skus

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

if [[ "$SPECIFY_AZ" == "true" ]]; then
	if region_has_zone_support; then
		POTENTIAL_HTC_AZ="$(fetch_region_zones "$HTC_SKU")"
		POTENTIAL_HPC_AZ="$(fetch_region_zones "$HPC_SKU")"
		POTENTIAL_GPU_AZ="$(fetch_region_zones "$GPU_SKU")"

		if [[ -n "$POTENTIAL_HTC_AZ" ]]; then echo "[INFO] HTC array $HTC_SKU available zones: $POTENTIAL_HTC_AZ" >&2; else echo "[INFO] $HTC_SKU has no zonal availability in region $LOCATION" >&2; fi
		if [[ -n "$POTENTIAL_HPC_AZ" ]]; then echo "[INFO] HPC array $HPC_SKU available zones: $POTENTIAL_HPC_AZ" >&2; else echo "[INFO] $HPC_SKU has no zonal availability in region $LOCATION" >&2; fi
		if [[ -n "$POTENTIAL_GPU_AZ" ]]; then echo "[INFO] GPU array $GPU_SKU available zones: $POTENTIAL_GPU_AZ" >&2; else echo "[INFO] $GPU_SKU has no zonal availability in region $LOCATION" >&2; fi

		# Only prompt for partitions where a zone wasn't provided on CLI
		HTC_AZ="$(prompt_zone HTC "${HTC_SKU}" "${HTC_AZ:-}" "${POTENTIAL_HTC_AZ}")"
		HPC_AZ="$(prompt_zone HPC "${HPC_SKU}" "${HPC_AZ:-}" "${POTENTIAL_HPC_AZ}")"
		GPU_AZ="$(prompt_zone GPU "${GPU_SKU}" "${GPU_AZ:-}" "${POTENTIAL_GPU_AZ}")"

		ANF_AZ="$(prompt_zone_manual ANF "${ANF_AZ:-}")"
		AMLFS_AZ="$(prompt_zone_manual AMLFS "${AMLFS_AZ:-}")"
	else
		echo "[INFO] Region $LOCATION appears to have no zone-capable VM SKUs (or discovery unavailable); skipping AZ prompts." >&2
		HTC_AZ=""
		HPC_AZ=""
		GPU_AZ=""
		ANF_AZ=""
		AMLFS_AZ=""
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

# Default AMLFS zone to 1 if none provided
if [[ -z "${AMLFS_AZ}" ]]; then
	echo "[INFO] AMLFS zone not specified; defaulting to '1'." >&2
	if region_has_zone_support; then
		AMLFS_AZ="1"
	else
		echo "[INFO] Region $LOCATION appears to have no zone-capable VM SKUs (or discovery unavailable); skipping AMLFS AZ default." >&2
		AMLFS_AZ=""
	fi
fi

# Prepare JSON fragments for optional availability zone (renamed to availabilityZone)
if [[ -n "${HTC_AZ}" ]]; then HTC_ZONES_JSON="\"availabilityZone\": [\"${HTC_AZ}\"],"; else HTC_ZONES_JSON="\"availabilityZone\": [],"; fi
if [[ -n "${HPC_AZ}" ]]; then HPC_ZONES_JSON="\"availabilityZone\": [\"${HPC_AZ}\"],"; else HPC_ZONES_JSON="\"availabilityZone\": [],"; fi
if [[ -n "${GPU_AZ}" ]]; then GPU_ZONES_JSON="\"availabilityZone\": [\"${GPU_AZ}\"],"; else GPU_ZONES_JSON="\"availabilityZone\": [],"; fi
if [[ -n "${ANF_AZ}" ]]; then ANF_ZONES_JSON="\"availabilityZone\": [\"${ANF_AZ}\"],"; else ANF_ZONES_JSON="\"availabilityZone\": [],"; fi
if [[ -n "${AMLFS_AZ}" ]]; then AMLFS_ZONES_JSON="\"availabilityZone\": [\"${AMLFS_AZ}\"],"; else AMLFS_ZONES_JSON="\"availabilityZone\": [],"; fi

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

# Validate AMLFS inputs
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

# Validate Open OnDemand requirements
if [[ "$OOD_ENABLED" == "true" ]]; then
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
	if [[ "$OOD_AUTO_REGISTER" == "true" ]]; then
		if [[ -n "$OOD_APP_ID" || -n "$OOD_MANAGED_IDENTITY_ID" ]]; then
			echo "[WARN] --ood-app-id / --ood-managed-identity-id provided but --ood-auto-register set; IDs will be ignored and a new Entra ID app will be registered." >&2
		fi
	else
		if [[ -z "$OOD_APP_ID" || -z "$OOD_MANAGED_IDENTITY_ID" ]]; then
			echo "[ERROR] Manual registration mode requires --ood-app-id and --ood-managed-identity-id (omit --ood-auto-register)." >&2
			exit 1
		fi
	fi
else
	if [[ -n "$OOD_FQDN" ]]; then
		echo "[WARN] --ood-fqdn provided but Open OnDemand not enabled; value will be ignored." >&2
	fi
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
git fetch --all --tags
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
	if [[ "$OOD_AUTO_REGISTER" == "true" ]]; then
		OOD_JSON='"ood": { "value": { "type": "enabled", "startCluster": true, "sku": "'"${OOD_SKU}"'", "osImage": "cycle.image.ubuntu22", "userDomain": "'"${OOD_USER_DOMAIN}"'", "fqdn": "'"${OOD_FQDN}"'", "registerEntraIDApp": true, "appId": "", "appManagedIdentityId": "" } },'
	else
		OOD_JSON='"ood": { "value": { "type": "enabled", "startCluster": true, "sku": "'"${OOD_SKU}"'", "osImage": "cycle.image.ubuntu22", "userDomain": "'"${OOD_USER_DOMAIN}"'", "fqdn": "'"${OOD_FQDN}"'", "registerEntraIDApp": false, "appId": "'"${OOD_APP_ID}"'", "appManagedIdentityId": "'"${OOD_MANAGED_IDENTITY_ID}"'" } },'
	fi
else
	OOD_JSON='"ood": { "value": { "type": "disabled" } },'
fi

cat >"$OUTPUT_FILE" <<EOF
{
	"\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
	"contentVersion": "1.0.0.0",
	"parameters": {
		"location": { "value": "${LOCATION}" },
		"adminUsername": { "value": "${ADMIN_USERNAME}" },
		"adminSshPublicKey": { "value": "${SSH_PUBLIC_KEY}" },
		"ccVMName": { "value": "ccw-cyclecloud-vm" },
		"ccVMSize": { "value": "${SCHEDULER_SKU}" },
		"resourceGroup": { "value": "${RESOURCE_GROUP}" },
		"sharedFilesystem": { "value": { "type": "anf-new", "anfServiceTier": "${ANF_SKU}", "anfCapacityInTiB": ${ANF_SIZE}, ${ANF_ZONES_JSON%%,} } },
		"additionalFilesystem": { "value": { "type": "aml-new", "lustreTier": "${AMLFS_SKU}", "lustreCapacityInTib": ${AMLFS_SIZE}, "mountPath": "/data", ${AMLFS_ZONES_JSON%%,} } },
		"network": { "value": { "type": "new", "addressSpace": "${NETWORK_ADDRESS_SPACE}", "bastion": ${NETWORK_BASTION}, "createNatGateway": true } },
		"storagePrivateDnsZone": { "value": { "type": "new" } },
		${DB_JSON_DATABASE_CONFIG}
		"acceptMarketplaceTerms": { "value": ${ACCEPT_MARKETPLACE} },
		"slurmSettings": { "value": { "startCluster": true, "version": "24.05.4-2", "healthCheckEnabled": false } },
		"schedulerNode": { "value": { "sku": "${SCHEDULER_SKU}", "osImage": "cycle.image.ubuntu22" } },
		"loginNodes": { "value": { "sku": "${LOGIN_SKU}", "osImage": "cycle.image.ubuntu22", "initialNodes": 1, "maxNodes": 1 } },
		"htc": { "value": { "sku": "${HTC_SKU}", "maxNodes": ${HTC_MAX_NODES}, "osImage": "cycle.image.ubuntu22", "useSpot": ${HTC_USE_SPOT}, ${HTC_ZONES_JSON%%,} } },
		"hpc": { "value": { "sku": "${HPC_SKU}", "maxNodes": ${HPC_MAX_NODES}, "osImage": "cycle.image.ubuntu22", ${HPC_ZONES_JSON%%,} } },
		"gpu": { "value": { "sku": "${GPU_SKU}", "maxNodes": ${GPU_MAX_NODES}, "osImage": "cycle.image.ubuntu22", ${GPU_ZONES_JSON%%,} } },
		${OOD_JSON}
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
echo "HTC SKU / AZ / Max:     ${HTC_SKU} / ${HTC_AZ:-<none>} / ${HTC_MAX_NODES}"
echo "HTC Use Spot:           ${HTC_USE_SPOT}"
echo "Open OnDemand Enabled:  ${OOD_ENABLED}"
echo "Open OnDemand SKU:      ${OOD_SKU}"
echo "Open OnDemand Domain:   ${OOD_USER_DOMAIN:-<none>}"
echo "Open OnDemand FQDN:     ${OOD_FQDN:-<none>}"
echo "OOD Auto Register:      ${OOD_AUTO_REGISTER}"
echo "OOD App ID:             ${OOD_APP_ID:-<none>}"
echo "OOD Managed Identity:   ${OOD_MANAGED_IDENTITY_ID:-<none>}"
echo "HPC SKU / AZ / Max:     ${HPC_SKU} / ${HPC_AZ:-<none>} / ${HPC_MAX_NODES}"
echo "GPU SKU / AZ / Max:     ${GPU_SKU} / ${GPU_AZ:-<none>} / ${GPU_MAX_NODES}"
echo "ANF Tier / Size / AZ:   ${ANF_SKU} / ${ANF_SIZE} / ${ANF_AZ:-<none>}"
echo "AMLFS Tier / Size / AZ: ${AMLFS_SKU} / ${AMLFS_SIZE} / ${AMLFS_AZ:-<none>}"
echo "Accept Marketplace:     ${ACCEPT_MARKETPLACE}"
echo "Network Address Space:  ${NETWORK_ADDRESS_SPACE}"
echo "Bastion Enabled:        ${NETWORK_BASTION}"
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
