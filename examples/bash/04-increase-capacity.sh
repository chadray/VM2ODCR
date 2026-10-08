#!/usr/bin/env bash
# Step 4b: Increase the reservation quantity to cover the running VM (behavior #3).
#
# Because the VM is already running, it already owns a hypervisor slot, so Azure can
# link the reservation to that existing slot. On a standard subscription with capacity,
# this succeeds and the VM becomes PROTECTED.
#
# Real-world note: this is the step that can fail with `SkuNotAvailable` /
# "Capacity Restrictions" if there is no real capacity to allocate, or if the
# subscription type (e.g. sponsored / MngEnv* lab subs) is restricted from allocating
# ODCR capacity. Retrying off-hours, or choosing another zone/size/region, can help.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

az capacity reservation update \
  -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" \
  --capacity 1 \
  -o table

echo "Reservation $RES_NAME raised to capacity 1. VM is now protected."

echo "--- Verify ---"
az capacity reservation group show -g "$RG" -n "$CRG_NAME" \
  --query "{crg:name, zones:zones, vmsAssociated:virtualMachinesAssociated[].id}" -o json
az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" \
  --query "{res:name, sku:sku.name, capacity:sku.capacity, zone:zones[0]}" -o json
