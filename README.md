# Azure Network Provisioner & Validator

A portfolio project demonstrating end-to-end Azure network infrastructure automation using PowerShell, Python, and GitHub Actions CI/CD, culminating in a live multiplayer Bomberman game deployed across a two-VM architecture with HTTPS and WebSocket communication.

**Live Demo:** https://bomberman-slee.canadacentral.cloudapp.azure.com
(Might not work as Azure Student Account gets expired)

**Game Source:** https://github.com/shawn-lee0609/COMP_4945_Unity_Game

---

## Overview

This project automates the deployment and validation of Azure network infrastructure across multiple environments (dev / staging / prod). It provisions a segmented Virtual Network with security controls, validates the deployed state against a desired configuration, and generates an HTML drift detection report.

The infrastructure was put to use by deploying a real-time multiplayer Bomberman game: an ASP.NET Core SignalR server on the Backend VM, and a Unity WebGL client served via Nginx on the Frontend VM which is secured with HTTPS (Let's Encrypt) and connected through a reverse proxy.

---

## Architecture

```
                        Internet
                           │
                           ▼
              ┌────────────────────────┐
              │  Azure Public IP       │
              │  DNS: bomberman-slee.  │
              │  canadacentral.        │
              │  cloudapp.azure.com    │
              └────────────┬───────────┘
                           │
              ┌────────────▼───────────┐
              │  snet-frontend         │
              │  10.0.1.0/24           │
              │  NSG: Allow 80, 443    │
              │                        │
              │  vm-frontend-dev       │
              │  ├─ Nginx (HTTPS)      │
              │  ├─ Let's Encrypt SSL  │
              │  ├─ WebGL static files │
              │  └─ Reverse Proxy ─────┼──┐
              └────────────────────────┘  │
                                          │ proxy_pass (HTTP)
              ┌────────────────────────┐  │
              │  snet-backend          │  │
              │  10.0.2.0/24           │  │
              │  NSG: Allow Frontend   │  │
              │       + SignalR(5000)  │  │
              │  Route Table: default  │  │
              │    → Internet          │  │
              │                        │  │
              │  vm-backend-dev        │◄─┘
              │  └─ ASP.NET Core       │
              │     SignalR Hub (:5000) │
              └────────────────────────┘
```

**Request flow:**
1. Browser loads `https://bomberman-slee.canadacentral.cloudapp.azure.com` → Nginx serves Unity WebGL build (HTML/JS/WASM)
2. WebGL client opens `wss://bomberman-slee.../gamehub` → Nginx TLS-terminates and proxies to `http://vm-backend:5000/gamehub`
3. SignalR hub relays game events (join, move, bomb, explode) to all connected players via WebSocket

---

## Project Structure

```
azure-network-provisioner/
├── deploy/
│   ├── Deploy-Network.ps1       # VNet and Subnet provisioning
│   ├── Deploy-NSG.ps1           # NSG rules and subnet association
│   ├── Deploy-RouteTable.ps1    # Route Table with default internet route
|   |__ Deploy-FrontendVM.ps1    # Azure VM provisioning (Frontend - Game Client)
│   ├── Deploy-VM.ps1            # Azure VM provisioning (Backend - Game Server)
│   ├── Deploy-App.ps1           # Bomberman server deployment
│   └── Deploy-All.ps1           # Master orchestration script
├── validate/
│   ├── expected_config.json     # Desired state definition
│   ├── validator.py             # Azure SDK drift detection
│   ├── report_generator.py      # HTML validation report
│   └── requirements.txt         # Python dependencies
├── tests/
│   └── test_validator.py        # Unit tests (11/11 pass)
├── .github/workflows/
│   ├── ci.yml                   # Lint + test on every push
│   └── deploy.yml               # Manual deployment pipeline
├── docs/
│   └── architecture.md
└── README.md
```

---

## Technology Stack

| Category | Technology | Purpose |
|----------|-----------|---------|
| Infrastructure as Code | PowerShell (Az module) | Deploy Azure resources |
| Validation | Python 3.x (azure-mgmt-network) | Drift detection and reporting |
| CI/CD | GitHub Actions | Automated lint, test, deploy |
| Cloud Platform | Microsoft Azure | VNet, Subnet, NSG, Route Table, VM |
| Game Server | ASP.NET Core SignalR (C#) | Real-time multiplayer WebSocket hub |
| Game Client | Unity (C#) → WebGL build | Browser-based Bomberman game |
| Web Server | Nginx | Static file serving, HTTPS, reverse proxy |
| SSL/TLS | Let's Encrypt + Certbot | Free automated HTTPS certificates |
| Code Quality | PSScriptAnalyzer, flake8, pytest | Linting and unit testing |

---

## Getting Started

### Prerequisites

- PowerShell 7.x
- Python 3.11+
- Azure CLI
- Az PowerShell module
- Active Azure subscription

### Installation

```powershell
# Clone the repository
git clone https://github.com/shawn-lee0609/azure-network-provisioner.git
cd azure-network-provisioner

# Install Python dependencies
pip install -r validate/requirements.txt

# Install Az PowerShell module
Install-Module -Name Az -Scope CurrentUser -Force
```

### Deploy Infrastructure

```powershell
# Login to Azure
Connect-AzAccount

# Deploy all network resources to dev environment
.\deploy\Deploy-All.ps1 -Environment dev
```

### Validate Deployment

```powershell
# Set subscription ID
$env:AZURE_SUBSCRIPTION_ID = "<your-subscription-id>"

# Run validator
python validate/validator.py

# Generate HTML report
python validate/report_generator.py
```

---

## CI/CD Pipeline

### CI Pipeline (`ci.yml`)
Triggered on every push and pull request to `main`:

| Job | Tool | Target |
|-----|------|--------|
| lint-powershell | PSScriptAnalyzer | `deploy/*.ps1` |
| lint-python | flake8 | `validate/`, `tests/` |
| test-python | pytest | `tests/test_validator.py` |

### Deploy Pipeline (`deploy.yml`)
Manual trigger via GitHub Actions UI:

```
Actions → Deploy Pipeline → Run workflow → Select environment → Run
```

---

## Network Design

| Resource | Name (dev) | Address / Rule |
|----------|-----------|----------------|
| Resource Group | rg-network-dev | — |
| Virtual Network | vnet-main-dev | 10.0.0.0/16 |
| Frontend Subnet | snet-frontend | 10.0.1.0/24 |
| Backend Subnet | snet-backend | 10.0.2.0/24 |
| Frontend NSG | nsg-frontend-dev | Allow 80, 443 inbound |
| Backend NSG | nsg-backend-dev | Allow Frontend + SignalR(5000) |
| Route Table | rt-custom-dev | 0.0.0.0/0 → Internet |
| Frontend VM | vm-frontend-dev | Nginx + WebGL static files |
| Backend VM | vm-backend-dev | ASP.NET Core SignalR server |
| DNS Label | bomberman-slee | *.canadacentral.cloudapp.azure.com |

---

## Validation Results

The Python validator checks 17 properties across all deployed resources:

```
✅ rg-network-dev          — location
✅ vnet-main-dev           — address_space
✅ snet-frontend           — address_prefix, nsg_association
✅ snet-backend            — address_prefix, nsg_association, route_table_association
✅ nsg-frontend-dev        — Allow-HTTP (priority, port), Allow-HTTPS (priority, port)
✅ nsg-backend-dev         — Allow-From-Frontend (priority, port), Allow-SignalR (priority, port)
✅ rt-custom-dev           — route-default-internet (address_prefix, next_hop_type)

Total: 17/17 PASS
```

---

### Bomberman SignalR Deployment

The final phase deployed a real-time multiplayer Bomberman game across the provisioned Azure infrastructure, validating the network design with a live application.

### Game Server (Backend VM)

An ASP.NET Core SignalR hub runs on `vm-backend-dev` within `snet-backend`, listening on port 5000. The hub manages game state: player joins, host assignment, movement, bomb placement, explosions, deaths, and game-over conditions. All communication is broadcast via WebSocket to connected clients.

### Game Client (Frontend VM)

The Unity game was built as a WebGL application and deployed as static files on `vm-frontend-dev` within `snet-frontend`. Nginx serves the HTML, JavaScript, and WASM files with proper `Content-Encoding: gzip` headers for Unity's compressed build output.

### HTTPS with Let's Encrypt

SSL was configured using Certbot with the Nginx plugin. The Azure Public IP was assigned a DNS label (`bomberman-slee.canadacentral.cloudapp.azure.com`), which Let's Encrypt validated via HTTP-01 challenge to issue a certificate. Certbot automatically configured Nginx with the SSL certificate and an HTTP-to-HTTPS redirect. A systemd timer handles automatic certificate renewal before the 90-day expiry.

### Nginx Reverse Proxy

Rather than exposing the Backend VM directly to the internet (which would cause mixed-content issues with HTTPS), Nginx on the Frontend VM acts as a reverse proxy for SignalR traffic:

```
Browser (wss://) → Nginx (:443, TLS termination) → Backend VM (:5000, HTTP)
```

The `/gamehub` location block forwards requests to the Backend VM with WebSocket upgrade headers (`Upgrade`, `Connection`), preserving the persistent connection required by SignalR. This eliminates CORS issues since the browser communicates with a single origin, and the Backend VM never needs its own SSL certificate.

### Networking Pattern — Interface-Based Transport Swap

The Bomberman game uses an `INetworkComm` interface that abstracts the transport layer. Three implementations exist:

| Implementation | Transport | Use Case |
|---|---|---|
| `MulticastComm` | UDP Multicast | LAN play (original) |
| `SignalRComm` | SignalR / WebSocket | Desktop builds over WAN |
| `SignalRCommWebGL` | SignalR via JS bridge | WebGL browser builds |

Switching between transports requires changing a single line in `GameController.cs` — the game logic is completely decoupled from the networking layer through polymorphism. The WebGL implementation required a JavaScript bridge (`.jslib`) because Unity's WebGL build runs in a browser sandbox where raw C# `HubConnection` is not available; instead, the SignalR JavaScript client library is loaded from CDN and communicates with the C# game logic via Unity's `SendMessage` interop.

---

## Known Constraints

Azure for Students accounts do not have Entra ID permissions to create Service Principals.
In a production environment, `deploy.yml` would use `azure/login@v2` with a Contributor-role
Service Principal stored in GitHub Secrets (`AZURE_CREDENTIALS`, `AZURE_SUBSCRIPTION_ID`).

See **Service Principal Setup** section below for full configuration steps.

---

## Service Principal Setup (Free Azure Account)

To enable full CI/CD deployment via GitHub Actions, follow these steps using a free Azure account:

### 1. Create Free Azure Account
Sign up at https://azure.microsoft.com/free

### 2. Create Service Principal

```bash
az login

az ad sp create-for-rbac \
    --name "github-actions-deployer" \
    --role contributor \
    --scopes /subscriptions/<your-subscription-id> \
    --sdk-auth
```

Copy the JSON output. It looks like this:

```json
{
  "clientId": "...",
  "clientSecret": "...",
  "subscriptionId": "...",
  "tenantId": "..."
}
```

### 3. Add GitHub Secrets

```
GitHub repo → Settings → Secrets and variables → Actions → New repository secret
```

| Secret Name | Value |
|-------------|-------|
| `AZURE_CREDENTIALS` | Full JSON from step 2 |
| `AZURE_SUBSCRIPTION_ID` | Your subscription ID |

### 4. Restore deploy.yml

Replace the dry-run steps with real Azure login and deployment:

```yaml
      - name: Login to Azure
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Run Deploy-All.ps1
        shell: pwsh
        run: |
          .\deploy\Deploy-All.ps1 -Environment ${{ github.event.inputs.environment }}
```

---

## Author

**Shawn Lee**
BCIT Computer Systems Technology