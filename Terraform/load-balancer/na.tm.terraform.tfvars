# terraform apply -var-file="na.terraform.tfvars"

location                     = "northcentralus"
load_balancer_name           = "tm-cloud-na-lb"
resource_group_name          = "tm-cloud-na-rg"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "tm-cloud-na-ip"
network_interface_name_1     = "tm-cloud-na-01974"
network_interface_name_2     = "tm-cloud-na-02113"
