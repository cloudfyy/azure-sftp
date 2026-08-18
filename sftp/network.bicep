@description('Azure region for the network resources.')
param location string

@description('Suffix used to keep resource names unique.')
param resourceSuffix string

@description('Virtual network name.')
param virtualNetworkName string

@description('Virtual network address space.')
param virtualNetworkAddressPrefix string

@description('Nginx proxy subnet name.')
param proxySubnetName string

@description('Nginx proxy subnet address prefix.')
param proxySubnetAddressPrefix string

@description('Private endpoint subnet name.')
param privateEndpointSubnetName string

@description('Private endpoint subnet address prefix.')
param privateEndpointSubnetAddressPrefix string

resource proxyNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-sftp-proxy-${resourceSuffix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowLoadBalancerProbe'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '2222'
        }
      }
      {
        name: 'AllowSftpFromInternet'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 200
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '2222'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        virtualNetworkAddressPrefix
      ]
    }
    subnets: [
      {
        name: proxySubnetName
        properties: {
          addressPrefix: proxySubnetAddressPrefix
          networkSecurityGroup: {
            id: proxyNetworkSecurityGroup.id
          }
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output virtualNetworkId string = virtualNetwork.id
output proxySubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, proxySubnetName)
output privateEndpointSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', virtualNetwork.name, privateEndpointSubnetName)
