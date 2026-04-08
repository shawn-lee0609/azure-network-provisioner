<#
.SYNOPSIS
    Master deployment script that orchestrates the full network provisioning pipeline.

.DESCRIPTION
    Calls Deploy-Network.ps1, Deploy-NSG.ps1, and Deploy-RouteTable.ps1 in order.
    Each script is independently idempotent, safe to re-run at any time.
#>

# Parameters
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev"
)

# Configuration

# $PSScriptRoot = the directory where this script is located
# All child scripts are resolved relative to the path
$ScriptRoot = $PSScriptRoot

$Scripts = @(
    "$ScriptRoot\Deploy-Network.ps1",
    "$ScriptRoot\Deploy-NSG.ps1",
    "$ScriptRoot\Deploy-RouteTable.ps1"
)

# Helper Functions
function Write-Step {
    param([string]$Message)
    Write-Host "`n[STEP] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

# Main Orchestration Logic
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Azure Network Provisioner - Full Deploy  " -ForegroundColor Magenta
Write-Host "  Environment: $Environment                " -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta

# Record start time to calculate total deployment duration at the end
$startTime = Get-Date

# Iterate through each script and execute in order
foreach ($script in $Scripts) {

    $scriptName = Split-Path $script -Leaf
    # Split-Path -Leaf extracts just the filename from the full path
    # e.g. "C:\...\Deploy-Network.ps1" → "Deploy-Network.ps1"

    Write-Step "Running: $scriptName"

    # & operator invokes an external script or command
    # -Environment passes through the environment parameter to each child script
    & $script -Environment $Environment

    # $? checks if the last PowerShell command completed without errors
    # Exit code 0 = success, anything else = failure
    if (-not $?) {
        Write-Host "`n[ERROR] $scriptName failed. Aborting pipeline." -ForegroundColor Red
        exit 1
    }

    Write-Success "$scriptName completed successfully."
}

# Calculate and display total deployment duration
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "  Full Deployment Complete" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host "  Environment : $Environment"
Write-Host "  Duration    : $($duration.Minutes)m $($duration.Seconds)s"
Write-Host "  Scripts run : $($Scripts.Count)"
Write-Host "============================================`n" -ForegroundColor Magenta
