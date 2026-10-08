# =============================================================================
# VM2ODCR — Terraform (azapi) : nondisruptive association.
#
# The azapi provider talks directly to the ARM REST API, so associating a running
# ZONAL VM with a CRG is applied as documented by Azure: IMMEDIATE and NONDISRUPTIVE
# (no stop/start). This mirrors the targeted PATCH we use from the Azure CLI.
#
# Here the base VM + network are created with azurerm, the CRG + reservation are
# created with azapi, and the association is done with `azapi_update_resource`
# (a PATCH of properties.capacityReservation) so the VM is NOT bounced.
# =============================================================================

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# --- Networking (minimal) ----------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-vm2odcr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.42.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Base VM WITHOUT the capacity reservation association (so azurerm never bounces it).
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # The association is managed out-of-band by azapi_update_resource below; ignore
  # drift on this computed property so the two providers don't fight.
  lifecycle {
    ignore_changes = [capacity_reservation_group_id]
  }
}

# --- Capacity Reservation Group (the bucket) via azapi ----------------------
resource "azapi_resource" "crg" {
  type      = "Microsoft.Compute/capacityReservationGroups@2024-07-01"
  name      = "crg-vm2odcr"
  parent_id = azurerm_resource_group.rg.id
  location  = azurerm_resource_group.rg.location
  body = {
    zones = [var.zone]
  }
}

# --- Capacity Reservation (the parking spaces) via azapi --------------------
resource "azapi_resource" "res" {
  type      = "Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-07-01"
  name      = "res-D2s_v5-z1"
  parent_id = azapi_resource.crg.id
  location  = azurerm_resource_group.rg.location
  body = {
    sku = {
      name     = var.vm_size
      capacity = var.reserved_count
    }
    zones = [var.zone]
  }
}

# --- Nondisruptive association: PATCH the VM's capacityReservation ----------
resource "azapi_update_resource" "associate" {
  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = azurerm_linux_virtual_machine.vm.id
  body = {
    properties = {
      capacityReservation = {
        capacityReservationGroup = {
          id = azapi_resource.crg.id
        }
      }
    }
  }
  depends_on = [azapi_resource.res]
}
