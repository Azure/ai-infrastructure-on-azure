#!/bin/bash
# Common functions and config loading for all scripts
# Source this at the top of each script: source ./scripts/common.sh

set -euo pipefail

# Fix Git Bash path conversion issue on Windows
export MSYS_NO_PATHCONV=1

# Load config with Windows/Linux line ending compatibility
load_config() {
    local config_file="${1:-./config.sh}"
    if [[ ! -f "$config_file" ]]; then
        echo "Error: $config_file not found. Copy config.sh.template to config.sh"
        exit 1
    fi
    
    if command -v dos2unix &>/dev/null; then
        source <(dos2unix < "$config_file" 2>/dev/null)
    else
        source <(sed 's/\r$//' "$config_file")
    fi
}

# Build resource names from suffix
build_resource_names() {
    # Generate suffix if not set
    if [[ -z "${UNIQUE_SUFFIX:-}" ]]; then
        if command -v openssl &>/dev/null; then
            UNIQUE_SUFFIX=$(openssl rand -hex 3)
        elif [[ -f /dev/urandom ]]; then
            UNIQUE_SUFFIX=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c 6)
        else
            UNIQUE_SUFFIX=$(date +%s | tail -c 7)
        fi
        echo "⚠ No UNIQUE_SUFFIX set - generated: $UNIQUE_SUFFIX"
    fi

    # Build names from PROJECT_NAME if not explicitly set
    RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-${PROJECT_NAME}-rg}"
    AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-${PROJECT_NAME}-aks}"
    TAGS="${TAGS:-project=${PROJECT_NAME} environment=dev purpose=ml-training}"

    # Build storage/ACR names with suffix
    STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-aksgpustorage${UNIQUE_SUFFIX}}"
    ACR_NAME="${ACR_NAME:-aksgpuacr${UNIQUE_SUFFIX}}"

    # Validate storage account name (lowercase, alphanumeric, max 24 chars)
    STORAGE_ACCOUNT_NAME=$(echo "$STORAGE_ACCOUNT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | cut -c1-24)

    export UNIQUE_SUFFIX STORAGE_ACCOUNT_NAME ACR_NAME RESOURCE_GROUP_NAME AKS_CLUSTER_NAME TAGS
}

# Check prerequisites
check_prereqs() {
    local tools=("$@")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "Error: $tool not installed"
            case "$tool" in
                az) echo "  Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" ;;
                kubectl) echo "  Install: az aks install-cli" ;;
                helm) echo "  Install: https://helm.sh/docs/intro/install/" ;;
            esac
            exit 1
        fi
    done
}

# Check Azure login
check_azure_login() {
    if ! az account show &>/dev/null; then
        echo "Error: Not logged in to Azure. Run 'az login'"
        exit 1
    fi
    [[ -n "${SUBSCRIPTION_ID:-}" ]] && az account set --subscription "$SUBSCRIPTION_ID"
}

# Initialize - call this from each script
init() {
    load_config
    build_resource_names
}