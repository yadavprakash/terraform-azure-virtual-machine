provider "azurerm" {
  features {}
}

locals {
  name        = "app"
  environment = "test"
}

module "resource_group" {
  source      = "git::https://github.com/yadavprakash/terraform-azure-resource-group.git?ref=v1.0.0"
  name        = local.name
  environment = local.environment
  location    = "Canada Central"
}

module "vnet" {
  source              = "git::https://github.com/yadavprakash/terraform-azure-vnet.git?ref=v1.0.0"
  name                = local.name
  environment         = local.environment
  resource_group_name = module.resource_group.resource_group_name
  location            = module.resource_group.resource_group_location
  address_spaces      = ["10.0.0.0/16"]
}

module "subnet" {
  source               = "git::https://github.com/yadavprakash/terraform-azure-subnet.git?ref=v1.0.1"
  name                 = local.name
  environment          = local.environment
  resource_group_name  = module.resource_group.resource_group_name
  location             = module.resource_group.resource_group_location
  virtual_network_name = join("", module.vnet[*].vnet_name)
  #subnet
  subnet_names    = ["subnet1"]
  subnet_prefixes = ["10.0.1.0/24"]
  # route_table
  enable_route_table = true
  route_table_name   = "default_subnet"
  routes = [
    {
      name           = "rt-test"
      address_prefix = "0.0.0.0/0"
      next_hop_type  = "Internet"
    }
  ]
}

module "network_security_group" {
  source                  = "git::https://github.com/yadavprakash/terraform-azure-network-security-group.git?ref=v1.0.0"
  name                    = local.name
  environment             = local.environment
  resource_group_name     = module.resource_group.resource_group_name
  resource_group_location = module.resource_group.resource_group_location
  subnet_ids              = module.subnet.subnet_id
  inbound_rules = [
    {
      name                       = "ssh"
      priority                   = 101
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "10.20.0.0/32"
      source_port_range          = "*"
      destination_address_prefix = "0.0.0.0/0"
      destination_port_range     = "22"
      description                = "ssh allowed port"
    },
    {
      name                       = "https"
      priority                   = 102
      access                     = "Allow"
      protocol                   = "*"
      source_address_prefix      = "VirtualNetwork"
      source_port_range          = "80,443,22"
      destination_address_prefix = "0.0.0.0/0"
      destination_port_range     = "22"
      description                = "ssh allowed port"
    }
  ]
}

module "vault" {
  depends_on                  = [module.vnet]
  source                      = "git::https://github.com/yadavprakash/terraform-azure-key-vault.git?ref=v1.0.0"
  name                        = local.name
  environment                 = local.environment
  sku_name                    = "standard"
  resource_group_name         = module.resource_group.resource_group_name
  subnet_id                   = module.subnet.subnet_id[0]
  virtual_network_id          = module.vnet.vnet_id
  enable_private_endpoint     = false
  enable_rbac_authorization   = true
  purge_protection_enabled    = true
  enabled_for_disk_encryption = false
  principal_id                = ["85555-2414-4a4c-abhi24-1289"]
  role_definition_name        = ["Key Vault Administrator"]

}


module "virtual-machine" {
  source = "../../"
  ## Tags
  name        = "app"
  environment = "test"
  label_order = ["environment", "name"]
  ## Common
  is_vm_linux                     = true
  enabled                         = true
  machine_count                   = 1
  resource_group_name             = module.resource_group.resource_group_name
  location                        = module.resource_group.resource_group_location
  disable_password_authentication = true
  ## Network Interface
  subnet_id                     = module.subnet.subnet_id
  private_ip_address_version    = "IPv4"
  private_ip_address_allocation = "Static"
  primary                       = true
  private_ip_addresses          = ["10.0.1.6"]
  #nsg
  network_interface_sg_enabled = true
  network_security_group_id    = module.network_security_group.id
  ## Availability Set
  availability_set_enabled     = true
  platform_update_domain_count = 7
  platform_fault_domain_count  = 3
  ## Public IP
  public_ip_enabled = true
  sku               = "Basic"
  allocation_method = "Static"
  ip_version        = "IPv4"
  ## Virtual Machine
  vm_size                         = "Standard_B1s"
  public_key                      = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCSYKCYgGWN4eKRHgP/RV6rfJWcE1p3m362P6SsAmR0n9IWnJLy9Bz/wAJgH+xh6Oma8o25eX2vtHB27MLjymasfjxePDUB1cinHd3Qh85+WZ+xqxU4hBABb1E+dhO7mIlX0EaZ1HW6lB58LMqcWpvD4HhchIH/Rzrl+hmBsW3UN2i1FGYyZuSkbinw8qlvhusTTIaf23++xJt7qPtsP5rz0bA7QeOCKBjp/NKqCChcqB/HO4PwpHF2lhMihZohYsTmB+HRVmwBa9uP+MbVg0j6FP68DJyALZOceoQBZx8v+S79eDsvePM3ghKdXUJBwwFmn161eQCBcBDRxttAb93pryyghHIp7LkqKtnskJsKyjKiSd+IiM8x7+p/8w8tOTertH17KJ5EW4WAWjvD5IjMlP7n8UUTvAX5n3etXp9USca5aXbL1zLXmen6uBRTf+AGeS1p8qxN/yHNusFLIBrJiVp71/7FFl4WVZKuS8RKJM89+QbzzA7+muAhQCrlj2s= sohan"
  admin_username                  = "ubuntu"
  admin_password                  = "P@ssw0rd!123!" # It is compulsory when disable_password_authentication = false
  caching                         = "ReadWrite"
  disk_size_gb                    = 30
  storage_image_reference_enabled = true
  image_publisher                 = "Canonical"
  image_offer                     = "0001-com-ubuntu-server-focal"
  image_sku                       = "20_04-lts"
  image_version                   = "latest"
  enable_disk_encryption_set      = true
  key_vault_id                    = module.vault.id
  addtional_capabilities_enabled  = true
  ultra_ssd_enabled               = false
  enable_encryption_at_host       = false
  key_vault_rbac_auth_enabled     = false
  data_disks = [
    {
      name                 = "disk1"
      disk_size_gb         = 100
      storage_account_type = "StandardSSD_LRS"
    }
  ]
  # Extension
  extensions = [{
    extension_publisher            = "Microsoft.Azure.Extensions"
    extension_name                 = "hostname"
    extension_type                 = "CustomScript"
    extension_type_handler_version = "2.0"
    auto_upgrade_minor_version     = true
    automatic_upgrade_enabled      = false
    settings                       = <<SETTINGS
    {
      "commandToExecute": "hostname && uptime"
     }
     SETTINGS
  }]
}
