# Terraform — `azapi` provider (nondisruptive)

Creates the CRG + reservation and **associates** the VM with a targeted `PATCH`
(`azapi_update_resource`) of `properties.capacityReservation`. For a running **zonal** VM
this is **immediate and nondisruptive** — no stop/start — unlike the `azurerm` approach.

## Usage

```bash
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

### Low-risk pattern for an existing VM

1. Apply with `-var="reserved_count=0"` — reservation is metadata only, VM gets associated.
2. Apply with `-var="reserved_count=1"` — allocates real capacity and protects the VM.

> `reserved_count > 0` **bills immediately** at the VM's compute rate.

## Why this is nondisruptive

The `azapi` provider issues the exact REST `PATCH` that Azure documents for associating a
capacity reservation. Azure applies it in place for a running **zonal** VM. A running
**regional** (zoneless) VM still requires a stop/start for the change to take effect.
