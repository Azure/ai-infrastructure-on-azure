#!/bin/bash

OUTPUT_FILE=failed_nodes.txt
MODE=$1  # Get input parameter (reboot, drain, or none)

# Collect failed nodes from ccw-gpu-*.log (only hostnames, no full paths)
grep -E "ERROR|Error" ccw-gpu-*.log | cut -d':' -f1 | sed 's/\.log//' | sort -u > "$OUTPUT_FILE"

# Print failed nodes list before any actions
echo -e "\n### The following nodes failed health checks: ###"
cat "$OUTPUT_FILE"

# If no parameters, just generate the file and continue
if [[ -z $MODE ]]; then
    echo "Failed nodes list generated: $OUTPUT_FILE"
else
    # Read the failed nodes and take action
    if [[ -s $OUTPUT_FILE ]]; then
        if [[ $MODE == "reboot" ]]; then
            echo -e "\n### Rebooting failed nodes... ###"
            parallel-ssh -h "$OUTPUT_FILE" -l hpcadmin -i "sudo reboot"
            echo "Reboot command issued."
        
        elif [[ $MODE == "drain" ]]; then
            echo -e "\n### Draining failed nodes in SLURM... ###"
            while read -r node; do
                echo "Draining $node..."
                sudo scontrol update NodeName="$node" State=DRAIN Reason="Health check failed"
            done < "$OUTPUT_FILE"
            echo "All failed nodes drained."
        
        else
            echo -e "\nInvalid parameter: $MODE"
            echo "Usage: $0 [reboot|drain]"
            exit 1
        fi
    else
        echo -e "\nAll nodes passed the health check."
    fi
fi

# Ensure firmware versions print even when no mode is set
echo -e "\n### Infiniband Firmware Versions Across All Nodes ###"
FIRMWARE_OUTPUT=$(grep -h -A 8 "### Infiniband Firmware Version ###" ccw-gpu-*.log | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort | uniq -c)

if [[ -n "$FIRMWARE_OUTPUT" ]]; then
    echo "$FIRMWARE_OUTPUT"
else
    echo "No Infiniband firmware versions found in logs."
fi
