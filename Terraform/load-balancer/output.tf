# terraform/outputs.tf

# Verify the results
# Define an output value in output.tf file
# Execute the following command in a console
#   echo "$(terraform output resource_group_name)"

output "load_balancer_name" {
  value       = azurerm_lb.lb.name
  description = "Deployed Load Balancer name"
}
