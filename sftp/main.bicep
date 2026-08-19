targetScope = 'resourceGroup'

@description('Azure region for the storage account.')
param location string = resourceGroup().location

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('Prefix for each private SFTP user container.')
@minLength(3)
@maxLength(20)
param blobContainerNamePrefix string = 'data'

@description('Whether to add the SecurityControl=Ignore tag to the storage account.')
param enableSecurityControlTag bool = false

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
  }
}

output storageAccountId string = storageAccount.outputs.storageAccountId
output blobEndpoint string = storageAccount.outputs.blobEndpoint
output sftpEndpoint string = storageAccount.outputs.sftpEndpoint
output localUserNames string[] = sftpUsers.outputs.localUserNames
output blobContainerNames string[] = blobContainers.outputs.blobContainerNames
output sftpLoginAddresses string[] = sftpUsers.outputs.sftpLoginAddresses
