#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def log(message):
    """Simple logging function"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)


def run_command(command):
    """Run a shell command"""
    log(f"Running command: {command}")
    result = os.system(command)
    if result != 0:
        raise RuntimeError(f"Command failed with exit code {result}: {command}")


class TorsetTool:

    def __init__(self, output_dir: Path, guids_json: str, sharp_cmd_path: Path):
        self.output_dir = output_dir
        self.guids_json = guids_json
        self.sharp_cmd_path = sharp_cmd_path
        self.guids_file = f"{output_dir}/guids.txt"
        self.topo_file = f"{output_dir}/topology.txt"
        self.guid_to_host_map = {}
        self.device_guids_per_switch = []
        self.host_to_torset_map = {}
        self.torsets = {}

    def retrieve_guids_from_json(self):
        """Read GUIDs from JSON input (from k8s annotations)"""
        data = json.loads(self.guids_json)
        for item in data:
            node_name = item["name"]
            guids_str = item["guids"]
            guids = guids_str.split(",")
            for guid in guids:
                guid = guid.strip()
                if guid:
                    self.guid_to_host_map[guid] = node_name
        log(f"Collected {len(self.guid_to_host_map)} GUIDs from {len(data)} nodes")

    def write_guids_to_file(self):
        with open(self.guids_file, "w") as f:
            for guid in self.guid_to_host_map.keys():
                f.write(f"{guid}\n")
        log(f"GUIDs written to {self.guids_file}")

    def generate_topo_file(self):
        """Generate topology using sharp_cmd (requires IB device)"""
        create_topo_cmd = (
            f"SHARP_SMX_UCX_INTERFACE=mlx5_0:1 {self.sharp_cmd_path}/sharp/bin/sharp_cmd "
            f"topology --ib-dev mlx5_0:1 "
            f"--guids_file {self.guids_file} "
            f"--topology_file {self.topo_file}"
        )
        run_command(create_topo_cmd)
        log(f"Topology file generated at {self.topo_file}")

    def group_guids_per_switch(self):
        """Parse topology file and group GUIDs per switch"""
        if not Path(self.topo_file).exists():
            raise FileNotFoundError(f"Topology file {self.topo_file} not found")
        guids_per_switch = []
        with open(self.topo_file, "r") as f:
            for line in f:
                if "Nodes=" not in line:
                    continue
                guids_per_switch.append(line.strip().split(" ")[1].split("=")[1])
        self.device_guids_per_switch = guids_per_switch
        log(f"Grouped {len(guids_per_switch)} switches from topology file")

    def identify_torsets(self):
        host_to_torset_map = {}
        for device_guids_one_switch in self.device_guids_per_switch:
            device_guids = device_guids_one_switch.strip().split(",")
            torset_index = len(set(host_to_torset_map.values()))
            for guid in device_guids:
                host = self.guid_to_host_map.get(guid)
                if not host or host in host_to_torset_map:
                    continue
                host_to_torset_map[host] = f"torset-{torset_index:02}"
        self.host_to_torset_map = host_to_torset_map
        log(f"Identified {len(host_to_torset_map)} hosts mapped to torsets")

    def group_hosts_by_torset(self):
        torsets = {}
        for host, torset in self.host_to_torset_map.items():
            torsets.setdefault(torset, []).append(host)
        self.torsets = torsets
        log(f"Grouped hosts into {len(torsets)} torsets")

    def write_hosts_by_torset(self):
        for torset, hosts in self.torsets.items():
            output_file = f"{self.output_dir}/{torset}_hosts.txt"
            with open(output_file, "w") as f:
                for host in hosts:
                    f.write(f"{host}\n")
        log(f"Wrote hosts by torset to {self.output_dir}")

    def write_torset_mapping(self):
        """Write node-to-torset mapping as JSON for kubectl to consume"""
        mapping_file = f"{self.output_dir}/torset_mapping.json"
        with open(mapping_file, "w") as f:
            json.dump(self.host_to_torset_map, f, indent=2)
        log(f"Wrote torset mapping to {mapping_file}")


def main():
    if len(sys.argv) != 4:
        print("Usage: torset_tool.py <guids_json> <sharp_cmd_path> <output_dir>")
        sys.exit(1)

    guids_json = sys.argv[1]
    sharp_cmd_path = sys.argv[2]
    output_dir = sys.argv[3]

    Path(output_dir).mkdir(exist_ok=True, parents=True)

    log("Starting torset discovery")
    torset_tool = TorsetTool(Path(output_dir), guids_json, Path(sharp_cmd_path))

    log("Retrieving GUIDs from JSON")
    torset_tool.retrieve_guids_from_json()
    torset_tool.write_guids_to_file()
    log("Generating topology using sharp_cmd")
    torset_tool.generate_topo_file()
    torset_tool.group_guids_per_switch()
    torset_tool.identify_torsets()
    torset_tool.group_hosts_by_torset()
    torset_tool.write_hosts_by_torset()
    torset_tool.write_torset_mapping()
    log("Torset discovery completed successfully")


if __name__ == "__main__":
    main()
