# terraform apply -var-file="eu.terraform.tfvars"

location                     = "northeurope"
load_balancer_name           = "ayudapreview-eu-lb"
resource_group_name          = "ayudapreview-eu-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudapreview-eu-lb"
network_interface_name_1     = "ayudapreview-tm-eu-0630"
network_interface_name_2     = "ayudapreview-tm-eu-0258"
