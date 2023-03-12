# terraform-aviatrix-azure-route-server

### Description
This module deploys a VNET with Azure route server and integrates it with the provided Aviatrix transit through BGP over LAN. Make sure to use a transit instance size that allows for more than 4 interfaces (e.g. Standard_DS4_v2). An ExpressRoute Gateway (vng) is provisioned as well to facilitate attachment to the ExpressRoute circuit.

### Diagram
<img src="https://github.com/terraform-aviatrix-modules/terraform-aviatrix-azure-route-server/blob/main/img/diagram.png?raw=true" width="500">

### Compatibility
Module version | Terraform version | Controller version | Terraform provider version
:--- | :--- | :--- | :---
v1.0.2 | >= 1.1.0 | >= 6.8.1311 | >= 2.23.1

### Usage Example
```hcl
module "transit" {
  source  = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version = "2.2.0"

  cloud   = "Azure"
  region  = "West Europe"
  cidr    = "10.1.0.0/23"
  account = "Azure"

  local_as_number          = 65000
  insane_mode              = true
  enable_bgp_over_lan      = true
  bgp_lan_interfaces_count = 1
  instance_size            = "Standard_D4_v2"
}

module "azure_route_server" {
  source  = "terraform-aviatrix-modules/azure-route-server/aviatrix"
  version = "1.0.2"
  
  name                = "myars"
  transit_vnet_obj    = module.transit.vpc
  transit_gw_obj      = module.transit.transit_gateway
  cidr                = "10.1.128.0/26"
}
```

### Variables
The following variables are required:

key | value
:--- | :---
name | Name to be used for Azure Route Server related components.
cidr | CIDR for VNET creation.
transit_vnet_obj | The entire VNET object as created by aviatrix_vpc resource.
transit_gw_obj | The entire gateway object as created by aviatrix_transit_gateway resource.

The following variables are optional:

key | default | value 
:---|:---|:---
enable_bgp_peering | true | Toggle to enable/disable BGP peering between the Aviatrix transit and Azure route server. E.g. for migration scenario's.
enable_vng_deployment | true | Toggle to enable/disable VNG deployment.
[enable_learned_cidrs_approval](https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs/resources/aviatrix_transit_external_device_conn#enable_learned_cidrs_approval) | null | Enable learned CIDRs approval for the connection. 
lan_interface_index | 0 | Determines which LAN interface will be used for terminating the BGP peering. Uses the first BGP interface by default (0)
network_domain | | Network domain used for segmentation.
[manual_bgp_advertised_cidrs](https://registry.terraform.io/providers/AviatrixSystems/aviatrix/latest/docs/resources/aviatrix_transit_external_device_conn#manual_bgp_advertised_cidrs) | null | Configure manual BGP advertised CIDRs from Aviatrix side just for this connection towards ARS. 
resource_group_name | | Resource group name, in case you want to use an existing resource group.
vng_sku | Standard | SKU to use to deploy the VNG.
route_server_subnet | | If provided, this is the subnet CIDR that will be used for the route server subnet.
vng_subnet | | If provided, this is the subnet CIDR that will be used for the VNG subnet.
ars_vnet_name | | If provided, VNET name for ARS.
ars_subnet_id | | If provided, this is the subnet ID that will be used for the ARS.

### Outputs
This module will return the following outputs:

key | description
:---|:---
vng | Azure virtual network gateway with all attributes as created through the azurerm_virtual_network_gateway resource.
