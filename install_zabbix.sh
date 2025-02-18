#!/usr/bin/env bash
set -Eeuo pipefail

###############################################################################
# A script to:
#   1. Remove old zabbix-agent (if installed).
#   2. Install Zabbix Agent2 (with optional plugins).
#   3. Configure Zabbix Agent2 with a GPU or non-GPU config, based on nvidia-smi.
#   4. Enable and start Zabbix Agent2.
#
# Tested on Debian 12 using Zabbix 7.2 repository.
###############################################################################

# --- VARIABLES ---
ZBX_VERSION="7.2"
REPO_DEB="zabbix-release_latest_${ZBX_VERSION}+debian12_all.deb"
REPO_URL="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/release/debian/pool/main/z/zabbix-release/${REPO_DEB}"

ZBX_AG2_CONF="/etc/zabbix/zabbix_agent2.conf"
ZBX_GPU_CONF_URL="https://raw.githubusercontent.com/CyganTech/configs/refs/heads/main/zabbix2_config_GPU.conf"
ZBX_NON_GPU_CONF_URL="https://raw.githubusercontent.com/CyganTech/configs/refs/heads/main/zabbix2_config.conf"

#--- Trap for errors ---
trap 'echo "ERROR: An unexpected error occurred. Exiting." >&2; exit 1' ERR

###############################################################################
# Check if run as root, or use sudo if available
###############################################################################
function require_root() {
  if [[ $EUID -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      echo "Not running as root. Attempting to use sudo..."
      SUDO="sudo"
    else
      echo "You must run this script as root or have sudo installed." >&2
      exit 1
    fi
  else
    SUDO=""
  fi
}

###############################################################################
# Remove old zabbix-agent if installed
###############################################################################
function remove_old_agent() {
  echo "Checking for legacy zabbix-agent..."
  if dpkg -l | grep -q '^ii\s\+zabbix-agent\b'; then
    echo "Old zabbix-agent found. Removing..."
    $SUDO systemctl stop zabbix-agent || true
    $SUDO systemctl disable zabbix-agent || true
    $SUDO apt-get purge -y zabbix-agent
    echo "Removing leftover config files for old agent..."
    # Remove common old agent conf files:
    $SUDO rm -f /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.dpkg-dist 2>/dev/null || true
    # You could also remove entire old agent directories if you wish:
    # $SUDO rm -rf /etc/zabbix/zabbix_agentd.d
  else
    echo "No legacy zabbix-agent package found. Skipping removal."
  fi
}

###############################################################################
# Install Zabbix repository and Zabbix Agent2
###############################################################################
function install_zabbix_agent2() {
  # Download and install Zabbix repository
  if ! dpkg -s zabbix-release >/dev/null 2>&1; then
    echo "Zabbix repository not found. Installing..."
    wget -q "${REPO_URL}" -O "/tmp/${REPO_DEB}"
    $SUDO dpkg -i "/tmp/${REPO_DEB}"
    $SUDO apt-get update
  else
    echo "Zabbix repository already installed. Skipping repository setup."
  fi

  # Install Zabbix Agent2
  if ! dpkg -l | grep -q '^ii\s\+zabbix-agent2\b'; then
    echo "Installing zabbix-agent2..."
    $SUDO apt-get install -y zabbix-agent2
  else
    echo "zabbix-agent2 already installed. Skipping."
  fi
}

###############################################################################
# Install optional Zabbix Agent2 plugins
###############################################################################
function install_zabbix_agent2_plugins() {
  echo "Installing plugins..."
  $SUDO apt-get install -y zabbix-agent2-plugin-mongodb \
                          zabbix-agent2-plugin-mssql \
                          zabbix-agent2-plugin-postgresql
}

###############################################################################
# Fetch appropriate config depending on GPU availability
###############################################################################
function configure_zabbix_agent2() {
  echo "Checking for nvidia-smi to determine GPU presence..."
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "nvidia-smi detected. Using GPU config."
    CONFIG_URL="$ZBX_GPU_CONF_URL"
  else
    echo "No nvidia-smi found. Using non-GPU config."
    CONFIG_URL="$ZBX_NON_GPU_CONF_URL"
  fi

  echo "Fetching config from: $CONFIG_URL"
  $SUDO wget -q -O "$ZBX_AG2_CONF" "$CONFIG_URL"

  # Double-check that the file was successfully downloaded
  if [[ ! -s "$ZBX_AG2_CONF" ]]; then
    echo "ERROR: Failed to download or write the new Zabbix Agent2 config." >&2
    exit 1
  fi

  echo "Successfully updated $ZBX_AG2_CONF."
}

###############################################################################
# Enable and start Zabbix Agent2 service
###############################################################################
function enable_start_agent2() {
  echo "Enabling and starting zabbix-agent2 service..."
  $SUDO systemctl enable zabbix-agent2
  $SUDO systemctl restart zabbix-agent2
  echo "zabbix-agent2 is now running."
}

###############################################################################
# Main
###############################################################################
function main() {
  require_root
  remove_old_agent
  install_zabbix_agent2
  install_zabbix_agent2_plugins
  configure_zabbix_agent2
  enable_start_agent2

  echo "======================================================================"
  echo "All done! Zabbix Agent2 is installed, configured, and running."
  echo "======================================================================"
}

main "$@"
