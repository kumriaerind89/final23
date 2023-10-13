terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.75.0"
    }
  }
}

provider "azurerm" {
  features {}
}
variable "admin" {
  description = "Admin username for VM"
  type        = string
}

variable "pass" {
  description = "Admin password for VM"
  type        = string
}

variable "vm_ip" {
  description = "Static IP addresses for VMs"
  type        = list(string)
}

variable "vnet_address_space" {
  description = "Address space for virtual network"
  type        = list(string)
}

variable "subnet_address_prefix" {
  description = "Address prefixes for subnet"
  type        = list(string)
}

resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "East US"
}

resource "azurerm_virtual_network" "example" {
  name                = "example-vnet"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = var.vnet_address_space
}

resource "azurerm_subnet" "example" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = var.subnet_address_prefix
}

resource "azurerm_network_security_group" "example" {
  name                = "example-nsg"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389-3391"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "example" {
  subnet_id                 = azurerm_subnet.example.id
  network_security_group_id = azurerm_network_security_group.example.id
}

resource "azurerm_windows_virtual_machine" "example" {
  count                 = length(var.vm_ip)
  name                  = "example-vm${count.index}"
  resource_group_name   = azurerm_resource_group.example.name
  location              = azurerm_resource_group.example.location
  size                  = "Standard_DS1_v2"
  admin_username        = var.admin
  admin_password        = var.pass
  network_interface_ids = [azurerm_network_interface.example[count.index].id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_network_interface" "example" {
  count               = length(var.vm_ip)
  name                = "example-nic${count.index}"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Static"
    private_ip_address = var.vm_ip[count.index]
    
  }
}

# ... Load balancer and NAT rules go here ...

# ... Previous code ...

resource "azurerm_lb" "example" {
  name                = "example-lb"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name

  frontend_ip_configuration {
    name                 = "privateIPAddress"
    private_ip_address   = "192.168.1.4"
    private_ip_address_version = "IPv4"
    subnet_id            = azurerm_subnet.example.id
  }
}

resource "azurerm_lb_backend_address_pool" "example" {
  loadbalancer_id     = azurerm_lb.example.id
  name                = "backendAddressPool"
}

resource "azurerm_lb_probe" "example" {
  loadbalancer_id     = azurerm_lb.example.id
  name                = "healthProbe"
  port                = 3389
  protocol            = "Tcp"
}

resource "azurerm_lb_nat_rule" "example" {
  count               = 3
  resource_group_name = azurerm_resource_group.example.name
  loadbalancer_id     = azurerm_lb.example.id
  name                = "natRule${count.index}"
  
  protocol            = "Tcp"
  frontend_port       = 3389 + count.index
  backend_port        = 3389
  frontend_ip_configuration_name = "privateIPAddress"
}

resource "azurerm_network_interface_backend_address_pool_association" "example" {
  network_interface_id    = azurerm_network_interface.example[0].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.example.id
}

# ... (The beginning part remains unchanged)

# Public IP Address
resource "azurerm_public_ip" "example" {
  name                = "example-public-ip"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Public Load Balancer with Frontend IP Configuration using the Public IP
resource "azurerm_lb" "public" {
  name                = "example-public-lb"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
    sku                 = "Standard" # <-- Make sure to set this to Standard

  frontend_ip_configuration {
    name                 = "publicIPAddress"
    public_ip_address_id = azurerm_public_ip.example.id
  }
}

# NAT Rules on the Public Load Balancer for RDP access
resource "azurerm_lb_nat_rule" "rdp" {
  count                          = 3
  resource_group_name            = azurerm_resource_group.example.name
  loadbalancer_id                = azurerm_lb.public.id
  name                           = "RDPAccessForVM${count.index}"
  protocol                       = "Tcp"
  frontend_port                  = 3389 + count.index
  backend_port                   = 3389
  frontend_ip_configuration_name = "publicIPAddress"
}