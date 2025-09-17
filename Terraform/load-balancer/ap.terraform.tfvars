# terraform apply -var-file="ap.terraform.tfvars"

location                     = "australiaeast"
load_balancer_name           = "ayudacloud-ap-lb"
resource_group_name          = "ayudacloud-ap-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudacloud-ap-lb"
network_interface_name_1     = "ayudacloud-tm-ap-01944"
network_interface_name_2     = "ayudacloud-tm-ap-02101"
