# =============================================================================
# VM2ODCR — Terraform (azurerm) : VM + CRG + reservation, with association.
#
# ⚠️  IMPORTANT (HashiCorp azurerm behavior):
#     Setting `capacity_reservation_group_id` on `azurerm_linux_virtual_machine`
#     causes Terraform to perform an immediate STOP/DEALLOCATE of the VM, apply the
#     change, then START it again. This happens whether the VM is zonal or regional.
#     It is a function of how the azurerm provider manages the VM resource, NOT a
#     property of Azure/ARM itself. For a zero-downtime association of a running
#     ZONAL VM, use the `azapi` example in ../azapi instead.
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

# --- Capacity Reservation Group (the bucket) --------------------------------
resource "azurerm_capacity_reservation_group" "crg" {
  name                = "crg-vm2odcr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  zones               = [var.zone]
}

# --- Capacity Reservation (the actual parking spaces) -----------------------
# For a brand-new build, Terraform will create the reservation at `reserved_count`.
# For the low-risk EXISTING-VM pattern you would create this at 0, associate, then
# bump `reserved_count` in a second apply.
resource "azurerm_capacity_reservation" "res" {
  name                          = "res-D2s_v5-z1"
  capacity_reservation_group_id = azurerm_capacity_reservation_group.crg.id
  zone                          = var.zone

  sku {
    name     = var.vm_size
    capacity = var.reserved_count
  }
}

# --- The VM, associated with the CRG ----------------------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.nic.id]

  # ⚠️ This association triggers a deallocate -> update -> start cycle on apply.
  capacity_reservation_group_id = azurerm_capacity_reservation_group.crg.id

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
}
