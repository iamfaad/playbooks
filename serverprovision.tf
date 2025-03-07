terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.40"
    }
  }
}
 
provider "hcloud" {
  token = var.hcloud_token
}
 
# Variables
variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  sensitive   = true
}

variable "existing_ssh_key_id" {
  default     = 27802540  # Replace with your actual SSH key ID
  description = "Existing SSH Key ID in Hetzner" 
}

variable "server_type" {
  default     = "cpx11"
  description = "Server type for the instances"
}
 
variable "locations" {
  default     = ["nbg1", "fsn1", "hel1"] # Nuremberg, Falkenstein, Helsinki
  description = "Locations for the servers"
}
 
variable "image" {
  default     = "ubuntu-22.04"
  description = "Operating system image for the servers"
}
 

# Create a private network
resource "hcloud_network" "private_net" {
  name     = "private-network"
  ip_range = "10.0.0.0/16"
}
 
# Create a subnet for the private network
resource "hcloud_network_subnet" "private_subnet" {
  network_id   = hcloud_network.private_net.id
  type         = "cloud"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}
 
# Create 3 servers with public IPs for SSH access
resource "hcloud_server" "servers" {
  count       = length(var.locations)
  name        = "server-${count.index}"
  server_type = var.server_type
  location    = var.locations[count.index]
  image       = var.image
  ssh_keys    = [var.existing_ssh_key_id]
 
  # Enable public IPv4
  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }
 
  # Attach to private network
  network {
    network_id = hcloud_network.private_net.id
    ip         = "10.0.1.${count.index + 2}" # Assign static private IPs
  }
}
 
# Create a load balancer in the first location
resource "hcloud_load_balancer" "lb" {
  name               = "my-load-balancer"
  load_balancer_type = "lb11"
  location           = var.locations[0] # Load balancer placed in first region
}
 
# Attach Load Balancer to Private Network
resource "hcloud_load_balancer_network" "lb_network" {
  load_balancer_id = hcloud_load_balancer.lb.id
  network_id       = hcloud_network.private_net.id
}
 
# Attach the servers to the load balancer
resource "hcloud_load_balancer_target" "lb_targets" {
  count             = length(hcloud_server.servers)
  load_balancer_id  = hcloud_load_balancer.lb.id
  server_id         = hcloud_server.servers[count.index].id
  type              = "server"
  use_private_ip    = true
}
 
# Configure HTTP (Port 80) traffic on the load balancer
resource "hcloud_load_balancer_service" "http" {
  load_balancer_id = hcloud_load_balancer.lb.id
  protocol         = "tcp"
  listen_port      = 80
  destination_port = 22
}
 
# Output the Load Balancer public IP
output "load_balancer_ip" {
  value = hcloud_load_balancer.lb.ipv4
}
 
# Output the server public IPs for SSH access
output "server_public_ips" {
  value = hcloud_server.servers[*].ipv4_address
}
