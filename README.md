# Azure Network Provisioner & Validator

A portfolio project demonstrating end-to-end Azure network infrastructure automation. Originally built with **PowerShell** and later re-implemented as **declarative Terraform (IaC)**, culminating in a live multiplayer Bomberman game deployed across a two-VM architecture with HTTPS and WebSocket communication.

**Live Demo:** https://bomberman-slee.canadacentral.cloudapp.azure.com
(Might not work as Azure Student Account gets expired)

**Game Source:** https://github.com/shawn-lee0609/COMP_4945_Unity_Game

---

## Overview

This project automates the deployment and validation of Azure network infrastructure across multiple environments (dev / staging / prod). It provisions a segmented Virtual Network with security controls, validates the deployed state against a desired configuration, and generates an HTML drift detection report.

The provisioning layer exists in **two implementations**: an original **imperative PowerShell** version (Az module) and a **declarative Terraform** re-implementation (azurerm provider). The Terraform migration models the network and compute as version-controlled infrastructure-as-code, and automates in-VM application setup with **cloud-init** — so a single `terraform apply` provisions the infrastructure *and* deploys the running game server.

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

The entire topology above is defined as code, first in PowerShell, now in Terraform, and the backend application layer is provisioned automatically on VM first boot via cloud-init.

**Request flow:**
1. Browser loads `https://bomberman-slee.canadacentral.cloudapp.azure.com` → Nginx serves Unity WebGL build (HTML/JS/WASM)
2. WebGL client opens `wss://bomberman-slee.../gamehub` → Nginx TLS-terminates and proxies to `http://vm-backend:5000/gamehub`
3. SignalR hub relays game events (join, move, bomb, explode) to all connected players via WebSocket

---

## Infrastructure as Code: PowerShell → Terraform

The provisioning layer was first written in imperative PowerShell, then re-implemented in declarative Terraform. Both live in the repo so the evolution is visible in the commit history.

### Why migrate

| | PowerShell (Az module) | Terraform (azurerm) |
|---|---|---|
| Paradigm | Imperative — scripted create/check steps | Declarative — desired end state |
| Idempotency | Hand-coded `Get-Az*` existence checks | State-tracked automatically |
| Ordering | Managed manually in script order | Derived from a dependency graph |
| Preview | None (run to find out) | `terraform plan` dry-run |
| App deploy | Manual SSH (`Deploy-App.ps1`) | cloud-init on first boot |
| Run | Multiple scripts, in sequence | Single `terraform apply` |

### What Terraform models

Every resource the PowerShell scripts created is expressed as an `azurerm` resource, split by layer for readability (Terraform merges all `.tf` files and resolves ordering from references):

- **network.tf** — Resource Group, VNet (`10.0.0.0/16`), frontend/backend subnets
- **nsg.tf** — Frontend NSG (Allow 80/443 from Internet) and Backend NSG (Allow 5000 from the frontend subnet only), each associated to its subnet
- **route_table.tf** — Custom route table (`0.0.0.0/0 → Internet`) associated to the backend subnet
- **compute.tf** — Public IPs, NICs, and Linux VMs for backend and frontend, using SSH key-only authentication (no password in source)
- **cloud-init-backend.yaml** — first-boot provisioning script (see below)
- **outputs.tf** — exports the backend/frontend public IPs

Environment (`dev` / `staging` / `prod`), region, and subscription are `variables`, so the same code deploys to any environment or region by changing a value — not the code.

### Automated app deployment with cloud-init

The manual, SSH-based `Deploy-App.ps1` was replaced by a cloud-init script passed to the backend VM via `custom_data`. On the VM's first boot it runs entirely on-box, no outbound SSH, and:

1. Installs the **.NET 10 SDK** (Microsoft apt repository)
2. Clones the **BombermanServer** repository
3. Runs `dotnet publish -c Release`
4. Registers the server as a **systemd service** (`Restart=always`, enabled at boot), bound to `0.0.0.0:5000`

The result: `terraform apply` alone brings up the network, the VMs, and a running game server registered under systemd, surviving crashes and reboots.

### Provider version pinning

The `azurerm` provider is version-pinned in `providers.tf` and `.terraform.lock.hcl` is committed, so every machine uses the same provider version. This was a deliberate response to a regression encountered on an unpinned upgrade, pinning guarantees reproducible plans.

### Migration status

- ✅ Network layer (VNet, subnets, NSGs, route table): fully IaC
- ✅ Compute (Public IPs, NICs, both VMs, SSH keys): fully IaC
- ✅ Backend application (.NET runtime, build, systemd service): automated via cloud-init
- 🔲 Frontend application layer (Nginx, WebGL static files, Let's Encrypt HTTPS, reverse proxy): provisioned as a bare VM today; cloud-init automation of this layer is the next step (it was configured manually in the original deployment)

---

## Project Structure

```
azure-network-provisioner/
├── terraform/                   # Declarative IaC (azurerm) — current
│   ├── providers.tf             # Provider config + version pinning
│   ├── variables.tf             # environment, location, subscription_id
│   ├── terraform.tfvars         # Variable values (gitignored — subscription_id)
│   ├── network.tf               # Resource Group, VNet, subnets
│   ├── nsg.tf                   # NSGs, rules, subnet associations
│   ├── route_table.tf           # Route table + backend association
│   ├── compute.tf               # Public IPs, NICs, Linux VMs
│   ├── cloud-init-backend.yaml  # First-boot app provisioning (replaces Deploy-App.ps1)
│   └── outputs.tf               # Public IP outputs
├── deploy/                      # Imperative PowerShell (Az module) — original
│   ├── Deploy-Network.ps1       # VNet and Subnet provisioning
│   ├── Deploy-NSG.ps1           # NSG rules and subnet association
│   ├── Deploy-RouteTable.ps1    # Route Table with default internet route
│   ├── Deploy-FrontendVM.ps1    # Azure VM provisioning (Frontend - Game Client)
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
| Infrastructure as Code | Terraform (azurerm) | Declarative resource provisioning (current) |
| Infrastructure as Code | PowerShell (Az module) | Imperative resource provisioning (original) |
| Config Management | cloud-init | Automated first-boot app deployment (backend) |
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

- Terraform >= 1.5
- Azure CLI (for Terraform authentication)
- PowerShell 7.x + Az module (for the original scripts)
- Python 3.11+
- Active Azure subscription

### Installation

```bash
# Clone the repository
git clone https://github.com/shawn-lee0609/azure-network-provisioner.git
cd azure-network-provisioner

# Install Python dependencies (for the validator)
pip install -r validate/requirements.txt
```

### Deploy Infrastructure — Terraform (current)

```bash
# Authenticate (Terraform uses the Azure CLI login)
az login
az account set --subscription "<your-subscription-id>"

cd terraform

# Provide the subscription id (terraform.tfvars is gitignored)
echo 'subscription_id = "<your-subscription-id>"' > terraform.tfvars

terraform init
terraform plan        # preview
terraform apply       # provision network + VMs + backend app (cloud-init)

# Public IPs are printed as outputs; tear down with:
terraform destroy
```

> New Azure subscriptions may need a VM family quota increase and a region/size with available capacity. Region and VM size are set via `var.location` and the `size` argument in `compute.tf`.

### Deploy Infrastructure — PowerShell (original)

```powershell
Connect-AzAccount
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

An ASP.NET Core SignalR hub runs on `vm-backend-dev` within `snet-backend`, listening on port 5000. The hub manages game state: player joins, host assignment, movement, bomb placement, explosions, deaths, and game-over conditions. All communication is broadcast via WebSocket to connected clients. In the Terraform deployment, the entire server setup (runtime install, build, systemd service) is provisioned automatically by cloud-init on first boot.

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

Switching between transports requires changing a single line in `GameController.cs`, the game logic is completely decoupled from the networking layer through polymorphism. The WebGL implementation required a JavaScript bridge (`.jslib`) because Unity's WebGL build runs in a browser sandbox where raw C# `HubConnection` is not available; instead, the SignalR JavaScript client library is loaded from CDN and communicates with the C# game logic via Unity's `SendMessage` interop.

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