output "backend_public_ip" {
  value = azurerm_public_ip.backend.ip_address
}

output "frontend_public_ip" {
  value = azurerm_public_ip.frontend.ip_address
}