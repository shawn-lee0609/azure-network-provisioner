<#
.SYNOPSIS
    Deploys the Bomberman SignalR game server onto the Azure VM.
    VM runs pulls the Git hub repo for Bomberman Server.

.DESCRIPTION
    Connects to the VM via SSH and executes a series of remote commands to:
    1. Install .NET 10 runtime
    2. Clone the Bomberman SignalR server repository
    3. Build and publish the application
    4. Register it as a systemd service for automatic startup 
#>

# Parameters
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$VMPublicIP = ""
)

# Configuration
$ResourceGroup  = "rg-network-$Environment"
$PublicIPName   = "pip-gameserver-$Environment"
$VMAdminUser    = "azureuser"
$SSHKeyPath     = "C:\Users\ASUS\.ssh\azure-vm-key-nopass"
$SignalRPort     = 5000
$RepoUrl = "https://github.com/shawn-lee0609/BombermanServer.git"

# Repo clones into $AppDirectory
# .csproj is located at $AppDirectory/BombermanServer/
$AppDirectory   = "/home/azureuser/bomberman-server"
$ProjectDir     = "$AppDirectory/BombermanServer"
$PublishDir     = "$ProjectDir/publish"
$ServiceName    = "bomberman"

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

function Invoke-SSHCommand {
    <#
    .SYNOPSIS
        Executes a command on the remote VM via SSH.
        Exits the script if the command fails.
    #>
    param(
        [string]$Command,
        [string]$Description
    )

    Write-Info "Remote: $Description"

    # -o StrictHostKeyChecking=no: skip host verification prompt
    # -o BatchMode=yes: non-interactive mode (no password prompt)
    ssh -i $SSHKeyPath `
        -o StrictHostKeyChecking=no `
        -o BatchMode=yes `
        "$VMAdminUser@$script:IPAddress" $Command

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Remote command failed: $Description" -ForegroundColor Red
        exit 1
    }
}

# Main Deployment Logic
Write-Host "  Azure App Deployer - $Environment  " -ForegroundColor Magenta

# 1. Verify Azure login 
Write-Step "Checking Azure connection..."
$context = Get-AzContext
if (-not $context) {
    Write-Info "No active session found. Launching browser login..."
    Connect-AzAccount
} else {
    Write-Success "Authenticated as: $($context.Account.Id)"
}

# 2. Retrieve VM Public IP
Write-Step "Retrieving VM Public IP..."

if ($VMPublicIP -ne "") {
    # Use manually provided IP if specified
    $script:IPAddress = $VMPublicIP
    Write-Info "Using provided IP: $script:IPAddress"
} else {
    # Fetch from Azure automatically
    $publicIP = Get-AzPublicIpAddress `
        -Name $PublicIPName `
        -ResourceGroupName $ResourceGroup `
        -ErrorAction SilentlyContinue

    if (-not $publicIP) {
        Write-Host "[ERROR] Public IP '$PublicIPName' not found. Run Deploy-VM.ps1 first." -ForegroundColor Red
        exit 1
    }

    $script:IPAddress = $publicIP.IpAddress
    Write-Success "VM Public IP: $script:IPAddress"
}

# 3. Test SSH connectivity
Write-Step "Testing SSH connectivity..."
ssh -i $SSHKeyPath `
    -o StrictHostKeyChecking=no `
    -o BatchMode=yes `
    -o ConnectTimeout=10 `
    "$VMAdminUser@$script:IPAddress" "echo connected"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Cannot connect to VM via SSH. Check NSG rules and VM status." -ForegroundColor Red
    exit 1
}
Write-Success "SSH connection established"

# 4. Update package list
Write-Step "Updating package list..."
Invoke-SSHCommand `
    -Command "sudo apt-get update -y" `
    -Description "apt-get update"

# 5. Install .NET 10 SDK
Write-Step "Installing .NET 10 SDK..."

# Check if .NET is already installed
$dotnetCheck = ssh -i $SSHKeyPath `
    -o StrictHostKeyChecking=no `
    -o BatchMode=yes `
    "$VMAdminUser@$script:IPAddress" "dotnet --version 2>/dev/null"

if ($LASTEXITCODE -eq 0) {
    Write-Info ".NET already installed: $dotnetCheck"
} else {
    # Add Microsoft package repository for Ubuntu 24.04
    Invoke-SSHCommand `
        -Command "wget https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb && sudo dpkg -i packages-microsoft-prod.deb && rm packages-microsoft-prod.deb" `
        -Description "Add Microsoft package repository"

    Invoke-SSHCommand `
        -Command "sudo apt-get install -y dotnet-sdk-10.0" `
        -Description "Install .NET 10 SDK"

    Write-Success ".NET 10 SDK installed"
}

# 6. Clone or update repository
Write-Step "Deploying application code..."

# Check if repo already exists
$repoCheck = ssh -i $SSHKeyPath -o StrictHostKeyChecking=no -o BatchMode=yes "$VMAdminUser@$script:IPAddress" "test -d $AppDirectory && echo exists"
    # By configuring no, it does not ask to verify if it's the correct server
    # By configuring yes, it does not pop up the password input screen
    # so that it only authenticate with SSH key -> essential for script automation

if ($repoCheck -eq "exists") {
    # Pull latest changes if repo already cloned
    Write-Info "Repository already exists. Pulling latest changes..."
    Invoke-SSHCommand `
        -Command "cd $AppDirectory && git pull origin main" `
        -Description "git pull"
} else {
    # Fresh clone into $AppDirectory
    Invoke-SSHCommand `
        -Command "git clone $RepoUrl $AppDirectory" `
        -Description "git clone"
}

Write-Success "Application code deployed to $AppDirectory"

# 7. Build and publish application
# .csproj is inside BombermanServer/ subdirectory
Write-Step "Building application..."

Invoke-SSHCommand `
    -Command "cd $ProjectDir && dotnet publish -c Release -o $PublishDir" `
    -Description "dotnet publish"

Write-Success "Application built: $PublishDir"


# 8. Register as systemd service 
Write-Step "Registering systemd service: $ServiceName"

# Create systemd service unit file
# After=network.target: ensures network is up before starting
# Restart=always: auto-restart on crash
# ASPNETCORE_URLS: binds the server to port 5000 on all interfaces
$serviceDefinition = "[Unit]
Description=Bomberman SignalR Game Server
After=network.target

[Service]
WorkingDirectory=$PublishDir
ExecStart=/usr/bin/dotnet $PublishDir/BombermanServer.dll
Restart=always
RestartSec=10
User=azureuser
Environment=ASPNETCORE_URLS=http://0.0.0.0:$SignalRPort
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target"

# Write service file to VM via SSH
Invoke-SSHCommand `
    -Command "echo '$serviceDefinition' | sudo tee /etc/systemd/system/$ServiceName.service > /dev/null" `
    -Description "Create systemd service file"

# Reload systemd daemon and enable + start the service
Invoke-SSHCommand `
    -Command "sudo systemctl daemon-reload && sudo systemctl enable $ServiceName && sudo systemctl start $ServiceName" `
    -Description "Enable and start service"

Write-Success "Systemd service registered and started"

# 9. Verify service is running
Write-Step "Verifying service status..."

Invoke-SSHCommand `
    -Command "sudo systemctl status $ServiceName --no-pager" `
    -Description "Check service status"

# 10. Health check 
Write-Step "Running health check on port $SignalRPort..."

# Wait for service to fully initialize
Start-Sleep -Seconds 5

Invoke-SSHCommand `
    -Command "curl -s -o /dev/null -w '%{http_code}' http://localhost:$SignalRPort || echo 'Service not responding yet'" `
    -Description "HTTP health check"

# 11. Deployment Summary 
Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Deployment Summary" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Environment   : $Environment"
Write-Host "  VM Public IP  : $script:IPAddress"
Write-Host "  SignalR Port  : $SignalRPort"
Write-Host "  Service       : $ServiceName"
Write-Host "  App Directory : $ProjectDir"
Write-Host "  WebSocket URL : ws://$($script:IPAddress):$SignalRPort"
Write-Host "============================================`n" -ForegroundColor Magenta
