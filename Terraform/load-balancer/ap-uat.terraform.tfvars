# terraform apply -var-file="ap.terraform.tfvars"

location                     = "australiaeast"
load_balancer_name           = "ayudapreview-ap-lb"
resource_group_name          = "ayudapreview-ap-01"
idle_timeout_in_minutes      = 4
public_ip_name_load_balancer = "ayudapreview-ap-lb"
network_interface_name_1     = "ayudapreview-tm-ap-0957"
network_interface_name_2     = "ayudapreview-tm-ap-0958"
