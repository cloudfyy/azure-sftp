@description('Name of the existing storage account.')
param storageAccountName string

@description('Name of the private Blob container shared by all SFTP local users.')
@minLength(3)
@maxLength(63)
param blobContainerName string

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: storageAccount
  name: 'default'
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = {
  parent: blobService
  name: blobContainerName
  properties: {
    publicAccess: 'None'
  }
}

output blobContainerName string = blobContainer.name
