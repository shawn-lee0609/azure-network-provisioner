# NSG for frontend
resource "azurerm_network_security_group" "frontend" {
  name                = "nsg-frontend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name


  # Nested blocks of srcurity rule
  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

# Associating the NSG with a subnet.
#
# ".id" is an ATTRIBUTE, not an argument:
#   - Argument : a field the user sets in code (e.g. name = "...").
#   - Attribute: a value Azure assigns when it creates the resource.
#                The user cannot set it, it can only be referenced.
#
# Because ".id" is unknown until apply time ("known after apply"),
# referencing it forces an order: Terraform knows the subnet and the NSG
# must be created "FIRST", and only then can this association be made.

# This replaces the PowerShell "edit-in-memory then Set-AzVirtualNetwork
# commit" two-step, Terraform derives the ordering automatically.

resource "azurerm_subnet_network_security_group_association" "frontend" {
  subnet_id                 = azurerm_subnet.frontend.id
  network_security_group_id = azurerm_network_security_group.frontend.id
}



# NSG for backend
resource "azurerm_network_security_group" "backend" {
  name                = "nsg-backend-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # The 5000 port only allows the traffic coming from frontend subnet.
  security_rule {
    name                       = "Allow-Frontend-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-SSH-Temp"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "154.20.6.156"   
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "backend" {
  subnet_id                 = azurerm_subnet.backend.id
  network_security_group_id = azurerm_network_security_group.backend.id
}