resource "azurerm_lb_probe" "lbp" {
  interval_in_seconds = 5
  loadbalancer_id     = azurerm_lb.lb.id
  name                = "health"
  number_of_probes    = 2
  port                = 80
  probe_threshold     = 1
  protocol            = "Http"
  request_path        = "/health"
}
