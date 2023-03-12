#Generic Azure resources
data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "default" {
  count    = local.existing_resource_group ? 0 : 1
  name     = var.name
  location = local.region
}

resource "azurerm_virtual_network" "default" {
  count               = local.existing_ars_vnet ? 0 : 1
  name                = format("%s-ars-vnet", var.name)
  address_space       = [var.cidr]
  resource_group_name = local.resource_group_name
  location            = local.region
}

#Azure Route Server resources
resource "azurerm_subnet" "ars" {
  count                = local.existing_ars_subnet ? 0 : 1
  name                 = "RouteServerSubnet"
  virtual_network_name = local.ars_vnet_name.name
  resource_group_name  = local.resource_group_name
  address_prefixes     = length(var.route_server_subnet) > 0 ? [var.route_server_subnet] : [cidrsubnet(var.cidr, 1, 1)]
}

resource "azurerm_public_ip" "ars" {
  name                = format("%s-ars-pip", var.name)
  resource_group_name = local.resource_group_name
  location            = local.region
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_route_server" "default" {
  name                             = format("%s-ars", var.name)
  resource_group_name              = local.resource_group_name
  location                         = local.region
  sku                              = "Standard"
  public_ip_address_id             = azurerm_public_ip.ars.id
  subnet_id                        = local.ars_subnet_id
  branch_to_branch_traffic_enabled = true
}

#VNG Resources
resource "azurerm_public_ip" "vng" {
  count               = var.enable_vng_deployment ? 1 : 0
  name                = format("%s-vng-pip", var.name)
  resource_group_name = local.resource_group_name
  location            = local.region
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_subnet" "vng" {
  count                = var.enable_vng_deployment ? 1 : 0
  name                 = "GatewaySubnet"
  virtual_network_name = local.ars_vnet_name.name
  resource_group_name  = local.resource_group_name
  address_prefixes     = length(var.vng_subnet) > 0 ? [var.vng_subnet] : [cidrsubnet(var.cidr, 1, 0)]
}

resource "azurerm_virtual_network_gateway" "default" {
  count               = var.enable_vng_deployment ? 1 : 0
  name                = format("%s-vng", var.name)
  location            = local.region
  resource_group_name = local.resource_group_name

  type = "ExpressRoute"
  sku  = var.vng_sku

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vng[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.vng[0].id
  }
}

#Connectivity to Aviatrix transit
resource "azurerm_virtual_network_peering" "default-1" {
  name                      = format("%s-peertransittoars", var.name)
  resource_group_name       = local.transit_resource_group
  virtual_network_name      = local.transit_vnet_name
  remote_virtual_network_id = local.ars_vnet_name.id
  use_remote_gateways       = true
}

resource "azurerm_virtual_network_peering" "default-2" {
  name                      = format("%s-peerarstotransit", var.name)
  resource_group_name       = local.resource_group_name
  virtual_network_name      = local.ars_vnet_name.name
  remote_virtual_network_id = local.transit_resource_group_id
  allow_gateway_transit     = true
}

resource "azurerm_route_server_bgp_connection" "transit_gw" {
  count           = var.enable_bgp_peering ? 1 : 0
  name            = format("%s-transit_gw", var.name)
  route_server_id = azurerm_route_server.default.id
  peer_asn        = local.transit_as_number
  peer_ip         = local.bgp_lan_ip_list[var.lan_interface_index]
}

resource "azurerm_route_server_bgp_connection" "transit_hagw" {
  count           = var.enable_bgp_peering ? 1 : 0
  name            = format("%s-transit_hagw", var.name)
  route_server_id = azurerm_route_server.default.id
  peer_asn        = local.transit_as_number
  peer_ip         = local.ha_bgp_lan_ip_list[var.lan_interface_index]
}

resource "aviatrix_transit_external_device_conn" "default" {
  count                         = var.enable_bgp_peering ? 1 : 0
  vpc_id                        = local.transit_vnet_id
  connection_name               = format("%s-ars-bgp", var.name)
  gw_name                       = local.transit_gateway_name
  connection_type               = "bgp"
  tunnel_protocol               = "LAN"
  remote_vpc_name               = format("%s:%s:%s", local.ars_vnet_name.name, local.resource_group_name, data.azurerm_subscription.current.subscription_id)
  ha_enabled                    = true
  bgp_local_as_num              = local.transit_as_number
  bgp_remote_as_num             = "65515"
  backup_bgp_remote_as_num      = "65515"
  remote_lan_ip                 = tolist(azurerm_route_server.default.virtual_router_ips)[0]
  backup_remote_lan_ip          = tolist(azurerm_route_server.default.virtual_router_ips)[1]
  enable_bgp_lan_activemesh     = true
  enable_learned_cidrs_approval = var.enable_learned_cidrs_approval
  manual_bgp_advertised_cidrs   = var.manual_bgp_advertised_cidrs

  depends_on = [
    azurerm_virtual_network_peering.default-1,
    azurerm_virtual_network_peering.default-2,
  ]
}

resource "aviatrix_segmentation_network_domain_association" "default" {
  count                = length(var.network_domain) > 0 && var.enable_bgp_peering ? 1 : 0 #Only create resource when attached and network_domain is set.
  transit_gateway_name = local.transit_gateway_name
  network_domain_name  = var.network_domain
  attachment_name      = aviatrix_transit_external_device_conn.default[0].connection_name
  depends_on           = [aviatrix_transit_external_device_conn.default] #Let's make sure this cannot create a race condition

  lifecycle {
    # Transit gateway must have segmentation enabled for network domain to be associated.
    precondition {
      condition     = local.segmentation_enabled
      error_message = "The transit gateway does not have segmentation enabled."
    }
  }
}
