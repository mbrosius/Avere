terraform {
  required_version = ">= 1.4.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.60.0"
    }
  }
  backend "azurerm" {
    key = "8.Artist.Workstation"
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}

module "global" {
  source = "../0.Global.Foundation/module"
}

variable "resourceGroupName" {
  type = string
}

variable "virtualMachines" {
  type = list(object(
    {
      name = string
      machine = object(
        {
          size = string
          image = object(
            {
              id = string
              plan = object(
                {
                  publisher = string
                  product   = string
                  name      = string
                }
              )
            }
          )
        }
      )
      network = object(
        {
          enableAcceleration = bool
        }
      )
      operatingSystem = object(
        {
          type = string
          disk = object(
            {
              storageType = string
              cachingType = string
              sizeGB      = number
            }
          )
        }
      )
      adminLogin = object(
        {
          userName     = string
          userPassword = string
          sshPublicKey = string
          passwordAuth = object(
            {
              disable = bool
            }
          )
        }
      )
      customExtension = object(
        {
          enable   = bool
          name     = string
          fileName = string
          parameters = object(
            {
              fileSystemMounts = list(object(
                {
                  enable = bool
                  mount  = string
                }
              ))
              teradiciLicenseKey = string
            }
          )
        }
      )
      monitorExtension = object(
        {
          enable = bool
        }
      )
    }
  ))
}

variable "serviceAccount" {
  type = object(
    {
      name     = string
      password = string
    }
  )
}

variable "trafficManager" {
  type = object(
    {
      profile = object(
        {
          name              = string
          routingMethod     = string
          enableTrafficView = bool
        }
      )
      dns = object(
        {
          name = string
          ttl  = string
        }
      )
    }
  )
}

variable "computeNetwork" {
  type = object(
    {
      name              = string
      subnetName        = string
      resourceGroupName = string
    }
  )
}

data "azurerm_user_assigned_identity" "studio" {
  name                = module.global.managedIdentity.name
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault" "studio" {
  count               = module.global.keyVault.name != "" ? 1 : 0
  name                = module.global.keyVault.name
  resource_group_name = module.global.resourceGroupName
}

data "azurerm_key_vault_secret" "admin_username" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.adminUsername
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_key_vault_secret" "admin_password" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.adminPassword
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_key_vault_secret" "service_password" {
  count        = module.global.keyVault.name != "" ? 1 : 0
  name         = module.global.keyVault.secretName.servicePassword
  key_vault_id = data.azurerm_key_vault.studio[0].id
}

data "azurerm_log_analytics_workspace" "monitor" {
  count               = module.global.monitor.name != "" ? 1 : 0
  name                = module.global.monitor.name
  resource_group_name = module.global.resourceGroupName
}

data "terraform_remote_state" "network" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.rootStorage.accountName
    container_name       = module.global.rootStorage.containerName.terraform
    key                  = "1.Virtual.Network"
  }
}

data "terraform_remote_state" "image" {
  backend = "azurerm"
  config = {
    resource_group_name  = module.global.resourceGroupName
    storage_account_name = module.global.rootStorage.accountName
    container_name       = module.global.rootStorage.containerName.terraform
    key                  = "3.Image.Builder"
  }
}

data "azurerm_virtual_network" "compute" {
  name                = !local.stateExistsNetwork ? var.computeNetwork.name : data.terraform_remote_state.network.outputs.computeNetwork.name
  resource_group_name = !local.stateExistsNetwork ? var.computeNetwork.resourceGroupName : data.terraform_remote_state.network.outputs.resourceGroupName
}

data "azurerm_subnet" "workstation" {
  name                 = !local.stateExistsNetwork ? var.computeNetwork.subnetName : data.terraform_remote_state.network.outputs.computeNetwork.subnets[data.terraform_remote_state.network.outputs.computeNetwork.subnetIndex.workstation].name
  resource_group_name  = data.azurerm_virtual_network.compute.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.compute.name
}

locals {
  stateExistsNetwork = var.computeNetwork.name != "" ? false : try(length(data.terraform_remote_state.network.outputs) > 0, false)
  virtualMachinesLinux = [
    for virtualMachine in var.virtualMachines : merge(virtualMachine, {
      machine = {
        size = virtualMachine.machine.size
        image = {
          id = virtualMachine.machine.image.id
          plan = {
            publisher = lower(virtualMachine.machine.image.plan.publisher != "" ? virtualMachine.machine.image.plan.publisher : try(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].publisher, ""))
            product   = lower(virtualMachine.machine.image.plan.product != "" ? virtualMachine.machine.image.plan.product : try(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].offer, ""))
            name      = lower(virtualMachine.machine.image.plan.name != "" ? virtualMachine.machine.image.plan.name : try(data.terraform_remote_state.image.outputs.imageDefinitionsLinux[0].sku, ""))
          }
        }
      }
    }) if virtualMachine.name != "" && virtualMachine.operatingSystem.type == "Linux"
  ]
  serviceAccountPassword = var.serviceAccount.password != "" ? var.serviceAccount.password : data.azurerm_key_vault_secret.service_password[0].value
}

resource "azurerm_resource_group" "workstation" {
  name     = var.resourceGroupName
  location = module.global.regionNames[0]
}

resource "azurerm_network_interface" "workstation" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != ""
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.workstation.name
  location            = azurerm_resource_group.workstation.location
  ip_configuration {
    name                          = "ipConfig"
    subnet_id                     = data.azurerm_subnet.workstation.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.trafficManager.profile.name != "" ? azurerm_public_ip.workstation[each.value.name].id : null
  }
  enable_accelerated_networking = each.value.network.enableAcceleration
}

resource "azurerm_linux_virtual_machine" "workstation" {
  for_each = {
    for virtualMachine in local.virtualMachinesLinux : virtualMachine.name => virtualMachine
  }
  name                            = each.value.name
  resource_group_name             = azurerm_resource_group.workstation.name
  location                        = azurerm_resource_group.workstation.location
  size                            = each.value.machine.size
  source_image_id                 = each.value.machine.image.id
  admin_username                  = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_username[0].value : each.value.adminLogin.userName
  admin_password                  = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_password[0].value : each.value.adminLogin.userPassword
  disable_password_authentication = each.value.adminLogin.passwordAuth.disable
  network_interface_ids = [
    "${azurerm_resource_group.workstation.id}/providers/Microsoft.Network/networkInterfaces/${each.value.name}"
  ]
  os_disk {
    storage_account_type = each.value.operatingSystem.disk.storageType
    caching              = each.value.operatingSystem.disk.cachingType
    disk_size_gb         = each.value.operatingSystem.disk.sizeGB
  }
  identity {
    type = "UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.studio.id
    ]
  }
  dynamic plan {
    for_each = each.value.machine.image.plan.name != "" ? [1] : []
    content {
      publisher = each.value.machine.image.plan.publisher
      product   = each.value.machine.image.plan.product
      name      = each.value.machine.image.plan.name
    }
  }
  dynamic admin_ssh_key {
    for_each = each.value.adminLogin.sshPublicKey != "" ? [1] : []
    content {
      username   = each.value.adminLogin.userName
      public_key = each.value.adminLogin.sshPublicKey
    }
  }
  depends_on = [
    azurerm_network_interface.workstation
  ]
}

resource "azurerm_virtual_machine_extension" "initialize_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Linux"
  }
  name                       = each.value.customExtension.name
  type                       = "CustomScript"
  publisher                  = "Microsoft.Azure.Extensions"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.workstation.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    script = "${base64encode(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters, {
        renderManager          = module.global.renderManager
        serviceAccountName     = var.serviceAccount.name
        serviceAccountPassword = local.serviceAccountPassword
      }))
    )}"
  })
  depends_on = [
    azurerm_linux_virtual_machine.workstation
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_linux" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Linux" && module.global.monitor.name != ""
  }
  name                       = "Monitor"
  type                       = "AzureMonitorLinuxAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.21"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.workstation.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    workspaceId = data.azurerm_log_analytics_workspace.monitor[0].workspace_id
  })
  protected_settings = jsonencode({
    workspaceKey = data.azurerm_log_analytics_workspace.monitor[0].primary_shared_key
  })
  depends_on = [
    azurerm_linux_virtual_machine.workstation
  ]
}

resource "azurerm_windows_virtual_machine" "workstation" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.operatingSystem.type == "Windows"
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.workstation.name
  location            = azurerm_resource_group.workstation.location
  size                = each.value.machine.size
  source_image_id     = each.value.machine.image.id
  admin_username      = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_username[0].value : each.value.adminLogin.userName
  admin_password      = module.global.keyVault.name != "" ? data.azurerm_key_vault_secret.admin_password[0].value : each.value.adminLogin.userPassword
  custom_data         = base64encode(templatefile("../0.Global.Foundation/functions.ps1", {}))
  network_interface_ids = [
    "${azurerm_resource_group.workstation.id}/providers/Microsoft.Network/networkInterfaces/${each.value.name}"
  ]
  os_disk {
    storage_account_type = each.value.operatingSystem.disk.storageType
    caching              = each.value.operatingSystem.disk.cachingType
    disk_size_gb         = each.value.operatingSystem.disk.sizeGB
  }
  identity {
    type = "UserAssigned"
    identity_ids = [
      data.azurerm_user_assigned_identity.studio.id
    ]
  }
  depends_on = [
    azurerm_network_interface.workstation
  ]
}

resource "azurerm_virtual_machine_extension" "initialize_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.customExtension.enable && virtualMachine.operatingSystem.type == "Windows"
  }
  name                       = each.value.customExtension.name
  type                       = "CustomScriptExtension"
  publisher                  = "Microsoft.Compute"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.workstation.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    commandToExecute = "PowerShell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(
      templatefile(each.value.customExtension.fileName, merge(each.value.customExtension.parameters, {
        renderManager          = module.global.renderManager
        serviceAccountName     = var.serviceAccount.name
        serviceAccountPassword = local.serviceAccountPassword
      })), "UTF-16LE"
    )}"
  })
  depends_on = [
    azurerm_windows_virtual_machine.workstation
  ]
}

resource "azurerm_virtual_machine_extension" "monitor_windows" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if virtualMachine.name != "" && virtualMachine.monitorExtension.enable && virtualMachine.operatingSystem.type == "Windows" && module.global.monitor.name != ""
  }
  name                       = "Monitor"
  type                       = "AzureMonitorWindowsAgent"
  publisher                  = "Microsoft.Azure.Monitor"
  type_handler_version       = "1.7"
  auto_upgrade_minor_version = true
  virtual_machine_id         = "${azurerm_resource_group.workstation.id}/providers/Microsoft.Compute/virtualMachines/${each.value.name}"
  settings = jsonencode({
    workspaceId = data.azurerm_log_analytics_workspace.monitor[0].workspace_id
  })
  protected_settings = jsonencode({
    workspaceKey = data.azurerm_log_analytics_workspace.monitor[0].primary_shared_key
  })
  depends_on = [
    azurerm_windows_virtual_machine.workstation
  ]
}

###############################################################################################
# Traffic Manager (https://learn.microsoft.comazure/traffic-manager/traffic-manager-overview) #
###############################################################################################

resource "azurerm_traffic_manager_profile" "workstation" {
  count                  = var.trafficManager.profile.name != "" ? 1 : 0
  name                   = var.trafficManager.profile.name
  resource_group_name    = azurerm_resource_group.workstation.name
  traffic_routing_method = var.trafficManager.profile.routingMethod
  traffic_view_enabled   = var.trafficManager.profile.enableTrafficView
  dns_config {
    relative_name = var.trafficManager.dns.name
    ttl           = var.trafficManager.dns.ttl
  }
  monitor_config {
    protocol = "HTTP"
    port     = 80
    path     = "/"
  }
}

resource "azurerm_traffic_manager_external_endpoint" "workstation" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if var.trafficManager.profile.name != "" && virtualMachine.name != ""
  }
  name       = each.value.name
  target     = azurerm_public_ip.workstation[each.value.name].ip_address
  profile_id = azurerm_traffic_manager_profile.workstation[0].id
  depends_on = [
    azurerm_linux_virtual_machine.workstation,
    azurerm_windows_virtual_machine.workstation
  ]
}

resource "azurerm_public_ip" "workstation" {
  for_each = {
    for virtualMachine in var.virtualMachines : virtualMachine.name => virtualMachine if var.trafficManager.profile.name != "" && virtualMachine.name != ""
  }
  name                = each.value.name
  resource_group_name = azurerm_resource_group.workstation.name
  location            = azurerm_resource_group.workstation.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

output "resourceGroupName" {
  value = azurerm_resource_group.workstation.name
}

output "virtualMachines" {
  value = var.virtualMachines
}

output "trafficManager" {
  value = {
    fqdn = var.trafficManager.profile.name != "" ? azurerm_traffic_manager_profile.workstation[0].fqdn : ""
  }
}
