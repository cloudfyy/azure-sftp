targetScope = 'resourceGroup'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('Prefix for each private SFTP user container.')
@minLength(3)
@maxLength(20)
param blobContainerName string = 'data'

@description('Whether to add the SecurityControl=Ignore tag to the storage account.')
param enableSecurityControlTag bool = false

@description('SSH public key used only for emergency administration of the proxy VMs from the private network.')
param proxyAdminSshPublicKey string

@description('Linux administrator username for the proxy VMs.')
param proxyAdminUsername string = 'azureuser'

@description('Size of each Nginx proxy VM.')
param proxyVmSize string = 'Standard_B2s'

@description('Client IPv4 CIDR ranges allowed to connect to the public load balancer on TCP 22.')
@minLength(1)
param allowedSftpSourceCidrs string[]

@description('Address space for the virtual network.')
param virtualNetworkAddressPrefix string = '10.20.0.0/16'

@description('Address prefix for the Nginx proxy subnet.')
param proxySubnetAddressPrefix string = '10.20.1.0/24'

@description('Address prefix for the Storage private endpoint subnet.')
param privateEndpointSubnetAddressPrefix string = '10.20.2.0/24'

type localUserConfig = {
  @minLength(3)
  @maxLength(42)
  name: string
  sshPublicKey: string
}

@description('Exactly three SFTP local users and their SSH public keys.')
@minLength(3)
@maxLength(3)
param localUsers localUserConfig[]

var resourceSuffix = uniqueString(resourceGroup().id, storageAccountName)
var virtualNetworkName = 'vnet-sftp-${resourceSuffix}'
var proxySubnetName = 'snet-proxy'
var privateEndpointSubnetName = 'snet-private-endpoints'

module storage './storage.bicep' = {
  params: {
    blobContainerName: blobContainerName
    enableSecurityControlTag: enableSecurityControlTag
    localUsers: localUsers
    location: location
    storageAccountName: storageAccountName
  }
}

module network './network.bicep' = {
  params: {
    allowedSftpSourceCidrs: allowedSftpSourceCidrs
    location: location
    privateEndpointSubnetAddressPrefix: privateEndpointSubnetAddressPrefix
    privateEndpointSubnetName: privateEndpointSubnetName
    proxySubnetAddressPrefix: proxySubnetAddressPrefix
    proxySubnetName: proxySubnetName
    resourceSuffix: resourceSuffix
    virtualNetworkAddressPrefix: virtualNetworkAddressPrefix
    virtualNetworkName: virtualNetworkName
  }
}

module privateEndpoint './private-endpoint.bicep' = {
  params: {
    location: location
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    storageAccountId: storage.outputs.storageAccountId
    storageAccountName: storageAccountName
    virtualNetworkId: network.outputs.virtualNetworkId
    virtualNetworkName: virtualNetworkName
  }
}

module loadBalancer './load-balancer.bicep' = {
  params: {
    location: location
    resourceSuffix: resourceSuffix
  }
}

module nginxProxies './nginx-proxies.bicep' = {
  params: {
    backendPoolId: loadBalancer.outputs.backendPoolId
    location: location
    proxyAdminSshPublicKey: proxyAdminSshPublicKey
    proxyAdminUsername: proxyAdminUsername
    proxySubnetId: network.outputs.proxySubnetId
    proxyVmSize: proxyVmSize
    resourceSuffix: resourceSuffix
    storageBlobHostName: storage.outputs.storageBlobHostName
  }
  dependsOn: [
    privateEndpoint
  ]
}

output storageAccountId string = storage.outputs.storageAccountId
output blobEndpoint string = storage.outputs.blobEndpoint
output loadBalancerPublicIpAddress string = loadBalancer.outputs.publicIpAddress
output sftpEndpoint string = 'sftp://${loadBalancer.outputs.publicIpAddress}'
output localUserNames string[] = storage.outputs.localUserNames
output blobContainerNames string[] = storage.outputs.blobContainerNames
output sftpLoginAddresses string[] = [for localUser in localUsers: 'sftp://${storageAccountName}.${localUser.name}@${loadBalancer.outputs.publicIpAddress}']
output storageBlobPrivateEndpointIpAddress string = privateEndpoint.outputs.privateEndpointIpAddress
output proxyVirtualMachineIds string[] = nginxProxies.outputs.virtualMachineIds
output proxyVirtualMachineNames string[] = nginxProxies.outputs.virtualMachineNames
output loadBalancerName string = loadBalancer.outputs.loadBalancerName
