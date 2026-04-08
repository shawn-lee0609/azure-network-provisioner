<#
.SYNOPSIS
    Deploys Network Security Groups and associates them with subnets.

.DESCRIPTION   
    This script creates two NSGs (Frontend and Backend) with appropriate
    inbound security rules, then associates each NSG with its corresponding 
    subnet in the existing Network.
#>

# Parameters
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

# Configuration
$Location          = "canadacentral"
$ResourceGroup     = "rg-network-$Environment"
$VNetName          = "vnet-main-$Environment"

# NSG names
$FrontendNSGName = "nsg-frontend-$Environment"
$BackendNSGName    = "nsg-backend-$Environment"

# Subnet names (must match Deploy-Network.ps1)
$FrontendSubnetName = "snet-frontend"
$BackendSubnetName  = "snet-backend"

# SignalR port for the Bomberman game server
$SignalRPort = 5000


# Helper function for readable console output
function Write-Step {
    param([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

# Main Deployment Logic
Write-Host "  Azure NSG Provisioner - $Environment  " -ForegroundColor Magenta

# 1. Verify Azure login
Write-Step "Checking Azure connection..."
$context = Get-AzContext
if (-not $context) {
    Write-Info "No active session found. Launching browser login..."
    Connect-AzAccount
} else {
    Write-Success "Authenticated as: $($context.Account.Id)"
}

# 2. Retrieve existing VNet
# Need the VNet object to associate NSGs with its subnets later
Write-Step "Retrieving Virtual Network: $VNetName"
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue

if (-not $vnet) {
    # NSGs are meaningless without a VNet, exit early with a clear message
    Write-Host "[ERROR] VNet '$VNetName' not found. Run Deploy-Network.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Success "VNet found: $VNetName"

# 3. Create Frontend NSG
Write-Step "Creating Frontend NSG: $FrontendNSGName"

# Checks if the NSG already exists by Get-Az* (idempotency)
# if exists, do not create a new one, if not, create a new one by New-Az*
$frontendNSG = Get-AzNetworkSecurityGroup -Name $FrontendNSGName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue

if ($frontendNSG) {
    Write-Info "Frontend NSG already exists. Reusing."
} else {
    # Defined inbound security rules for the Frontend NSG
    # Each rule needs: priority (lower number = higher priority), direction, access, protocol, port, source, destination

    # Rule 1: Allow HTTP (port# 80)
    # Priority 100
    # From the Internet
    $allowHTTP = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-HTTP" `
        -Description "Allow inbound HTTP traffic" `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 100 `
        -SourceAddressPrefix Internet `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange 80 `
        -Access Allow

    # Rule 2: Allow HTTPS (port 443)
    $allowHTTPS = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-HTTPS" `
        -Description "Allow inbound HTTPS traffic" `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 110 `
        -SourceAddressPrefix Internet `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange 443 `
        -Access Allow

    # Create the NSG with both rules attached
    $frontendNSG = New-AzNetworkSecurityGroup `
        -Name $FrontendNSGName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -SecurityRules @($allowHTTP, $allowHTTPS)

    Write-Success "Frontend NSG created: $FrontendNSGName (Allow HTTP:80, HTTPS:443)"
}

# 4. Create Backend NSG
Write-Step "Creating Backend NSG: $BackendNSGName"
$backendNSG = Get-AzNetworkSecurityGroup -Name $BackendNSGName -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue

if ($backendNSG) {
    Write-Info "Backend NSG already exists. Reusing."
} else {
    # Rule 1: Allow traffic from Frontend Subnet only
    # SourceAddressPrefix set to Frontend CIDR — backend should not be directly reachable from Internet
    $allowFromFrontend = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-From-Frontend" `
        -Description "Allow inbound traffic from Frontend Subnet" `
        -Protocol Tcp `
        -Direction Inbound `
        -Priority 100 `
        -SourceAddressPrefix "10.0.1.0/24" `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange * `
        -Access Allow

    # Rule 2: Allow SignalR WebSocket port from Internet
    # Required for game clients to connect directly to the Bomberman server
    # Allows traffic destined to dedicated SignalRPort
    $allowSignalR = New-AzNetworkSecurityRuleConfig `
        -Name "Allow-SignalR" `
        -Description "Allow inbound WebSocket traffic for SignalR game server" `
        -Protocol TCP `
        -Direction Inbound `
        -Priority 110 `
        -SourceAddressPrefix Internet `
        -SourcePortRange * `
        -DestinationAddressPrefix * `
        -DestinationPortRange $SignalRPort `
        -Access Allow

    # Create the Backend NSG with both rules
    $backendNSG = New-AzNetworkSecurityGroup `
        -Name $BackendNSGName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -SecurityRules @($allowFromFrontend, $allowSignalR)

    Write-Success "Backend NSG created: $BackendNSGName (Allow Frontend traffic + SignalR:$SignalRPort)"
}

# 5. Associate NSGs with subnets
# NSG rules do nothing until the NSG is linked to a subnet
# Retrieve each subnet object from the VNet, attach the NSG, then save the VNet

Write-Step "Associating Frontend NSG with subnet: $FrontendSubnetName"

# Get-AzVirtualNetworkSubnetConfig retrieves a specific subnet object from the VNet
$frontendSubnet = Get-AzVirtualNetworkSubnetConfig -Name $FrontendSubnetName -VirtualNetwork $vnet

# Set-AzVirtualNetworkSubnetConfig updates the subnet's NSG assignment in memory
# This does not apply to Azure yet, requires Set-AzVirtualNetwork to commit
Set-AzVirtualNetworkSubnetConfig `
    -Name $FrontendSubnetName `
    -VirtualNetwork $vnet `
    -AddressPrefix $frontendSubnet.AddressPrefix `
    -NetworkSecurityGroup $frontendNSG | Out-Null

# Set-AzVirtualNetwork pushes the updated VNet config to Azure
$vnet | Set-AzVirtualNetwork | Out-Null
Write-Success "Frontend NSG associated with $FrontendSubnetName"

Write-Step "Associating Backend NSG with subnet: $BackendSubnetName"
# Re-fetch VNet to get the latest state after the previous update
$vnet = Get-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroup

$backendSubnet = Get-AzVirtualNetworkSubnetConfig -Name $BackendSubnetName -VirtualNetwork $vnet

Set-AzVirtualNetworkSubnetConfig `
    -Name $BackendSubnetName `
    -VirtualNetwork $vnet `
    -AddressPrefix $backendSubnet.AddressPrefix `
    -NetworkSecurityGroup $backendNSG | Out-Null

$vnet | Set-AzVirtualNetwork | Out-Null
Write-Success "Backend NSG associated with $BackendSubnetName"

# ── 6. Deployment Summary ──────────────────────
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Deployment Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Resource Group  : $ResourceGroup"
Write-Host "  Frontend NSG    : $FrontendNSGName"
Write-Host "    Rules         : Allow HTTP(80), HTTPS(443)"
Write-Host "    Associated    : $FrontendSubnetName"
Write-Host "  Backend NSG     : $BackendNSGName"
Write-Host "    Rules         : Allow Frontend(10.0.1.0/24), SignalR($SignalRPort)"
Write-Host "    Associated    : $BackendSubnetName"
Write-Host "============================================`n" -ForegroundColor Magenta