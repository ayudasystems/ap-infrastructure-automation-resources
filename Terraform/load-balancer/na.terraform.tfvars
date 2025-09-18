# terraform apply -var-file="na.terraform.tfvars"

location                     = "northcentralus"
load_balancer_name           = "ayudacloud-na-lb"
resource_group_name          = "ayudacloud-na-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudacloud-na-lb"
network_interface_name_1     = "ayudacloud-tm-na-01476"
network_interface_name_2     = "ayudacloud-tm-na-02748"
