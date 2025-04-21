#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: gabmich - forked from thost96 (thost96) script
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
    ____             __                _    ____  ___
   / __ \____  _____/ /_____  _____   | |  / /  |/  /
  / / / / __ \/ ___/ //_/ _ \/ ___/   | | / / /|_/ /
 / /_/ / /_/ / /__/ ,< /  __/ /       | |/ / /  / /
/_____/\\____/\\___/_/|_|\\___/_/     |___/_/  /_/

EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
NEXTID=$(pvesh get /cluster/nextid)
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="debian12vm"
var_os="debian"
var_version="12"
DISK_SIZE="8G"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
HA=$(echo "\033[1;34m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")
BFR="\\r\\033[K"
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "INTERRUPTED"' SIGINT
trap 'post_update_to_api "failed" "TERMINATED"' SIGTERM

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  post_update_to_api "failed" "${command}"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function cleanup_vmid() {
  if qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Docker VM" --yesno "This will create a New Docker VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "⚠ User exited script \n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}..."
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

function pve_check() {
  if ! pveversion | grep -Eq "pve-manager/8\.[1-4](\.[0-9]+)*"; then
    msg_error "This version of Proxmox Virtual Environment is not supported"
    echo -e "Requires Proxmox Virtual Environment Version 8.1 or later."
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ] && [ "$(dpkg --print-architecture)" != "arm64" ]; then
    msg_error "This script will not work with your CPU Architecture"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1 && [ -n "${SSH_CLIENT:+x}" ]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" \
         --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
      echo "you've been warned"
    else
      clear
      exit
    fi
  fi
}

function exit-script() {
  clear
  echo -e "⚠  User exited script \n"
  exit
}

function default_settings() {
  VMID="$NEXTID"
  FORMAT=",efitype=4m"
  MACHINE=""
  DISK_CACHE=""
  HN="docker"
  CPU_TYPE=""
  CORE_COUNT="2"
  RAM_SIZE="4096"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${DGN}Using Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${DGN}Using Machine Type: ${BGN}i440fx${CL}"
  echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
  echo -e "${DGN}Using Hostname: ${BGN}${HN}${CL}"
  echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
  echo -e "${DGN}Allocated Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${DGN}Allocated RAM: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${DGN}Using Bridge: ${BGN}${BRG}${CL}"
  echo -e "${DGN}Using MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
  echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${BL}Creating a Docker VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 $NEXTID --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID="$NEXTID"
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist "Choose Type" 10 58 2 \
    "i440fx" "Machine i440fx" ON \
    "q35"   "Machine q35"   OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = "q35" ]; then
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=""
      MACHINE=" -machine q35"
    else
      echo -e "${DGN}Using Machine Type: ${BGN}$MACH${CL}"
      FORMAT=",efitype=4m"
      MACHINE=""
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" \
       --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
       "0" "None (Default)" ON \
       "1" "Write Through"  OFF \
       3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "1" ]; then
      echo -e "${DGN}Using Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DGN}Using Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" \
       --inputbox "Set Hostname" 8 58 docker --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="docker"
    else
      HN=$(echo "${VM_NAME,,}" | tr -d ' ')
    fi
    echo -e "${DGN}Using Hostname: ${BGN}$HN${CL}"
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" \
       --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
       "0" "KVM64 (Default)" ON \
       "1" "Host"              OFF \
       3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "1" ]; then
      echo -e "${DGN}Using CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${DGN}Using CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 2 \
       --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    CORE_COUNT=${CORE_COUNT:-2}
    echo -e "${DGN}Allocated Cores: ${BGN}$CORE_COUNT${CL}"
  else
    exit-script
  fi

  if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 4096 \
       --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    RAM_SIZE=${RAM_SIZE:-4096}
    echo -e "${DGN}Allocated RAM: ${BGN}$RAM_SIZE${CL}"
  else
    exit-script
  fi

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 \
       --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    BRG=${BRG:-vmbr0}
    echo -e "${DGN}Using Bridge: ${BGN}$BRG${CL}"
  else
    exit-script
  fi

  if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 $GEN_MAC \
       --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    MAC=${MAC1:-$GEN_MAC}
    echo -e "${DGN}Using MAC Address: ${BGN}$MAC${CL}"
  else
    exit-script
  fi

  if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a VLAN (leave blank for default)" \
       8 58 "" --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VLAN1" ]; then
      VLAN=""
      echo -e "${DGN}Using VLAN: ${BGN}Default${CL}"
    else
      VLAN=",tag=$VLAN1"
      echo -e "${DGN}Using VLAN: ${BGN}$VLAN1${CL}"
    fi
  else
    exit-script
  fi

  if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" \
       8 58 "" --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$MTU1" ]; then
      MTU=""
      echo -e "${DGN}Using Interface MTU Size: ${BGN}Default${CL}"
    else
      MTU=",mtu=$MTU1"
      echo -e "${DGN}Using Interface MTU Size: ${BGN}$MTU1${CL}"
    fi
  else
    exit-script
  fi

  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" \
       --yesno "Start VM when completed?" 10 58; then
    START_VM="yes"
    echo -e "${DGN}Start VM when completed: ${BGN}yes${CL}"
  else
    START_VM="no"
    echo -e "${DGN}Start VM when completed: ${BGN}no${CL}"
  fi
}

function start_script() {
  if whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" \
       --yesno "Use default settings?" --no-button "Advanced" 10 58; then
    header_info
    echo -e "${BL}Using default settings${CL}"
    default_settings
  else
    header_info
    echo -e "${RD}Using advanced settings${CL}"
    advanced_settings
  fi
}

check_root
arch_check
pve_check
ssh_check
start_script

# --- Ask for username and password ---
if USER_NAME=$(whiptail --inputbox "Enter the new user name (non‑root):" 8 50 3>&1 1>&2 2>&3); then
  USER_NAME=${USER_NAME,,}
else
  msg_error "User not specified, exiting."
  exit 1
fi

if USER_PASS=$(whiptail --passwordbox "Enter the password for ${USER_NAME}:" 8 50 3>&1 1>&2 2>&3); then
  :
else
  msg_error "Password not specified, exiting."
  exit 1
fi
# ----------------------------------------

# --- Keyboard layout selection ---
if KB_LAYOUT=$(whiptail --radiolist \
    "Choose keyboard layout:" 10 60 2 \
    "fr" "French (France)" OFF \
    "ch" "Swiss (CH)"     ON \
    3>&1 1>&2 2>&3); then
  :
else
  msg_error "Keyboard layout not specified, exiting."
  exit 1
fi

if KB_VARIANT=$(whiptail --radiolist \
    "Choose keyboard variant:" 10 60 2 \
    ""   "None"             OFF \
    "fr" "French (variant)" ON \
    3>&1 1>&2 2>&3); then
  :
else
  msg_error "Keyboard variant not specified, exiting."
  exit 1
fi

# --- SSH key for non‑root user ---
if SSH_PUBKEY=$(whiptail --inputbox \
    "Paste the SSH public key for ${USER_NAME}:" 10 80 3>&1 1>&2 2>&3); then
  mkdir -p "${TEMP_DIR}"
  echo "${SSH_PUBKEY}" > "${TEMP_DIR}/authorized_keys"
else
  msg_error "SSH key not provided, exiting."
  exit 1
fi

post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(echo $line | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  MSG_MAX_LENGTH=${MSG_MAX_LENGTH:-0}
  if [[ $((${#ITEM} + $OFFSET)) -gt $MSG_MAX_LENGTH ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]}/3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}? To make a selection, use the Spacebar." \
      16 $((MSG_MAX_LENGTH+23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."
msg_info "Retrieving the URL for the Debian 12 Qcow2 Disk Image"
URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-$(dpkg --print-architecture).qcow2"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"
curl -f#SL -o "$(basename "$URL")" "$URL"
echo -en "\e[1A\e[0K"
FILE=$(basename "$URL")
msg_ok "Downloaded ${CL}${BL}${FILE}${CL}"

STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  nfs|dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VMID/"
    DISK_IMPORT="-format raw"
    FORMAT=",efitype=4m"
    THIN=""
    ;;
esac
for i in 0 1; do
  disk="DISK$i"
  eval DISK${i}=vm-${VMID}-disk-${i}${DISK_EXT:-}
  eval DISK${i}_REF=${STORAGE}:${DISK_REF:-}${!disk}
done

msg_info "Installing Pre-Requisite libguestfs-tools onto Host"
apt-get -qq update && apt-get -qq install libguestfs-tools lsb-release -y >/dev/null
msg_ok "Installed libguestfs-tools successfully"

msg_info "Adding Docker, SSH, keyboard and user into the image"
virt-customize -q -a "${FILE}" \
  --install qemu-guest-agent,apt-transport-https,ca-certificates,curl,gnupg,software-properties-common,lsb-release,openssh-server,keyboard-configuration,console-setup \
  --run-command "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg" \
  --run-command "echo 'deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list" \
  --run-command "apt-get update -qq && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" \
  --run-command "systemctl enable docker" \
  --run-command "sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT=\"${KB_LAYOUT}\"/; s/^XKBVARIANT=.*/XKBVARIANT=\"${KB_VARIANT}\"/' /etc/default/keyboard" \
  --run-command "DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration" \
  --run-command "useradd -m -s /bin/bash -G sudo ${USER_NAME} && echo '${USER_NAME}:${USER_PASS}' | chpasswd" \
  --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && echo 'AllowUsers ${USER_NAME}' >> /etc/ssh/sshd_config && systemctl enable ssh" \
  --run-command "mkdir -p /home/${USER_NAME}/.ssh && chmod 700 /home/${USER_NAME}/.ssh" \
  --upload "${TEMP_DIR}/authorized_keys":/home/${USER_NAME}/.ssh/authorized_keys \
  --run-command "chmod 600 /home/${USER_NAME}/.ssh/authorized_keys && chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/.ssh" \
  --run-command "echo -n > /etc/machine-id" \
  >/dev/null
msg_ok "Image ready: Docker, SSH, keyboard ${KB_LAYOUT}/${KB_VARIANT} and user ${USER_NAME}"

# --- Final confirmation before creating the VM ---
if whiptail --backtitle "Proxmox VE Helper Scripts" --title "READY TO CREATE DOCKER VM?" \
     --yesno "Ready to create a Docker VM?" 10 58; then
  echo -e "${CL}Proceeding with Docker VM creation...${CL}"
else
  msg_error "User cancelled VM creation."
  exit 1
fi

# --- Create the Docker VM ---
msg_info "Creating a Docker VM"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} \
  -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,debian12,docker \
  -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU \
  -onboot 1 -ostype l26 -scsihw virtio-scsi-pci
pvesm alloc $STORAGE $VMID $DISK0 4M >/dev/null
qm importdisk $VMID "${FILE}" $STORAGE ${DISK_IMPORT:-} >/dev/null
qm set $VMID \
  -efidisk0 ${DISK0_REF}${FORMAT} \
  -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=2G \
  -boot order=scsi0 \
  -serial0 socket >/dev/null
qm resize $VMID scsi0 8G >/dev/null
qm set $VMID --agent enabled=1 >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://Helper-Scripts.com' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>Docker VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>

  <span style='margin: 0 10px;'>GitHub</span>
  <span style='margin: 0 10px;'>Discussions</span>
  <span style='margin: 0 10px;'>Issues</span>
</div>
EOF
)
qm set "$VMID" -description "$DESCRIPTION" >/dev/null

msg_ok "Created a Docker VM ${CL}${BL}(${HN})"
if [ "$START_VM" == "yes" ]; then
  msg_info "Starting Docker VM"
  qm start $VMID
  msg_ok "Started Docker VM"
fi
post_update_to_api "done" "none"
msg_ok "Completed Successfully!\n"

