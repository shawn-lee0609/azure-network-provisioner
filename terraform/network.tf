# The "azurerm_[name of the resource]" is a type name which is already defined by the provider (azurerm)
# Following by the "main", this is like a nickname of how Terraform will call it internally.
# This information doesn't show in the Azure side

resource "azurerm_resource_group" "main" { # main is the nickname inside Terraform (azurerm_resource_group.main)
  name = "rg-network-${var.environment}"   # Apply the specified variable value from variables.tf (The final value)
  # and after applying the value, this would be the actual name in Azure. (What would actually show in the Azure portal)
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-main-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name # reference from the above nickname
  # This is how Terraform knows the dependency (Need RG first, implicit dependency)
  location      = azurerm_resource_group.main.location
  address_space = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "frontend" {
  name = "snet-frontend"
  # The argument name (the one in the left) is defined from the provider (azurerm provider)
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "snet-backend"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
}

