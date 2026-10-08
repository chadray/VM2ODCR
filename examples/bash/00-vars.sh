#!/usr/bin/env bash
# Shared variables for the Azure CLI (bash) walkthrough.
# Source this file before running the numbered scripts:  source ./00-vars.sh
set -euo pipefail

export LOCATION="eastus2"
export ZONE="1"
export RG="rg-vm2odcr-lab"
export VM_NAME="vm-odcr-demo"
export VM_SIZE="Standard_D2s_v5"      # NOTE: burstable B-series is NOT eligible for ODCR
export ADMIN_USER="azureuser"

export CRG_NAME="crg-vm2odcr"
export RES_NAME="res-D2s_v5-z1"

# Derived at runtime
export SUB_ID="$(az account show --query id -o tsv)"
