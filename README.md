# VM2ODCR — Adding an existing Azure VM to an On-Demand Capacity Reservation (ODCR)

This repo documents, with working code, how to:

1. Build a small VM.
2. Build a Capacity Reservation Group (CRG) and a Capacity Reservation inside it.
3. Associate an **existing** VM with the CRG — using the low‑risk pattern described in
   [Demystifying On-Demand Capacity Reservations](https://techcommunity.microsoft.com/blog/azureinfrastructureblog/demystifying-on-demand-capacity-reservations/4504806).

Code is provided in **Azure CLI (bash)**, **PowerShell (Az)**, **Terraform** (both `azurerm`
and `azapi`), and **Bicep**.

---

## Concepts (the "parking garage")

- An **ODCR** reserves a hypervisor slot ("parking space") for a specific **VM size**, in a
  specific **region** and **availability zone**. A VM associated with it gets priority on
  start and a formal startup SLA.
- An ODCR has two parts:
  - **Capacity Reservation Group (CRG)** — a "bucket". Only needs a **name**, **region**, and
    the **zones** it may use.
  - **Capacity Reservation** — created inside the CRG. Needs a **name**, the **VM size**, the
    **zone**, and the **quantity** (number of instances / "parking spaces").
- **Associated vs. Allocated**: a VM linked to a CRG is *associated*. The number of parking
  spaces the reservation holds is its *allocated capacity*. You can associate more VMs than you
  have allocated — this is **overallocation**, and the extra VMs are not protected until you
  raise the capacity.

### The three behaviors that make protecting existing VMs easy

1. You can add a **running** VM to a CRG.
2. You can create a reservation with a quantity of **zero** (pure metadata — it always succeeds).
3. If associated VMs > allocated capacity, you can **increase** the capacity to cover the running
   VMs, because a running VM already owns a hypervisor slot.

### The recommended order for existing VMs (lowest risk)

> Bring the VMs online first, then apply the reservation.

1. Create the CRG + a reservation with **quantity 0** (behavior #2).
2. **Associate** the running VM(s) to the CRG (behavior #1). The CRG is now overallocated.
3. **Increase** the reservation quantity to match the number of running VMs (behavior #3).

### Disruption when associating

- VM **not running** → change applies immediately.
- VM **running + zonal** (has a zone) → change is **immediate and nondisruptive**.
- VM **running + regional** (no zone) → VM must be **stopped and restarted** to apply.

---

## ⚠️ Important note for Terraform users (`azurerm` vs `azapi`)

Per the source article:

> There is a critical behavior difference between the **AzureRM** provider and the **Azapi**
> provider. If you use the **AzureRM** provider, Terraform will always perform an immediate
> **stop/deallocate of the VM, apply the change, and then start the VM again**. The **Azapi**
> provider works as documented (nondisruptive for a running zonal VM). This is a result of how
> HashiCorp coded the AzureRM provider to manage Azure resources.

In practice, setting `capacity_reservation_group_id` on an existing `azurerm_linux_virtual_machine`
(or `azurerm_windows_virtual_machine`) triggers that **deallocate → update → start** cycle. If you
need a zero-downtime association for a running **zonal** VM, use the **`azapi`** approach (a targeted
`PATCH` of `properties.capacityReservation`) instead. See
[`examples/terraform/azurerm`](examples/terraform/azurerm) and
[`examples/terraform/azapi`](examples/terraform/azapi).

---

## What was actually built in the lab

| Resource | Name | Details |
|---|---|---|
| Resource group | `rg-vm2odcr-lab` | `eastus2` |
| VM | `vm-odcr-demo` | `Standard_D2s_v5`, **zone 1**, Ubuntu 22.04, no public IP |
| Capacity Reservation Group | `crg-vm2odcr` | `eastus2`, zone 1 |
| Capacity Reservation | `res-D2s_v5-z1` | `Standard_D2s_v5`, zone 1, **capacity 0** |
| Association | — | `vm-odcr-demo` associated with `crg-vm2odcr` ✅ |

### Two real-world gotchas we hit (and how we handled them)

1. **`az vm update --capacity-reservation-group` failed with**
   `Operation 'Enabling zone movement' is not supported...`.
   The CLI issues a *full PUT* of the VM that includes its `zones`, which ARM misinterprets as a
   zone-movement request. **Workaround:** use a targeted REST `PATCH` that sets only
   `properties.capacityReservation` (no `zones` in the body). This is shown in
   [`examples/bash/03-associate-vm.sh`](examples/bash/03-associate-vm.sh).

2. **Raising the reservation quantity 0 → 1 failed with** `SkuNotAvailable` /
   *"failed for Capacity Restrictions"*.
   This is the **real capacity failure mode** the article describes: allocating a reservation
   requires Azure to find real hardware. Sponsored / `MngEnv*` lab subscriptions are frequently
   **restricted from allocating ODCR capacity** (we confirmed the same failure in multiple
   zones and regions). Everything *management-plane* works (CRG, reservation, association); only
   the actual hardware allocation is blocked on this subscription type. On a standard
   subscription with available capacity, step 3 (raise the quantity) completes the protection.

---

## Step-by-step

Pick your tool and follow the matching example folder. Each one performs the same four steps:

1. Create the VM (small, zonal).
2. Create the CRG.
3. Create a reservation with **quantity 0**.
4. Associate the VM, then raise the quantity to 1.

| Tool | Folder |
|---|---|
| Azure CLI (bash) | [`examples/bash`](examples/bash) |
| PowerShell (Az) | [`examples/powershell`](examples/powershell) |
| Terraform (`azurerm`) | [`examples/terraform/azurerm`](examples/terraform/azurerm) |
| Terraform (`azapi`, nondisruptive) | [`examples/terraform/azapi`](examples/terraform/azapi) |
| Bicep | [`examples/bicep`](examples/bicep) |

---

## Cleanup

Delete everything created in the lab:

```bash
az group delete -n rg-vm2odcr-lab --yes --no-wait
```

A reservation with quantity > 0 **bills immediately** (same rate as a running VM of that size),
so remove it when you're done experimenting. Deleting the resource group removes the VM, CRG, and
reservation together. (A reservation must have no associated running VMs / be emptied before the CRG
can be deleted independently; deleting the whole RG handles ordering for you.)

---

## References

- [On-Demand Capacity Reservations overview](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overview)
- [Associate a VM to a capacity reservation](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-associate-virtual-machine)
- [Overallocating capacity reservations](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overallocate)
- [Demystifying On-Demand Capacity Reservations (blog)](https://techcommunity.microsoft.com/blog/azureinfrastructureblog/demystifying-on-demand-capacity-reservations/4504806)

