# proxmox-scripts
Proxmox scripts for VM and containers creation.

# requirements
In my case, I don't have a Proxmox entreprise subscription. So I had to switch to the free one on the host. This script is perfet for that (run the script in the host's Proxmox shell) :

```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"
```

(source : https://community-scripts.github.io/ProxmoxVE/scripts?id=post-pve-install).

After that, install libguestfs-tools on host :

```
apt update
apt install libguestfs-tools
```

## pve-debian-docker.sh
This script is a fork of "docker.sh" (https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/docker-vm.sh) by thost96 (thost96). Published here : https://community-scripts.github.io/ProxmoxVE/scripts?id=docker. 

Just added possibility to choose keyboard layout (French/Switzerland here) and creation of non-root user with username/password/ssh key.

Usage :
```bash
bash -c "$(curl -fsSL https://github.com/gabmich/proxmox-scripts/raw/refs/heads/main/pve-debian-docker.sh)"
```

## more scripts will be added if needed
