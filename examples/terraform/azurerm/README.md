# Terraform — `azurerm` provider

Builds the VM, Capacity Reservation Group, and reservation, and **associates** the VM.

## ⚠️ Disruptive association

Setting `capacity_reservation_group_id` on `azurerm_linux_virtual_machine` makes the
`azurerm` provider **stop/deallocate the VM, apply the change, then start it again** — every
time, zonal or regional. This is how HashiCorp implemented the resource, not an Azure/ARM
requirement. For a **zero-downtime** association of a running **zonal** VM, use the
[`../azapi`](../azapi) example, which issues a targeted `PATCH`.

## Usage

```bash
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

### Low-risk pattern for an existing VM

1. First apply with `-var="reserved_count=0"` (reservation is metadata only).
2. Apply again with `-var="reserved_count=1"` to allocate real capacity and protect the VM.

> `reserved_count > 0` **bills immediately** at the VM's compute rate.
