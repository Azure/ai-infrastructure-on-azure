#!/usr/bin/env bash
set -euo pipefail

###############################################
# CycleCloud Slurm Workspace Deployment Helper
# Generates an output.json parameters file for Bicep deployment
# Clones azure/cyclecloud-slurm-workspace at a ref
# Applies availability zone substitutions and optional security rules
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_FILE="${SCRIPT_DIR}/output.json"
WORKSPACE_REPO_URL="https://github.com/azure/cyclecloud-slurm-workspace.git"

usage() {
	cat <<EOF
Usage: $0 \
	--subscription-id <subId> \
	--resource-group <rg> \
	--location <region> \
	--ssh-public-key-file <path> \
	--admin-password <password> \
	[--admin-username <name>] \
	--htc-sku <vmSku> [--htc-az <az>] \
	--hpc-sku <vmSku> [--hpc-az <az>] \
	--gpu-sku <vmSku> [--gpu-az <az>] \
	[--scheduler-sku <vmSku>] [--login-sku <vmSku>] \
	[--workspace-ref <commit|tag|branch>] \
	[--workspace-commit <commit-sha>] \
	[--workspace-dir <path>] \
	[--output-file <path>] \
	[--anf-sku <Standard|Premium|Ultra>] \
	[--anf-size <TiB>] \
	[--anf-az <az>] \
	[--amlfs-sku AMLFS-Durable-Premium-40|AMLFS-Durable-Premium-125|AMLFS-Durable-Premium-250|AMLFS-Durable-Premium-500] \
	[--amlfs-size <TiB>] \
	[--amlfs-az <az>] \
	[--specify-az] \
	[--accept-marketplace] \
	[--help]

Required:
	--subscription-id              Azure subscription ID
	--resource-group               Target resource group name
	--location                     Azure region (used for all resources)
	--ssh-public-key-file          Path to SSH public key file (OpenSSH format)
	--admin-password               Admin password (for CycleCloud workspace UI / cluster DB)
	--htc-sku                      HTC partition VM SKU (availability zone optional via --htc-az)
	--hpc-sku                      HPC partition VM SKU (availability zone optional via --hpc-az)
	--gpu-sku                      GPU partition VM SKU (availability zone optional via --gpu-az)

Optional:
	--admin-username               Admin username (default: hpcadmin)
	--scheduler-sku                Scheduler node VM SKU (default: Standard_D4as_v5)
	--login-sku                    Login node VM SKU (default: Standard_F4s_v2)
	--workspace-ref                Git ref (commit SHA / tag / branch) to checkout (default: main)
	--workspace-commit             Specific commit SHA to checkout (detached HEAD). Overrides --workspace-ref if provided.
	--workspace-dir                Directory to clone workspace into (default: ./cyclecloud-slurm-workspace under script dir)
	--output-file                  Where to write output.json (default: ${DEFAULT_OUTPUT_FILE})
	--accept-marketplace           Include acceptMarketplaceTerms=true in output.json
	--anf-sku                      Azure NetApp Files service tier for shared filesystem (default: Premium)
	--anf-size                     Azure NetApp Files capacity in TiB for shared filesystem (integer, default: 2)
	--anf-az                       Availability zone for ANF shared filesystem (optional; interactive if omitted)
	--amlfs-sku                    Azure Managed Lustre tier (AMLFS-Durable-Premium-40|AMLFS-Durable-Premium-125|AMLFS-Durable-Premium-250|AMLFS-Durable-Premium-500). Default: 500
	--amlfs-size                   Azure Managed Lustre capacity in TiB (integer, default: 4)
	--amlfs-az                     Availability zone for AMLFS additional filesystem (optional; interactive if omitted)
	--specify-az                   Enable availability zone prompting logic (default behavior). Omit to skip all prompts and emit empty availabilityZone arrays.
	--storage-sku                  Storage account SKU (default Standard_LRS)
	--deploy                       After generating output.json, run az deployment group create
	--help                         Show this usage text

Examples:
	$0 --subscription-id SUB --resource-group rg-ccw --location eastus \
		 --ssh-public-key-file ~/.ssh/id_rsa.pub --admin-password YOUR_SUPER_SECRET_PASSWORD \
		 --htc-sku Standard_F2s_v2 --htc-az 1 --hpc-sku Standard_HB176rs_v4 --hpc-az 2 \
		 --gpu-sku Standard_ND96amsr_A100_v4 --gpu-az 3 --specify-az

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
EOF
}

# Default values
ADMIN_USERNAME="hpcadmin"
SCHEDULER_SKU="Standard_D4as_v5"
LOGIN_SKU="Standard_D2as_v5"
WORKSPACE_REF="${WORKSPACE_REF:-main}" # allow pre-set env var to override default
WORKSPACE_COMMIT="4054aa6902effe0f16ce94b384d85bb4c1daeed5"
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

# Parse args
while [[ $# -gt 0 ]]; do
	case "$1" in
		--subscription-id) SUBSCRIPTION_ID="$2"; shift 2;;
		--resource-group) RESOURCE_GROUP="$2"; shift 2;;
		--location) LOCATION="$2"; shift 2;;
		--ssh-public-key-file) SSH_KEY_FILE="$2"; shift 2;;
		--admin-password) ADMIN_PASSWORD="$2"; shift 2;;
		--admin-username) ADMIN_USERNAME="$2"; shift 2;;
		--htc-sku) HTC_SKU="$2"; shift 2;;
		--htc-az) HTC_AZ="$2"; shift 2;;
		--hpc-sku) HPC_SKU="$2"; shift 2;;
		--hpc-az) HPC_AZ="$2"; shift 2;;
		--gpu-sku) GPU_SKU="$2"; shift 2;;
		--gpu-az) GPU_AZ="$2"; shift 2;;
		--scheduler-sku) SCHEDULER_SKU="$2"; shift 2;;
		--login-sku) LOGIN_SKU="$2"; shift 2;;
		--workspace-ref) WORKSPACE_REF="$2"; shift 2;;
		--workspace-commit) WORKSPACE_COMMIT="$2"; shift 2;;
		--workspace-dir) WORKSPACE_DIR="$2"; shift 2;;
		--output-file) OUTPUT_FILE="$2"; shift 2;;
		--anf-sku) ANF_SKU="$2"; shift 2;;
		--anf-size) ANF_SIZE="$2"; shift 2;;
		--anf-az) ANF_AZ="$2"; shift 2;;
		--amlfs-sku) AMLFS_SKU="$2"; shift 2;;
		--amlfs-size) AMLFS_SIZE="$2"; shift 2;;
		--amlfs-az) AMLFS_AZ="$2"; shift 2;;
		--db-name) DB_NAME="$2"; shift 2;;
		--db-user) DB_USERNAME="$2"; shift 2;;
		--db-password) DB_PASSWORD="$2"; shift 2;;
		--db-id) DB_ID="$2"; shift 2;;
		--specify-az) SPECIFY_AZ="true"; shift 1;;
		--no-az) echo "[WARN] --no-az deprecated; use --specify-az for prompting zones (invert semantics)." >&2; SPECIFY_AZ="true"; shift 1;;
		--accept-marketplace) ACCEPT_MARKETPLACE="true"; shift 1;;
		--deploy) DO_DEPLOY="true"; shift 1;;
		--help|-h) usage; exit 0;;
		*) echo "Unknown argument: $1" >&2; usage; exit 1;;
	esac
done

required=(SUBSCRIPTION_ID RESOURCE_GROUP LOCATION SSH_KEY_FILE ADMIN_PASSWORD HTC_SKU HPC_SKU GPU_SKU)
missing=()
for var in "${required[@]}"; do
	if [[ -z "${!var:-}" ]]; then missing+=("$var"); fi
done
if (( ${#missing[@]} )); then
	echo "Missing required arguments: ${missing[*]}" >&2
	usage; exit 1
fi

if [[ ! -f "$SSH_KEY_FILE" ]]; then echo "SSH key file not found: $SSH_KEY_FILE" >&2; exit 1; fi
SSH_PUBLIC_KEY="$(tr -d '\n' < "$SSH_KEY_FILE")"

# Determine if database config should be enabled (all required DB vars present)
if [[ -n "$DB_NAME" || -n "$DB_USERNAME" || -n "$DB_PASSWORD" || -n "$DB_ID" ]]; then
	# Enforce all-or-nothing
	if [[ -z "$DB_NAME" || -z "$DB_USERNAME" || -z "$DB_PASSWORD" || -z "$DB_ID" ]]; then
		echo "[ERROR] Database parameters require --db-name, --db-user, --db-password, and --db-id all set." >&2
		exit 1
	fi
	DB_ENABLED="true"
	echo "[INFO] Database configuration enabled (privateEndpoint)." >&2
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
	if [[ -n "$current" ]]; then echo "[INFO] $label array $sku availability zone set through commandline to: $current" >&2; echo "$current"; return 0; fi
	
	read -r -p "Select availability zone (e.g. 1) for $label SKU '$sku' or press Enter for none: " sel
	if [[ -n "$sel" ]]; then
		if [[ -n "$zones" ]]; then
			if echo "$zones" | tr '\t' ' ' | tr ' ' '\n' | grep -Fx "$sel" >/dev/null 2>&1; then
				echo "$sel"; return 0
			else
				echo "[WARN] '$sel' is not in discovered zones list; proceeding anyway." >&2
				echo "$sel"; return 0
			fi
		else
			echo "$sel"; return 0
		fi
	else
		echo ""; return 0
	fi
}

# Manual zone prompt for storage (ANF / AMLFS) without auto-discovery
prompt_zone_manual() {
	local label="$1" current="$2"
	if [[ -n "$current" ]]; then echo "[INFO] $label availability zone preset: $current" >&2; echo "$current"; return 0; fi
	echo "[INFO] ${label}: availability zone not auto-discovered. Typical zonal regions use 1,2,3. Leave blank for none." >&2
	read -r -p "Enter availability zone for ${label} (blank for none): " sel
	if [[ -n "$sel" ]]; then echo "$sel"; else echo ""; fi
}

load_compute_skus

if [[ "$SPECIFY_AZ" == "true" ]]; then
	if region_has_zone_support; then
		POTENTIAL_HTC_AZ="$(fetch_region_zones "$HTC_SKU")"
		POTENTIAL_HPC_AZ="$(fetch_region_zones "$HPC_SKU")"
		POTENTIAL_GPU_AZ="$(fetch_region_zones "$GPU_SKU")"

		if [[ -n "$POTENTIAL_HTC_AZ" ]]; then echo "[INFO] HTC array $HTC_SKU available zones: $POTENTIAL_HTC_AZ" >&2; else echo "[INFO] $HTC_SKU has no zonal availability in region $LOCATION" >&2; fi
        if [[ -n "$POTENTIAL_HPC_AZ" ]]; then echo "[INFO] HPC array $HPC_SKU available zones: $POTENTIAL_HPC_AZ" >&2; else echo "[INFO] $HPC_SKU has no zonal availability in region $LOCATION" >&2; fi
		if [[ -n "$POTENTIAL_GPU_AZ" ]]; then echo "[INFO] GPU array $GPU_SKU available zones: $POTENTIAL_GPU_AZ" >&2; else echo "[INFO] $GPU_SKU has no zonal availability in region $LOCATION" >&2; fi
		
        HTC_AZ="$(prompt_zone HTC "${HTC_SKU}" "${HTC_AZ:-}" "${POTENTIAL_HTC_AZ}")"
		HPC_AZ="$(prompt_zone HPC "${HPC_SKU}" "${HPC_AZ:-}" "${POTENTIAL_HPC_AZ}")"
		GPU_AZ="$(prompt_zone GPU "${GPU_SKU}" "${GPU_AZ:-}" "${POTENTIAL_GPU_AZ}")"

		ANF_AZ="$(prompt_zone_manual ANF "${ANF_AZ:-}")"
		AMLFS_AZ="$(prompt_zone_manual AMLFS "${AMLFS_AZ:-}")"
	else
		echo "[INFO] Region $LOCATION appears to have no zone-capable VM SKUs (or discovery unavailable); skipping AZ prompts." >&2
		HTC_AZ=""; HPC_AZ=""; GPU_AZ=""; ANF_AZ=""; AMLFS_AZ=""
	fi
else
	echo "[INFO] No --specify-az flag: while AZ are specified in CLI arguments. Add --specify-az flag to use AZs." >&2
	exit 1
fi

# Default AMLFS zone to 1 if none provided
if [[ -z "${AMLFS_AZ}" && "$SPECIFY_AZ" == "true" ]]; then
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
	echo "[ERROR] --anf-size must be an integer (TiB). Provided: $ANF_SIZE" >&2; exit 1
fi
if (( ANF_SIZE < 1 )); then
	echo "[ERROR] --anf-size must be >= 1 TiB. Provided: $ANF_SIZE" >&2; exit 1
fi
case "$ANF_SKU" in
	Standard|Premium|Ultra) ;; 
	*) echo "[ERROR] --anf-sku must be one of Standard|Premium|Ultra. Provided: $ANF_SKU" >&2; exit 1;;
esac

# Validate AMLFS inputs
if ! [[ "$AMLFS_SIZE" =~ ^[0-9]+$ ]]; then
	echo "[ERROR] --amlfs-size must be an integer (TiB). Provided: $AMLFS_SIZE" >&2; exit 1
fi
if (( AMLFS_SIZE < 4 )); then
	echo "[ERROR] --amlfs-size must be >= 4 TiB. Provided: $AMLFS_SIZE" >&2; exit 1
fi
case "$AMLFS_SKU" in
	AMLFS-Durable-Premium-40|AMLFS-Durable-Premium-125|AMLFS-Durable-Premium-250|AMLFS-Durable-Premium-500) ;;
	*) echo "[ERROR] --amlfs-sku must be one of AMLFS-Durable-Premium-40|AMLFS-Durable-Premium-125|AMLFS-Durable-Premium-250|AMLFS-Durable-Premium-500. Provided: $AMLFS_SKU" >&2; exit 1;;
esac

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
		git checkout "$WORKSPACE_COMMIT" || { echo "[ERROR] Failed to checkout commit $WORKSPACE_COMMIT" >&2; exit 1; }
		echo "[INFO] Checked out commit $WORKSPACE_COMMIT (detached HEAD)"
	else
		echo "[ERROR] Commit $WORKSPACE_COMMIT not found in repository" >&2; exit 1
	fi
else
	git checkout "$WORKSPACE_REF" || { echo "[ERROR] Failed to checkout ref $WORKSPACE_REF" >&2; exit 1; }
fi

echo "[INFO] Generating output.json at $OUTPUT_FILE"
if [[ "$DB_ENABLED" == "true" ]]; then
    DB_JSON_DB_ADMIN_PASSWORD='"databaseAdminPassword": { "value": "'"${DB_PASSWORD}"'" },'
    DB_JSON_DATABASE_CONFIG='"databaseConfig": { "value": { "type": "privateEndpoint", "databaseUser": "'"${DB_USERNAME}"'", "dbInfo": { "name": "'"${DB_NAME}"'", "id": "'"${DB_ID}"'", "location": "'"${LOCATION}"'", "subscriptionName": "" } } },'
else
    DB_JSON_DB_ADMIN_PASSWORD='"databaseAdminPassword": { "value": "'""'" },'
    DB_JSON_DATABASE_CONFIG='"databaseConfig": { "value": { "type": "disabled" } },'
fi

cat > "$OUTPUT_FILE" <<EOF
{
	"\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
	"contentVersion": "1.0.0.0",
	"parameters": {
		"location": { "value": "${LOCATION}" },
		"adminUsername": { "value": "${ADMIN_USERNAME}" },
		"adminPassword": { "value": "${ADMIN_PASSWORD}" },
		"adminSshPublicKey": { "value": "${SSH_PUBLIC_KEY}" },
		"ccVMName": { "value": "ccw-cyclecloud-vm" },
		"ccVMSize": { "value": "${SCHEDULER_SKU}" },
		"resourceGroup": { "value": "${RESOURCE_GROUP}" },
		"sharedFilesystem": { "value": { "type": "anf-new", "anfServiceTier": "${ANF_SKU}", "anfCapacityInTiB": ${ANF_SIZE}, ${ANF_ZONES_JSON%%,} } },
		"additionalFilesystem": { "value": { "type": "aml-new", "lustreTier": "${AMLFS_SKU}", "lustreCapacityInTib": ${AMLFS_SIZE}, "mountPath": "/data", ${AMLFS_ZONES_JSON%%,} } },
		"network": { "value": { "type": "new", "addressSpace": "10.0.0.0/24", "bastion": false, "createNatGateway": true} },
		"storagePrivateDnsZone": { "value": { "type": "new" } },
		${DB_JSON_DB_ADMIN_PASSWORD}
		${DB_JSON_DATABASE_CONFIG}
		"acceptMarketplaceTerms": { "value": ${ACCEPT_MARKETPLACE} },
		"slurmSettings": { "value": { "startCluster": true, "version": "24.05.4-2", "healthCheckEnabled": false } },
		"schedulerNode": { "value": { "sku": "${SCHEDULER_SKU}", "osImage": "cycle.image.ubuntu22" } },
		"loginNodes": { "value": { "sku": "${LOGIN_SKU}", "osImage": "cycle.image.ubuntu22", "initialNodes": 0, "maxNodes": 1 } },
		"htc": { "value": { "sku": "${HTC_SKU}", "maxNodes": 1, "osImage": "cycle.image.ubuntu22", "useSpot": true, ${HTC_ZONES_JSON%%,} } },
		"hpc": { "value": { "sku": "${HPC_SKU}", "maxNodes": 1, "osImage": "cycle.image.ubuntu22", ${HPC_ZONES_JSON%%,} } },
		"gpu": { "value": { "sku": "${GPU_SKU}", "maxNodes": 1, "osImage": "cycle.image.ubuntu22", ${GPU_ZONES_JSON%%,} } },
		"ood": { "value": { "type": "disabled" } },
		"tags": { "value": {} }
	}
}
EOF

RANDOM_NAME="$(generate_random_name)"
echo "[INFO] Generated random name: ${RANDOM_NAME}"

echo "[INFO] output.json generation complete"
echo "[INFO] Path: $OUTPUT_FILE"
echo "[INFO] To deploy manually: az deployment sub create  --name "$RANDOM_NAME" --location "$LOCATION" --template-file "$WORKSPACE_DIR/bicep/mainTemplate.bicep" --parameters @"$OUTPUT_FILE" --debug || { echo "[ERROR] Deployment failed" >&2; exit 1; }"

echo ""
echo "================ Deployment Configuration Summary ================"
echo "Subscription ID:        ${SUBSCRIPTION_ID}"
echo "Resource Group:         ${RESOURCE_GROUP}"
echo "Region:                 ${LOCATION}"
echo "Workspace Ref:          ${WORKSPACE_REF}"
echo "Workspace Commit:       ${WORKSPACE_COMMIT:-<none>}"
echo "Scheduler SKU:          ${SCHEDULER_SKU}"
echo "Login SKU:              ${LOGIN_SKU}"
echo "HTC SKU / AZ:           ${HTC_SKU} / ${HTC_AZ:-<none>}"
echo "HPC SKU / AZ:           ${HPC_SKU} / ${HPC_AZ:-<none>}"
echo "GPU SKU / AZ:           ${GPU_SKU} / ${GPU_AZ:-<none>}"
echo "ANF Tier / Size / AZ:   ${ANF_SKU} / ${ANF_SIZE} / ${ANF_AZ:-<none>}"
echo "AMLFS Tier / Size / AZ: ${AMLFS_SKU} / ${AMLFS_SIZE} / ${AMLFS_AZ:-<none>}"
echo "Accept Marketplace:     ${ACCEPT_MARKETPLACE}"
echo "Deployment Name (preview): ${RANDOM_NAME}"
echo "Output Parameters File: ${OUTPUT_FILE}"
echo "Template Path:          ${WORKSPACE_DIR}/bicep/mainTemplate.bicep"
if [[ "$DB_ENABLED" == "true" ]]; then
	echo "Database Enabled:       true (privateEndpoint)"
	echo "Database Name:          ${DB_NAME}"
	echo "Database User:          ${DB_USERNAME}"
	echo "Database Resource ID:   ${DB_ID}"
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
	az deployment sub create --name "$RANDOM_NAME" --location "$LOCATION" --template-file "$WORKSPACE_DIR/bicep/mainTemplate.bicep" --parameters @"$OUTPUT_FILE" --debug || { echo "[ERROR] Deployment failed" >&2; exit 1; }
	echo "[INFO] Deployment finished successfully"
fi


exit 0
