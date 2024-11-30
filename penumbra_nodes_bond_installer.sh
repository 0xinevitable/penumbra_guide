#!/bin/bash

apt-get install -y git git-lfs tmux bc


# Check if running interactively
if [ -z "$PS1" ]; then
    echo "Setting default PS1 as the script is not running interactively."
    export PS1='\h:\w\$ '
fi

# Temporarily change the home directory to avoid sourcing .bashrc
ORIGINAL_HOME=$HOME
export HOME=/tmp

# Author: nodes.bond
# Penumbra Version: v0.80.7
# Go Version: 1.21.1
# Cometbft Version: v0.37.5

set -euo pipefail

# Check Ubuntu Version
UBUNTU_VERSION=$(lsb_release -sr)
if (( $(echo "$UBUNTU_VERSION < 22" | bc -l) )); then
    echo "This script requires Ubuntu version 22 or higher. Your version is $UBUNTU_VERSION."
    exit 1
fi

# Set default GOPATH, GOROOT and update PATH
export GOPATH=${GOPATH:-"$HOME/go"}
export GOROOT=${GOROOT:-"/usr/local/go"}
export PATH="$PATH:$GOROOT/bin:$GOPATH/bin"

# Remove previous versions of Penumbra and related modules
echo "Removing old versions of Penumbra and related modules..."
sudo rm -rf /root/penumbra /root/cometbft

# Rename existing Penumbra directory
if [ -d "/root/penumbra" ]; then
    mv /root/penumbra /root/penumbra_old
fi

# Explicitly set the tmux temporary directory
export TMUX_TMPDIR="/root/.tmux"
mkdir -p "$TMUX_TMPDIR"

# Ensure the tmux server is running correctly
tmux start-server

# Handle non-empty pcli directory
PCLI_DIR="/root/.local/share/pcli"
if [ -d "$PCLI_DIR" ]; then
    if [ "$(ls -A $PCLI_DIR)" ]; then
        echo "The pcli directory at $PCLI_DIR is not empty."
        echo "Existing contents will be removed to continue with a clean initialization."
        rm -rf ${PCLI_DIR:?}/*  # Using parameter expansion to avoid catastrophic deletion
    fi
fi

# Update package list and install dependencies
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev clang git-lfs tmux libclang-dev curl
sudo apt-get install tmux

# Check and install Go if not present
if ! command -v go > /dev/null; then
    echo "Go is not installed. Installing Go..."
    wget https://dl.google.com/go/go1.21.1.linux-amd64.tar.gz
    sudo tar -xvf go1.21.1.linux-amd64.tar.gz -C /usr/local
    export PATH=$PATH:/usr/local/go/bin
fi

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env

# Clone and set up Penumbra
mkdir -p /root/penumbra
cd /root/penumbra
git clone https://github.com/penumbra-zone/penumbra .
git fetch
git checkout v0.80.7
cargo build --release --bin pcli
cargo build --release --bin pd

# Install and set up CometBFT
cd /root
git clone https://github.com/cometbft/cometbft.git
cd cometbft
git checkout v0.37.5
go mod tidy

# Compile the cometbft executable
go build -o cometbft ./cmd/cometbft

# Move the compiled executable to a specific directory inside /root/cometbft if not already there
if [ ! -f /root/cometbft/cometbft ]; then
    mv cometbft /root/cometbft/
else
    echo "Executable already in place."
fi

# Prepare for node operation
make install
ulimit -n 4096

# Set up node configuration
echo "Enter the name of your node:"
read MY_NODE_NAME
# Attempt to automatically determine the external IP address
IP_ADDRESS=$(curl -4s ifconfig.me)

# If the IP address is empty, prompt the user to enter it manually
if [ -z "$IP_ADDRESS" ]; then
    echo "Could not automatically determine the server's IP address."
    echo "Please enter your server's external IP address manually:"
    read IP_ADDRESS
fi

# Validate the IP address format
if [[ ! $IP_ADDRESS =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid IP address format. Please enter a valid IP address."
    exit 1
fi

# Continue with using the IP_ADDRESS in further commands
echo "Using IP address: $IP_ADDRESS"

# Join the Penumbra network
./target/release/pd network join --moniker "$MY_NODE_NAME" --external-address "$IP_ADDRESS:26656" http://void.s9.gay:26657

# Handle non-empty pcli directory
PCLI_DIR="/tmp/.local/share/pcli"
if [ -d "$PCLI_DIR" ]; then
    if [ "$(ls -A $PCLI_DIR)" ]; then
        echo "The pcli directory at $PCLI_DIR is not empty."
        echo "Existing contents will be removed to continue with a clean initialization."
        rm -rf ${PCLI_DIR:?}/*  # Using parameter expansion to avoid catastrophic deletion
    fi
fi

echo "export PATH=\$PATH:/root/penumbra/target/release" >> $HOME/.profile
source $HOME/.profile

# Restore original home directory after detaching from TMUX
export HOME=$ORIGINAL_HOME

echo "Installation is complete. Run the tmux window to start the node."
