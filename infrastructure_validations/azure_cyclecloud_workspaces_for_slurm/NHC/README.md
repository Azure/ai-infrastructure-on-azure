# Single node NHC example
```bash
# Run NHC on a given set of nodes
sbatch -w ccw-gpu-[1-10] nhc.slurm

# Collect a list of failed nodes without draining
bash collect_failed.sh

# Reboot failed nodes (works on some failures)
bash collect_failed.sh reboot

# Set failed nodes in Drain state
bash collect_failed.sh drain
```

Suggested approach is to run NHC on all nodes, then reboot failed ones and rerun NHC on them. For nodes that cannot be fixed with soft reboot, drain and deallocate. 
