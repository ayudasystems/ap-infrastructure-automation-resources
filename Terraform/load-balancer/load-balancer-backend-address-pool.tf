resource "azurerm_lb_backend_address_pool" "lbbap" {
  loadbalancer_id = azurerm_lb.lb.id
  name            = "nginx"
}

resource "azurerm_network_interface_backend_address_pool_association" "nibapa1" {
  count                   = 1
  network_interface_id    = data.azurerm_network_interface.ni1.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lbbap.id
}

resource "azurerm_network_interface_backend_address_pool_association" "nibapa2" {
  count                   = 1
  network_interface_id    = data.azurerm_network_interface.ni2.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lbbap.id
}
