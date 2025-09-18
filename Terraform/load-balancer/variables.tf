# terraform/variables.tf

variable "location" {
  type        = string
  description = "location of infrastructure"
}

variable "load_balancer_name" {
  type        = string
  description = "name of load balancer"
}

variable "resource_group_name" {
  type        = string
  description = "resource group name"
}

variable "idle_timeout_in_minutes" {
  type        = number
  description = "idle timeout in minutes of load balancer rule"
}

variable "public_ip_name_load_balancer" {
  type        = string
  description = "public ip name for load balance"
}

variable "network_interface_name_1" {
  type        = string
  description = "name of the first network interface"
}

variable "network_interface_name_2" {
  type        = string
  description = "name of the second network interface"
}

variable "azure_subscription_id" {
  type        = string
  description = "Azure Subscription Id"
}

variable "azure_subscription_tenant_id" {
  type        = string
  description = "Azure Tenant Id"
}

variable "service_principal_appid" {
  type        = string
  description = "Azure Service Principal App Id"
}

variable "service_principal_password" {
  type        = string
  description = "Azure Service Principal Password"
}
