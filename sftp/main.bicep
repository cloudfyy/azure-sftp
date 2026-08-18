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
param blobContainerName string = 'data'

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

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' = {
  name: storageAccountName
  location: location
  tags: enableSecurityControlTag ? {
    SecurityControl: 'Ignore'
  } : {}
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    isHnsEnabled: true
    isLocalUserEnabled: true
    isSftpEnabled: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: storageAccount
  name: 'default'
}

resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = [for localUser in localUsers: {
  parent: blobService
  name: toLower('${blobContainerName}-${localUser.name}')
  properties: {
    publicAccess: 'None'
  }
}]

resource sftpLocalUsers 'Microsoft.Storage/storageAccounts/localUsers@2025-06-01' = [for (localUser, index) in localUsers: {
  parent: storageAccount
  name: localUser.name
  properties: {
    allowAclAuthorization: false
    hasSharedKey: false
    hasSshKey: true
    hasSshPassword: false
    homeDirectory: blobContainers[index].name
    permissionScopes: [
      {
        permissions: 'rwdlc'
        resourceName: blobContainers[index].name
        service: 'blob'
      }
    ]
    sshAuthorizedKeys: [
      {
        description: 'SFTP SSH public key'
        key: localUser.sshPublicKey
      }
    ]
  }
}]

output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output sftpEndpoint string = 'sftp://${storageAccount.name}.blob.${environment().suffixes.storage}'
output localUserNames string[] = [for localUser in localUsers: localUser.name]
output blobContainerNames string[] = [for (localUser, index) in localUsers: blobContainers[index].name]
output sftpLoginAddresses string[] = [for localUser in localUsers: 'sftp://${storageAccount.name}.${localUser.name}@${storageAccount.name}.blob.${environment().suffixes.storage}']
