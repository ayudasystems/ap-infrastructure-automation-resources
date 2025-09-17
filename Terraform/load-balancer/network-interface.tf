data "azurerm_network_interface" "ni1" {
  name                = var.network_interface_name_1
  resource_group_name = var.resource_group_name
}

data "azurerm_network_interface" "ni2" {
  name                = var.network_interface_name_2
  resource_group_name = var.resource_group_name
}
