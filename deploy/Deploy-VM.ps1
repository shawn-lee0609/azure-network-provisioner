<#
.SYNOPSIS
    Provisions an Azure Virtual Machine in the Bakend Subnet.
    
.DESCRIPTION
    This script creates a Public IP, Network Interface, and Virtual Machine
    in the Backend Subnet for hosting the Bomberman SignalR game server.
    The VM is configured with .NET runtime prerequisites.
#>

# Parameters 
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

# Configuration
$Location           = "canadacentral"
$ResourceGroup      = "rg-network-$Environment"
$VNetName           = "vnet-main-$Environment"
$BackendSubnetName  = "snet-backend"
$NSGName            = "nsg-backend-$Environment"

# VM Configuration
$VMName             = "vm-gameserver-$Environment"
$PublicIPName       = "pip-gameserver-$Environment"
$NICName            = "nic-gameserver-$Environment"
$VMSize             = "Standard_B2ls_v2"

# VM credentials: If it's in production these would come from key vault
$VMAdminUsername    = "azureuser"
$VMAdminPassword    = "BomberManServer123!"

# Helper Functions
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
Write-Host "  Azure VM Provisioner - $Environment  " -ForegroundColor Magenta

# 1. Verify Azure login
Write-Step "Checking Azure connection..."
$context = Get-AzContext
if(-not $context) {
    Write-Info "No active session found. Launching browser login..."
    Connect-AzAccount
} else {
    Write-Success "Authenticated as: $($context.Account.Id)"
}

# 2. Retrieve VNet and Backend Subnet
Write-Step "Retrieving VNet and Backend Subnet..."
$vnet = Get-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if(-not $vnet) {
    Write-Host "[ERROR] VNet '$VNetName' not found. Run Deploy-Network.ps1 first." -ForegroundColor Red
    exit 1
}

# Retrieve the Backend Subnet object from VNet
$backendSubnet = Get-AzVirtualNetworkSubnetConfig `
    -Name $BackendSubnetName `
    -VirtualNetwork $vnet 

Write-Success "Backend Subnet found: $BackendSubnetName ($($backendSubnet.AddressPrefix))"

# 3. Create Public IP
Write-Step "Creating Public IP: $PublicIPName"
$publicIP = Get-AzPublicIpAddress `
    -Name $PublicIPName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if ($publicIP) {
    Write-Info "Public IP already exists. Reusing."
} else {
    # Dynamic allocation: IP is assigned when VM starts
    # If prefer fixed IP use static allocation, but may cost more
    $publicIP = New-AzPublicIpAddress `
        -Name $PublicIPName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -AllocationMethod Static `
        -Sku Standard

    Write-Success "Public IP created: $PublicIPName (Dynamic)"
}

# 4. Create Network Interface
Write-Step "Creating Network Interface: $NICName"
$nic = Get-AzNetworkInterface `
    -Name $NICName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if($nic) {
    Write-Info "Network Interface already exists. Reusing."
} else {
    # New-AzNetworkInterfaceIpConfig: defines the IP configuration for the NIC
    # Links the NIC to the Backend Subnet and the Public IP
    $ipConfig = New-AzNetworkInterfaceIpConfig `
        -Name "ipconfig-gameserver" `
        -SubnetId $backendSubnet.Id `
        -PublicIpAddressId $publicIP.Id `
        -Primary
    
    $nic = New-AzNetworkInterface `
        -Name $NICName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -IpConfiguration $ipConfig `
        
    Write-Success "Network Interface created: $NICName"
}

# 5. Create Virtual Machine
Write-Step "Creating Virtual Machine: $VMName"
$vm = Get-AzVM `
    -Name $VMName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if ($vm) {
    Write-Info "VM already exists. Reusing."
} else {
    # SSH key path
    $sshKeyPath = "C:\Users\ASUS\.ssh\azure-vm-key.pub"

    # Check if SSH key exists
    if (-not (Test-Path $sshKeyPath)) {
        Write-Host "[ERROR] SSH key not found at $sshKeyPath" -ForegroundColor Red
        Write-Host "Generate it with: ssh-keygen -t rsa -b 4096 -f C:\Users\ASUS\.ssh\azure-vm-key" -ForegroundColor Yellow
        exit 1
    }

    # Build VM credential object
    $securePassword = ConvertTo-SecureString $VMAdminPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($VMAdminUsername, $securePassword)

    # New-AzVM with simplified syntax (handles SSH automatically)
    $job = New-AzVM `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -Name $VMName `
        -Size $VMSize `
        -Image "Canonical:ubuntu-24_04-lts:server:latest" `
        -Credential $credential `
        -VirtualNetworkName $VNetName `
        -SubnetName $BackendSubnetName `
        -PublicIpAddressName $PublicIPName `
        -NetworkInterfaceName $NICName `
        -OpenPorts 22,80,443,5000 `
        -SshKeyName "azure-vm-key" `
        -GenerateSshKey:$false `
        -SshKeyPath $sshKeyPath `
        -AsJob

    $job | Wait-Job

    # Check job result
    if ($job.State -eq 'Completed') {
        Write-Success "Virtual Machine created: $VMName ($VMSize)"
    } elseif ($job.State -eq 'Failed') {
        Write-Host "[ERROR] VM creation failed. Details:" -ForegroundColor Red
        $job | Receive-Job
        exit 1
    } else {
        Write-Host "[WARNING] VM creation job ended in state: $($job.State)" -ForegroundColor Yellow
        $job | Receive-Job
    }
}

# 6. Retrieve and display Public IP
Write-Step "Retrieving assigned Public IP address..."
$publicIP = Get-AzPublicIpAddress `
    -Name $PublicIPName `
    -ResourceGroupName $ResourceGroup

$ipAddress = $publicIP.IpAddress

# 7. Deployment Summary
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Deployment Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Resource Group : $ResourceGroup"
Write-Host "  VM Name        : $VMName"
Write-Host "  VM Size        : $VMSize"
Write-Host "  Subnet         : $BackendSubnetName"
Write-Host "  Public IP      : $ipAddress"
Write-Host "  Admin User     : $VMAdminUsername"
Write-Host "============================================`n" -ForegroundColor Magenta
