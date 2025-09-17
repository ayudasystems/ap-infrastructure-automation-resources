# terraform apply -var-file="eu.terraform.tfvars"

location                     = "northeurope"
load_balancer_name           = "ayudacloud-eu-lb"
resource_group_name          = "ayudacloud-eu-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudacloud-eu-lb"
network_interface_name_1     = "ayudacloud-tm-eu-01886"
network_interface_name_2     = "ayudacloud-tm-eu-02131"
