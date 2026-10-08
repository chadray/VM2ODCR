// =============================================================================
// VM2ODCR — Bicep: VM + Capacity Reservation Group + reservation, with association.
//
// A VM is linked to a CRG by setting:
//   properties.capacityReservation.capacityReservationGroup.id
//
// For an EXISTING VM, deploy this template referencing that VM's current config with
// the capacityReservation block added. For a running ZONAL VM the change is immediate
// and nondisruptive; a running REGIONAL VM must be stopped/started to apply.
//
// Low-risk pattern: deploy the reservation with `reservedCount = 0`, then redeploy
// with `reservedCount = 1` after the VM is associated.
// =============================================================================

@description('Azure region.')
param location string = resourceGroup().location

@description('Availability zone for the VM and reservation.')
param zone string = '1'

@description('VM name.')
param vmName string = 'vm-odcr-demo'

@description('VM size. NOTE: burstable B-series is NOT eligible for ODCR.')
param vmSize string = 'Standard_D2s_v5'

@description('Admin username.')
param adminUsername string = 'azureuser'

@description('SSH public key for the admin user.')
param sshPublicKey string

@description('Number of reserved instances (parking spaces). Start at 0, then raise to protect running VMs.')
param reservedCount int = 1

var crgName = 'crg-vm2odcr'
var reservationName = 'res-D2s_v5-z1'

// --- Networking (minimal) ---------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-vm2odcr'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.42.0.0/16'] }
    subnets: [
      {
        name: 'default'
        properties: { addressPrefix: '10.42.1.0/24' }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// --- Capacity Reservation Group (the bucket) --------------------------------
resource crg 'Microsoft.Compute/capacityReservationGroups@2024-07-01' = {
  name: crgName
  location: location
  zones: [zone]
}

// --- Capacity Reservation (the parking spaces) ------------------------------
resource reservation 'Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-07-01' = {
  parent: crg
  name: reservationName
  location: location
  sku: {
    name: vmSize
    capacity: reservedCount
  }
  zones: [zone]
}

// --- VM, associated with the CRG --------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  zones: [zone]
  properties: {
    hardwareProfile: { vmSize: vmSize }
    // The association: link the VM to the CRG.
    capacityReservation: {
      capacityReservationGroup: {
        id: crg.id
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
  // Ensure the reservation exists before the VM references the group.
  dependsOn: [reservation]
}
