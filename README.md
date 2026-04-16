# SLURM-shell-gres-viz
Shell-based Slurm GPU allocation visualizer with colored per-user GPU maps, node state indicators, and lightweight live monitoring.

------

```bash
##How to use?

# Options:
#  -i        Show GPU indices as [0][1] instead of '*'
#  -m        Show only my jobs
#  -l SEC    Refresh every SEC seconds
#  -h        Show this help
```

```bash
## How to deploy on your master node

# Clone this repository
git clone https://github.com/jhlee-khu/SLURM-shell-gres-viz
cd SLURM-shell-gres-viz

# Copy the script to a system-wide path
sudo cp slurm-gres-viz.sh /usr/local/bin/<desired-script-name>
sudo chmod 755 /usr/local/bin/<desired-script-name>
```

