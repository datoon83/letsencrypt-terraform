provider "template" {
  version = "~> 1.0"
}

provider "azurerm" {
  version = "~> 1.17"
}

locals {
  resource_group = "letsencrypt"
  location = "northeurope"
  name = "nginx"
  virtual_machine_name = "${local.name}-vm1"
  email_address = "test@yourdomain.com"
  dns_record = "yourdomain.com"
  admin_username = ""
  ssh_key = ""
  backend_ip_address = ""
}

resource "azurerm_resource_group" "lets_encrypt" {
  name     = "${local.resource_group}"
  location = "${local.location}"
}

resource "azurerm_virtual_network" "vnet" {
  name = "letsEncrypt"
  address_space = ["10.0.0.0/18"]
  location = "${local.location}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
}

resource "azurerm_subnet" "subnet" {
  name = "encrypt"
  address_prefix = "10.0.1.0/28"
  virtual_network_name = "${azurerm_virtual_network.vnet.name}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
}

resource "azurerm_dns_zone" "vertical_software" {
  name = "vertical-software.co.uk"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
  zone_type = "Public"
}

resource "azurerm_dns_a_record" "test" {
  name = "${local.dns_record}"
  zone_name = "${azurerm_dns_zone.vertical_software.name}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
  ttl = 300
  records = [ "${azurerm_public_ip.nginx_public_ip.ip_address}" ]
}

resource "azurerm_public_ip" "nginx_public_ip" {
  name = "${local.virtual_machine_name}-pip"
  location = "${local.location}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
  sku = "Standard"
  allocation_method = "Static"
}

resource "azurerm_network_security_group" "nsg" {
  name = "${local.name}-nsg"
  location = "${local.location}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"

  security_rule = [
  {
    name = "HTTPS"
    priority = 100
    protocol = "TCP"
    direction = "Inbound"
    access = "Allow"
    source_port_range = "*"
    destination_port_ranges = ["80", "443"]
    source_address_prefix = "*"
    destination_address_prefix = "*"
  },
  {
    name = "SSH"
    priority = 200
    protocol = "TCP"
    direction = "Inbound"
    access = "Allow"
    source_port_range = "*"
    destination_port_ranges = ["22"]
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }
  ]
}

resource "azurerm_network_interface" "nic" {
  name = "${local.virtual_machine_name}-nic"
  location = "${local.location}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"
  network_security_group_id = "${azurerm_network_security_group.nsg.id}"

  ip_configuration {
    name = "ipconfig"
    subnet_id = "${azurerm_subnet.subnet.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id = "${azurerm_public_ip.nginx_public_ip.id}"
  }
}

resource "azurerm_virtual_machine" "nginx" {
  name = "${local.virtual_machine_name}"
  location = "${local.location}"
  resource_group_name = "${azurerm_resource_group.lets_encrypt.name}"

  delete_os_disk_on_termination = true
  delete_data_disks_on_termination = true

  network_interface_ids = ["${azurerm_network_interface.nic.id}"]
  vm_size = "Standard_B2s"

  storage_image_reference {
    publisher = "Canonical"
    offer = "UbuntuServer"
    sku = "18.04-LTS"
    version = "latest"
  }

  storage_os_disk {
    name = "${local.virtual_machine_name}-disk"
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name = "${local.virtual_machine_name}"
    admin_username = "${local.admin_username}"
    custom_data =  "${file("${path.module}/files/nginx.yaml")}"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = "${local.ssh_key}"
      path = "/home/${local.admin_username}/.ssh/authorized_keys"
    }
  }

  connection {
    type = "ssh"
    user = "${local.admin_username}"
    private_key = "${file("~/.ssh/azure.pem")}"
    host = "${azurerm_public_ip.nginx_public_ip.ip_address}"
  }

  provisioner "file" {
    content = "${data.template_file.nginx_config.rendered}"
    destination = "/tmp/nginx.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait",
      "sudo mv -f /tmp/nginx.conf /etc/nginx/nginx.conf",
      "sudo service nginx start",
      "sudo service nginx reload",
      "sleep 30s",
      "sudo certbot --nginx -n -d ${local.dns_record} --email ${local.email_address} --agree-tos --redirect --hsts",
      "sudo systemctl reboot"
    ]
  }
}

data "template_file" "nginx_config" {
  template = "${file("${path.module}/files/nginx.conf")}"

  vars {
    dns_name = "${local.dns_record}"
    backend_ip_address = "${local.backend_ip_address}"
  }
}