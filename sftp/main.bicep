targetScope = 'resourceGroup'

@description('Azure region for the storage account.')
param location string = resourceGroup().location

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('Optional prefix for each private SFTP user container. When empty, the username is used as the container name.')
@maxLength(20)
param blobContainerNamePrefix string = 'data'

@description('Whether to add the SecurityControl=Ignore tag to the storage account.')
param enableSecurityControlTag bool = false

@description('Public IPv4 addresses or CIDR ranges allowed to access the storage account.')
@maxLength(400)
param allowedIpRanges string[]

type localUserConfig = {
  @minLength(3)
  @maxLength(42)
  name: string
  sshPublicKey: string
  accessibleUserNames: string[]?
}

@description('Exactly four SFTP local users, their SSH public keys, and optional access to other users containers.')
@minLength(4)
@maxLength(4)
param localUsers localUserConfig[]

module storageAccount './storage-account.bicep' = {
  name: 'storage-account'
  params: {
    location: location
    storageAccountName: storageAccountName
    enableSecurityControlTag: enableSecurityControlTag
    allowedIpRanges: allowedIpRanges
  }
}

module blobContainers './blob-containers.bicep' = {
  name: 'blob-containers'
  params: {
    storageAccountName: storageAccount.outputs.storageAccountName
    blobContainerNamePrefix: blobContainerNamePrefix
    localUserNames: [for localUser in localUsers: localUser.name]
  }
}

module sftpUsers './sftp-users.bicep' = {
  name: 'sftp-users'
  params: {
    storageAccountName: storageAccount.outputs.storageAccountName
    localUsers: localUsers
    blobContainerNames: blobContainers.outputs.blobContainerNames
    blobContainerNamePrefix: blobContainerNamePrefix
  }
}

output storageAccountId string = storageAccount.outputs.storageAccountId
output blobEndpoint string = storageAccount.outputs.blobEndpoint
output sftpEndpoint string = storageAccount.outputs.sftpEndpoint
output localUserNames string[] = sftpUsers.outputs.localUserNames
output blobContainerNames string[] = blobContainers.outputs.blobContainerNames
output sftpLoginAddresses string[] = sftpUsers.outputs.sftpLoginAddresses
