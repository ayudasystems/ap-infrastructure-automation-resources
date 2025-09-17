resource "azurerm_lb" "lb" {
  location            = var.location
  name                = var.load_balancer_name
  resource_group_name = var.resource_group_name
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = {}
  frontend_ip_configuration {
    name                          = "LoadBalancerFrontEnd"
    private_ip_address_allocation = "Dynamic"
    private_ip_address_version    = "IPv4"
    public_ip_address_id          = data.azurerm_public_ip.pilb.id
    zones                         = []
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_lock" "lock" {
  name       = "no-delete"
  scope      = azurerm_lb.lb.id
  lock_level = "CanNotDelete"
  notes      = ""
}
