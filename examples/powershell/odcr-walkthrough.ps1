<#
    VM2ODCR — PowerShell (Az module) walkthrough.

    Adds an EXISTING VM to an On-Demand Capacity Reservation using the low-risk
    order: create CRG + reservation (qty 0) -> associate running VM -> raise qty.

    Prereqs:
        Install-Module Az -Scope CurrentUser
        Connect-AzAccount
        Set-AzContext -Subscription "<your-sub-id>"
#>

$ErrorActionPreference = 'Stop'

# ---- Variables -------------------------------------------------------------
$Location  = 'eastus2'
$Zone      = '1'
$Rg        = 'rg-vm2odcr-lab'
$VmName    = 'vm-odcr-demo'
$VmSize    = 'Standard_D2s_v5'      # NOTE: burstable B-series is NOT eligible for ODCR
$AdminUser = 'azureuser'

$CrgName   = 'crg-vm2odcr'
$ResName   = 'res-D2s_v5-z1'

# ---- Step 1: Resource group + small ZONAL VM -------------------------------
New-AzResourceGroup -Name $Rg -Location $Location -Force | Out-Null

# Prompt for the local admin credential (password auth for brevity).
$cred = Get-Credential -UserName $AdminUser -Message 'Enter a password for the VM admin user'

New-AzVM `
    -ResourceGroupName $Rg `
    -Name $VmName `
    -Location $Location `
    -Zone $Zone `
    -Size $VmSize `
    -Image 'Ubuntu2204' `
    -Credential $cred `
    -PublicIpAddressName $null | Out-Null

Write-Host "VM $VmName created in $Location zone $Zone."

# ---- Step 2: Capacity Reservation Group (the bucket) -----------------------
New-AzCapacityReservationGroup `
    -ResourceGroupName $Rg `
    -Name $CrgName `
    -Location $Location `
    -Zone $Zone | Out-Null

# ---- Step 3: Reservation inside the CRG, starting at capacity 0 ------------
# Quantity 0 is pure metadata and always succeeds (behavior #2).
$sku = New-Object Microsoft.Azure.Management.Compute.Models.Sku
$sku.Name     = $VmSize
$sku.Capacity = 0

New-AzCapacityReservation `
    -ResourceGroupName $Rg `
    -ReservationGroupName $CrgName `
    -Name $ResName `
    -Sku $sku `
    -Zone $Zone | Out-Null

Write-Host "CRG $CrgName and reservation $ResName (capacity 0) created."

# ---- Step 4a: Associate the EXISTING VM with the CRG (behavior #1) ---------
# Running + zonal => immediate/nondisruptive. Running + regional => stop/start required.
$crg = Get-AzCapacityReservationGroup -ResourceGroupName $Rg -Name $CrgName
$vm  = Get-AzVM -ResourceGroupName $Rg -Name $VmName

Update-AzVM -ResourceGroupName $Rg -VM $vm -CapacityReservationGroupId $crg.Id | Out-Null
Write-Host "Associated $VmName with $CrgName. CRG is now overallocated."

# If the VM is REGIONAL (no zone) you must bounce it for the change to take effect:
#   Stop-AzVM  -ResourceGroupName $Rg -Name $VmName -Force
#   Start-AzVM -ResourceGroupName $Rg -Name $VmName

# ---- Step 4b: Raise the reservation quantity to protect the VM (behavior #3)
# May fail with SkuNotAvailable if there is no real capacity to allocate, or if the
# subscription is restricted from allocating ODCR capacity (common on lab/sponsored subs).
Update-AzCapacityReservation `
    -ResourceGroupName $Rg `
    -ReservationGroupName $CrgName `
    -Name $ResName `
    -CapacityToReserve 1 | Out-Null

Write-Host "Reservation $ResName raised to capacity 1. VM is now protected."

# ---- Verify ----------------------------------------------------------------
Get-AzCapacityReservationGroup -ResourceGroupName $Rg -Name $CrgName |
    Select-Object Name, Zones, @{n='VMs';e={$_.VirtualMachinesAssociated.Id}} | Format-List
Get-AzCapacityReservation -ResourceGroupName $Rg -ReservationGroupName $CrgName -Name $ResName |
    Select-Object Name, @{n='Sku';e={$_.Sku.Name}}, @{n='Capacity';e={$_.Sku.Capacity}}, Zones | Format-List

# ---- Cleanup ---------------------------------------------------------------
# Remove-AzResourceGroup -Name $Rg -Force -AsJob
