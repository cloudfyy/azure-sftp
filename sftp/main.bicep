targetScope = 'resourceGroup'

@description('Azure region for the storage account.')
param location string = resourceGroup().location

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('Name of the private Blob container shared by all SFTP local users.')
@minLength(3)
@maxLength(63)
param blobContainerName string = 'data'

@description('Whether to add the SecurityControl=Ignore tag to the storage account.')
param enableSecurityControlTag bool = false

@description('Public IPv4 addresses or CIDR ranges allowed to access the storage account.')
@minLength(1)
@maxLength(400)
param allowedIpRanges string[]

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
    blobContainerName: blobContainerName
  }
}

module sftpUsers './sftp-users.bicep' = {
  name: 'sftp-users'
  params: {
    storageAccountName: storageAccount.outputs.storageAccountName
    localUsers: localUsers
    blobContainerName: blobContainers.outputs.blobContainerName
  }
}

output storageAccountId string = storageAccount.outputs.storageAccountId
output blobEndpoint string = storageAccount.outputs.blobEndpoint
output sftpEndpoint string = storageAccount.outputs.sftpEndpoint
output localUserNames string[] = sftpUsers.outputs.localUserNames
output blobContainerName string = blobContainers.outputs.blobContainerName
output sftpLoginAddresses string[] = sftpUsers.outputs.sftpLoginAddresses
