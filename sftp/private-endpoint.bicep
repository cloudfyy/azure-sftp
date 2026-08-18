@description('Azure region for the private endpoint.')
param location string

@description('Storage account resource ID.')
param storageAccountId string

@description('Storage account name.')
param storageAccountName string

@description('Private endpoint subnet resource ID.')
param privateEndpointSubnetId string

@description('Virtual network resource ID linked to the private DNS zone.')
param virtualNetworkId string

@description('Virtual network name used for the DNS link name.')
param virtualNetworkName string

var blobPrivateDnsZoneName = 'privatelink.blob.${environment().suffixes.storage}'

resource blobPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: blobPrivateDnsZoneName
  location: 'global'
}

resource blobPrivateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: blobPrivateDnsZone
  name: 'link-${virtualNetworkName}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetworkId
    }
  }
}

resource blobPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'storageBlobConnection'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource blobPrivateEndpointDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: blobPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blobPrivateDnsZone'
        properties: {
          privateDnsZoneId: blobPrivateDnsZone.id
        }
      }
    ]
  }
}

output privateEndpointId string = blobPrivateEndpoint.id
output privateEndpointIpAddress string = length(blobPrivateEndpoint.properties.customDnsConfigs) > 0
  ? (length(blobPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses) > 0
    ? blobPrivateEndpoint.properties.customDnsConfigs[0].ipAddresses[0]
    : '')
  : ''
