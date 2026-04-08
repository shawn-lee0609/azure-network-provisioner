<#
.SYNOPSIS
    Deploys an Azure Virtual Network and Subnets automatically.

.DESCRIPTION
    This script provisions a Resource Group, Virtual Network,
    and Frontend/Backend Subnets for a given environment (dev/staging/prod).

.PARAMETER Environment
    Target deployment environment. Defaults to 'dev'.
#>

# Parameters 
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")] # Rejects any value outside this set
    [string]$Environment = "dev"
)

# Configuration
$Location = "canadacentral"
$ResourceGroup = "rg-network-$Environment" # Resource Group name
$VNetName = "vnet-main-$Environment" # Virtual Network name
$VNetAddressSpace = "10.0.0.0/16" # Total address space for the VNet -> Potentially, maximum 256 /24 subnets can be created

# Subnet Configuration
$FrontendSubnetName = "snet-frontend"
$FrontendSubnetPrefix = "10.0.1.0/24" # 254 usable IPs for public-facing workloads

$BackendSubnetName    = "snet-backend"
$BackendSubnetPrefix  = "10.0.2.0/24"         # 254 usable IPs for internal services


# Helper Functions (To format the console output more readable)
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

Write-Host "  Azure Network Provisioner - $Environment  " -ForegroundColor Magenta

# 1. Verify Azure login 
Write-Step "Checking Azure connection..."

# Get-AzContext returns the current authenticated session
# Returns null if not logged in
$context = Get-AzContext

if(-not $context) {
    # Prompt interactive login if no active session exists
    Write-Info "No active session found. Launching browser login..."
    Connect-AzAccount
} else {
    Write-Success "Authenticated as: $($context.Account.Id)"
}

# 2. Create Resource Group
Write-Step "Creating Resource Group: $ResourceGroup"

# Check if the resource group already exists before attempting to create it
# -ErrorAction SilentlyContinue suppresses errors if the resource group is not found
$rg = Get-AzResourceGroup -Name $ResourceGroup -ErrorAction SilentlyContinue

if ($rg) {
    # Skip creation if already exists — keeps the script idempotent
    Write-Info "Resource Group already exists. Reusing."
} else {
    # New-AzResourceGroup creates the logical container for all resources in this deployment
    New-AzResourceGroup -Name $ResourceGroup -Location $Location | Out-Null
    # Out-Null suppresses the return object to keep console output clean
    Write-Success "Resource Group created: $ResourceGroup ($Location)"
}

# 3. Define Subnet configuration objects
Write-Step "Preparing Subnet configurations..."

# New-AzVirtualNetworkSubnetConfig creates an in-memory subnet definition
# Nothing is deployed to Azure at this stage, these objects are passed to New-AzVirtualNetwork
$frontendSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name $FrontendSubnetName `
    -AddressPrefix $FrontendSubnetPrefix
# AddressPrefix uses CIDR notation: 10.0.1.0/24 covers 10.0.1.0 – 10.0.1.255

$backendSubnet = New-AzVirtualNetworkSubnetConfig `
    -Name $BackendSubnetName `
    -AddressPrefix $BackendSubnetPrefix

Write-Success "Frontend Subnet defined: $FrontendSubnetName ($FrontendSubnetPrefix)"
Write-Success "Backend Subnet defined:  $BackendSubnetName ($BackendSubnetPrefix)"

# 4. Create Virtual Network
Write-Step "Creating Virtual Network: $VNetName"

# Check if VNet already exists to avoid duplicate creation errors
$vnet = Get-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if ($vnet) {
    Write-Info "Virtual Network already exists. Reusing." # If there is already a vnet
} else {
    # New-AzVirtualNetwork creates the VNet and attaches both subnets in a single call
    # Subnet accepts an array of subnet config objects defined above
    # By typing New-Az* it sends a HTTP request to Azure, calls AZURE API to create resource and
    # retrieves an object
    $vnet = New-AzVirtualNetwork `
        -Name $VNetName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -AddressPrefix $VNetAddressSpace `
        -Subnet @($frontendSubnet, $backendSubnet)

    Write-Success "Virtual Network created: $VNetName ($VNetAddressSpace)"
}

# 5. Deployment Summary
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Deployment Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Resource Group : $ResourceGroup"
Write-Host "  Location       : $Location"
Write-Host "  VNet           : $VNetName ($VNetAddressSpace)"
Write-Host "  Frontend Subnet: $FrontendSubnetName ($FrontendSubnetPrefix)"
Write-Host "  Backend Subnet : $BackendSubnetName ($BackendSubnetPrefix)"
Write-Host "============================================`n" -ForegroundColor Magenta