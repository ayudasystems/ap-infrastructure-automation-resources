# terraform/resource-group.tf

# Import a previous created resource groups
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}
