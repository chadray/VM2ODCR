#!/usr/bin/env bash
# Step 1: Create a small, ZONAL VM.
# A zonal VM lets us associate the CRG with ZERO downtime later.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

az group create -n "$RG" -l "$LOCATION" -o table

az vm create \
  -g "$RG" -n "$VM_NAME" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  --zone "$ZONE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --public-ip-address "" \
  --nsg-rule NONE \
  -o table

echo "VM $VM_NAME created in $LOCATION zone $ZONE."
