#!/bin/bash

# set duration in seconds
DURATION=900
CURRENT_DATE=$(date +"%Y-%m-%d.%Hh%Mm%Ss")
LOGDIR=$(pwd)

echo "Duration: $DURATION"
echo "Current date: $CURRENT_DATE"
echo "Log directory: $LOGDIR"

target=1004

# Create the log file name using the hostname and current date
LOGFILE="thermal_results.$(hostname).${target}.${DURATION}.${CURRENT_DATE}.csv"
LOGPATH="${LOGDIR}/${LOGFILE}"

# Runs the stress/diagnostic test on all GPUs (as background process)
dcgmproftester12 --no-dcgm-validation --max-processes 0 -t $target -d $DURATION &

# Capture the process ID (PID) of the last command (workload)
WORKLOAD_PID=$!

# Collect data from multiple GPU sensors using the nvidia-smi tool (needed for tlimit) every 1 second (--loop=1)
export RUN_INFO="$(hostname),$target,$DURATION"
echo `date` starting ${RUN_INFO}
nvidia-smi --query-gpu=serial,name,timestamp,index,temperature.gpu,temperature.memory,temperature.gpu.tlimit,power.draw,clocks.current.sm,clocks_throttle_reasons.active,utilization.gpu  --loop=1 --format=csv --filename=$LOGPATH &

# Capture the process ID (PID) of the last command (telemetry)
TELEMETRY_PID=$!

tail --pid=$WORKLOAD_PID -f /dev/null
echo `date` Done workload ${WORKLOAD_PID}
kill -s INT $TELEMETRY_PID
sleep 1
awk '{print ENVIRON["RUN_INFO"]","$0}' $LOGPATH >  ${LOGPATH}.tmp
mv ${LOGPATH}.tmp $LOGPATH
