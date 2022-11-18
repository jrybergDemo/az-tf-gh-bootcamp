resource "azurerm_resource_group" "list" {
  for_each = var.resource_groups

  name     = each.key
  location = each.value.location
}
