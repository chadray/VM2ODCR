#!/usr/bin/env bash
# Step 4a: Associate the EXISTING VM with the CRG (behavior #1).
#
# Why not just `az vm update --capacity-reservation-group`?
#   On a running zonal VM, that command currently issues a FULL PUT of the VM that
#   includes its `zones`, which ARM can misread as a zone-movement request and fail with:
#     (BadRequest) Operation 'Enabling zone movement' is not supported ...
#   We avoid that by sending a TARGETED PATCH of only properties.capacityReservation.
#
# Disruption:
#   - Running + ZONAL  -> immediate, nondisruptive (this script).
#   - Running + REGIONAL (no zone) -> you must stop/deallocate then start for it to apply.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

CRG_ID="$(az capacity reservation group show -g "$RG" -n "$CRG_NAME" --query id -o tsv)"
VM_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}"

echo "Associating $VM_NAME with $CRG_NAME via targeted PATCH..."
az rest --method patch \
  --url "https://management.azure.com${VM_ID}?api-version=2024-07-01" \
  --headers "Content-Type=application/json" \
  --body "{\"properties\":{\"capacityReservation\":{\"capacityReservationGroup\":{\"id\":\"${CRG_ID}\"}}}}" \
  --query "properties.capacityReservation.capacityReservationGroup.id" -o tsv

# ---------------------------------------------------------------------------
# Alternative (works, but DISRUPTIVE) if you prefer the first-party CLI verb:
#   az vm deallocate -g "$RG" -n "$VM_NAME"
#   az vm update     -g "$RG" -n "$VM_NAME" --capacity-reservation-group "$CRG_ID"
#   az vm start      -g "$RG" -n "$VM_NAME"
# ---------------------------------------------------------------------------

echo "Associated. The CRG is now OVERALLOCATED (associated > allocated)."
