# Bicep

Deploys the VM, Capacity Reservation Group, and reservation, and **associates** the VM by
setting `properties.capacityReservation.capacityReservationGroup.id`.

## Usage

```bash
az group create -n rg-vm2odcr-lab-bicep -l eastus2

az deployment group create \
  -g rg-vm2odcr-lab-bicep \
  -f ./main.bicep \
  -p sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

### Low-risk pattern for an existing VM

1. Deploy with `-p reservedCount=0` — the reservation is metadata only; the VM gets associated.
2. Deploy again with `-p reservedCount=1` — allocates real capacity and protects the VM.

> `reservedCount > 0` **bills immediately** at the VM's compute rate.

## Notes

- A running **zonal** VM is associated immediately and nondisruptively. A running **regional**
  (zoneless) VM must be stopped/started for the change to apply.
- Raising `reservedCount` can fail with `SkuNotAvailable` if real capacity isn't available or the
  subscription is restricted from allocating ODCR capacity (common on lab/sponsored subscriptions).
