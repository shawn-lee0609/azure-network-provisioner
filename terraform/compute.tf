# ------ Backend (game server) VM: networking ------
# Flow: Create IP and then NIC, after that attach the NIC to the VM.

resource "azurerm_public_ip" "backend" {
  name                = "pip-backend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static" # IP stays the same even when the VM is deallocated or restarted
  sku                 = "Standard"
}

# The NIC card defines which subnet the VM belongs to and which IP address it is using
# Public IP gets attached to NIC so that it can enable external connection.
resource "azurerm_network_interface" "backend" {
  name                = "nic-backend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Dynamic" # Auto-allocates an ip address within the range of private IP address in the subnet
    public_ip_address_id          = azurerm_public_ip.backend.id
  }
}

# VM congfig
resource "azurerm_linux_virtual_machine" "backend" {

  name                = "vm-backend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = "Standard_D2s_v7"
  admin_username      = "azureuser" # Admin account name: Use when to connect in SSH (ssh azureuser@<IP>)
  # The above created NIC card gets attached to the VM
  # The reason why it is written with [ ], is because one VM can have multiple NICs (list)
  network_interface_ids = [azurerm_network_interface.backend.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/azure-vm-key-nopass.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  # Pass the cloud-init script to the VM, runs once on first boot to install .NET,
  # deploy the game server, and register it as a systemd service (replaces Deploy-App.ps1).
  custom_data = base64encode(file("${path.module}/cloud-init-backend.yaml"))
}

# ------ Frontend (Nginx / Unity WebGL) VM ------

resource "azurerm_public_ip" "frontend" {
  name                = "pip-frontend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "frontend" {
  name                = "nic-frontend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.frontend.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.frontend.id
  }
}

resource "azurerm_linux_virtual_machine" "frontend" {
  name                  = "vm-frontend-${var.environment}"
  location              = azurerm_resource_group.main.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_D2s_v7"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.frontend.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/azure-vm-key-nopass.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

