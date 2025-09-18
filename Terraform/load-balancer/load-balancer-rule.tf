resource "azurerm_lb_rule" "lbr1" {
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lbbap.id]
  backend_port                   = 80
  disable_outbound_snat          = false
  enable_floating_ip             = false
  enable_tcp_reset               = false
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  frontend_port                  = 80
  idle_timeout_in_minutes        = 4
  load_distribution              = "Default"
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "http"
  probe_id                       = azurerm_lb_probe.lbp.id
  protocol                       = "Tcp"
}

resource "azurerm_lb_rule" "lbr2" {
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.lbbap.id]
  backend_port                   = 443
  disable_outbound_snat          = false
  enable_floating_ip             = false
  enable_tcp_reset               = false
  frontend_ip_configuration_name = "LoadBalancerFrontEnd"
  frontend_port                  = 443
  idle_timeout_in_minutes        = var.idle_timeout_in_minutes
  load_distribution              = "Default"
  loadbalancer_id                = azurerm_lb.lb.id
  name                           = "https"
  probe_id                       = azurerm_lb_probe.lbp.id
  protocol                       = "Tcp"
}
