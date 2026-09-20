resource "azurerm_route_table" "custom" {
  name                = "rt-custom-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # UDR (User-Defined Route). Currently identical to Azure's default system route.
  # Can be extended later by setting next_hop_type = "VirtualAppliance" to force
  # outbound traffic through a firewall/NVA for inspection.
  route {
    name           = "route-default-internet"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

resource "azurerm_subnet_route_table_association" "backend" {
  subnet_id      = azurerm_subnet.backend.id
  route_table_id = azurerm_route_table.custom.id
}