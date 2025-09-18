# terraform apply -var-file="na.terraform.tfvars"

location                     = "northcentralus"
load_balancer_name           = "ayudapreview-na-lb"
resource_group_name          = "ayudapreview-na-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudapreview-na-lb"
network_interface_name_1     = "ayudapreview-tm-na-0435"
network_interface_name_2     = "ayudapreview-tm-na-0727"
