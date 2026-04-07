<# 
.SYNOPSIS
    Deploys a Route Table and associates it with the Backend Subnet.
    
.DESCRIPTION
    This script creates a custom Route Table with a default route
    that directs all outbound traffic through the Internet gateway.
    The Route Table is then associated with the Backend Subnet.
#>

# Paramters
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

# Configuration
$Location           = "canadacentral"
$ResourceGroup      = "rg-network-$Environment"
$VNetName           = "vnet-main-$Environment"
$RouteTableName     = "rt-custom-$Environment"

# Route Table is applied to Backend Subnet where the game server lives
$BackendSubnetName = "snet-backend"
$BackendSubnetPrefix = "10.0.2.0/24"

# Helper Function
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
Write-Host "  Azure Route Table Provisioner - $Environment  " -ForegroundColor Magenta

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
Write-Step "Retrieving Virtual Network: $VNetName"
$vnet = Get-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if(-not $vnet) {
    Write-Host "[ERROR] VNet '$VNetName' not found. Run Deploy-Network.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Success "VNet found: $VNetName"

# 3. Create Route Table
Write-Step "Creating Route Table: $RouteTableName"
$routeTable = Get-AzRouteTable `
    -Name $RouteTableName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if($routeTable) {
    Write-Info "Route Table already exists. Reusing"
} else {
    # Define a default route that sends all outbound traffic (0.0.0.0/0) to the Internet
    # 0.0.0.0/0 = "everything" — acts as a catch-all for any traffic
    # not matched by a more specific route

    # First, create a route
    $defaultRoute = New-AzRouteConfig `
    -Name "route-default-internet" `
    -AddressPrefix "0.0.0.0/0" `
    -NextHopType Internet
    # NextHopType Internet = send this traffic directly out to the Internet

    # Second, create the Route Table with the default route attached
    $routeTable = New-AzRouteTable `
        -Name $RouteTableName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -Route @($defaultRoute)

    Write-Success "Route Table created: $RouteTableName"
    Write-Success "Default route added: 0.0.0.0/0 -> Internet"
}

# 4. Third, associate Route Table with Backend subnet
# Just like NSGs, Route Tables have no effect until linked to a subnet
Write-Step "Associating Route Table with subnet: $BackendSubnetName"

# Re-fetch VNet to ensure we have the latest state
$vnet = Get-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroup

$backendSubnet = Get-AzVirtualNetworkSubnetConfig `
    -Name $BackendSubnetName `
    -VirtualNetwork $vnet

# Set-AzVirtualNetworkConfig updates the subnet in memory
# We must preserve the existing NSG by passing it through
Set-AzVirtualNetworkSubnetConfig `
    -Name $BackendSubnetName `
    -VirtualNetwork $vnet `
    -AddressPrefix $BackendSubnetPrefix `
    -NetworkSecurityGroup $backendSubnet.NetworkSecurityGroup `
    -RouteTable $routeTable | Out-Null

# Commit the updated subnet config to Azure
$vnet | Set-AzVirtualNetwork | Out-Null
Write-Success "Route Table associated with $BackendSubnetName"

# ── 5. Deployment Summary ──────────────────────
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Deployment Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Resource Group : $ResourceGroup"
Write-Host "  Route Table    : $RouteTableName"
Write-Host "    Route        : 0.0.0.0/0 -> Internet"
Write-Host "    Associated   : $BackendSubnetName"
Write-Host "============================================`n" -ForegroundColor Magenta