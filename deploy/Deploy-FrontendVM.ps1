<#
.SYNOPSIS
    Provisions an Azure Virtual Machine in the Frontend Subnet.

.DESCRIPTION
    This script creates a Public IP, Network Interface, and Virtual Machine
    in the Frontend Subnet for hosting the Bomberman Unity WebGL client via Nginx.
#>

# Parameters
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

# Configuration
$Location            = "canadacentral"
$ResourceGroup       = "rg-network-$Environment"
$VNetName            = "vnet-main-$Environment"
$FrontendSubnetName  = "snet-frontend"

# VM Configuration
$VMName              = "vm-frontend-$Environment"
$PublicIPName        = "pip-frontend-$Environment"
$NICName             = "nic-frontend-$Environment"
$VMSize              = "Standard_B2ls_v2"

# VM credentials
$VMAdminUsername     = "azureuser"
$VMAdminPassword     = "FrontendServer2026!"

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
Write-Host "  Azure Frontend VM Provisioner - $Environment  " -ForegroundColor Magenta

# 1. Verify Azure login
Write-Step "Checking Azure connection..."
$context = Get-AzContext
if (-not $context) {
    Write-Info "No active session found. Launching browser login..."
    Connect-AzAccount
} else {
    Write-Success "Authenticated as: $($context.Account.Id)"
}

# 2. Retrieve VNet and Frontend Subnet
Write-Step "Retrieving VNet and Frontend Subnet..."
$vnet = Get-AzVirtualNetwork `
    -Name $VNetName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if (-not $vnet) {
    Write-Host "[ERROR] VNet '$VNetName' not found. Run Deploy-Network.ps1 first." -ForegroundColor Red
    exit 1
}

$frontendSubnet = Get-AzVirtualNetworkSubnetConfig `
    -Name $FrontendSubnetName `
    -VirtualNetwork $vnet

Write-Success "Frontend Subnet found: $FrontendSubnetName ($($frontendSubnet.AddressPrefix))"

# 3. Create Public IP
Write-Step "Creating Public IP: $PublicIPName"
$publicIP = Get-AzPublicIpAddress `
    -Name $PublicIPName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if ($publicIP) {
    Write-Info "Public IP already exists. Reusing."
} else {
    $publicIP = New-AzPublicIpAddress `
        -Name $PublicIPName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -AllocationMethod Static `
        -Sku Standard

    Write-Success "Public IP created: $PublicIPName (Static)"
}

# 4. Create Network Interface
Write-Step "Creating Network Interface: $NICName"
$nic = Get-AzNetworkInterface `
    -Name $NICName `
    -ResourceGroupName $ResourceGroup `
    -ErrorAction SilentlyContinue

if ($nic) {
    Write-Info "Network Interface already exists. Reusing."
} else {
    $ipConfig = New-AzNetworkInterfaceIpConfig `
        -Name "ipconfig-frontend" `
        -SubnetId $frontendSubnet.Id `
        -PublicIpAddressId $publicIP.Id `
        -Primary

    $nic = New-AzNetworkInterface `
        -Name $NICName `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -IpConfiguration $ipConfig

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
    $sshKeyPath = "C:\Users\ASUS\.ssh\azure-vm-key-nopass.pub"

    if (-not (Test-Path $sshKeyPath)) {
        Write-Host "[ERROR] SSH key not found at $sshKeyPath" -ForegroundColor Red
        exit 1
    }

    $securePassword = ConvertTo-SecureString $VMAdminPassword -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($VMAdminUsername, $securePassword)

    # Read SSH public key
    $sshPublicKey = Get-Content $sshKeyPath -Raw

    # Build VM config step by step
    $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize

    $vmConfig = Set-AzVMOperatingSystem `
        -VM $vmConfig `
        -Linux `
        -ComputerName $VMName `
        -Credential $credential `
        -DisablePasswordAuthentication $true

    $vmConfig = Add-AzVMSshPublicKey `
        -VM $vmConfig `
        -KeyData $sshPublicKey `
        -Path "/home/$VMAdminUsername/.ssh/authorized_keys"

    $vmConfig = Set-AzVMSourceImage `
        -VM $vmConfig `
        -PublisherName "Canonical" `
        -Offer "ubuntu-24_04-lts" `
        -Skus "server" `
        -Version "latest"

    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

    $vmConfig = Set-AzVMOSDisk `
        -VM $vmConfig `
        -Name "$VMName-osdisk" `
        -CreateOption FromImage `
        -StorageAccountType Standard_LRS

    $job = New-AzVM `
        -ResourceGroupName $ResourceGroup `
        -Location $Location `
        -VM $vmConfig `
        -AsJob

    $job | Wait-Job

    if ($job.State -eq 'Completed') {
        Write-Success "Virtual Machine created: $VMName ($VMSize)"
    } elseif ($job.State -eq 'Failed') {
        Write-Host "[ERROR] VM creation failed." -ForegroundColor Red
        $job | Receive-Job
        exit 1
    } else {
        Write-Host "[WARNING] Job state: $($job.State)" -ForegroundColor Yellow
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
Write-Host "  Subnet         : $FrontendSubnetName"
Write-Host "  Public IP      : $ipAddress"
Write-Host "  Admin User     : $VMAdminUsername"
Write-Host "============================================`n" -ForegroundColor Magenta