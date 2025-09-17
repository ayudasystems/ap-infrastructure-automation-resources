# terraform apply -var-file="na-ci.terraform.tfvars"

location                     = "northcentralus"
load_balancer_name           = "ayudalabs-na-lb"
resource_group_name          = "ayudalabs-na-01"
idle_timeout_in_minutes      = 30
public_ip_name_load_balancer = "ayudalabs-na-lb"
network_interface_name_1     = "ayudalabs-tm-na-01223"
network_interface_name_2     = "ayudalabs-tm-na-02320"
