#!/usr/bin/env bash

set -euo pipefail

# Line removed as the variable 'aznhc_root' is unused.

vm_hostname=$(hostname)
vm_id=$(curl -H Metadata:true --max-time 10 -s -f "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-03-01&format=text") || { echo "Error: Failed to fetch vmId from metadata service"; exit 1; }
vm_name=$(curl -H Metadata:true --max-time 10 -s -f "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-11-15&format=text") || { echo "Error: Failed to fetch vmName from metadata service"; exit 1; }
kernel_version=$(uname -r)
sku=$(curl -H Metadata:true --max-time 10 -s -f "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | tr '[:upper:]' '[:lower:]' | sed 's/standard_//') || { echo "Error: Failed to fetch vmSize from metadata service"; exit 1; }
if [ -f /var/lib/hyperv/.kvp_pool_3 ]; then
    physical_id=$(tr -d '\0' < /var/lib/hyperv/.kvp_pool_3 | sed -e 's/.*Qualified\(.*\)VirtualMachineDynamic.*/\1/')
else
    physical_id="Not available"
fi

cat <<EOF
HOSTNAME: $vm_hostname
VMNAME: $vm_name
VMID: $vm_id
PHYSICALID: $physical_id
KERNEL: $kernel_version
SKU: $sku
EOF

if [ -f "${AZ_NHC_ROOT}/aznhc.conf" ]; then
    conf_file="${AZ_NHC_ROOT}/aznhc.conf"
else
    conf_file="${AZ_NHC_ROOT}/conf/${sku}.conf"
fi

if [ ! -f "$conf_file" ]; then
    echo "The vm SKU 'standard_$sku' is currently not supported by Azure health checks."
    exit 1
fi

nhc -t 600 -c $conf_file
