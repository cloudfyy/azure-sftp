@description('Name of the existing storage account.')
param storageAccountName string

@description('Prefix for each private SFTP user container.')
@minLength(3)
@maxLength(20)
param blobContainerNamePrefix string

@description('SFTP local user names used to generate container names.')
param localUserNames string[]

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-06-01' = {
  parent: storageAccount
  name: 'default'
}

resource blobContainers 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-06-01' = [for localUserName in localUserNames: {
  parent: blobService
  name: toLower('${blobContainerNamePrefix}-${localUserName}')
  properties: {
    publicAccess: 'None'
  }
}]

output blobContainerNames string[] = [for (localUserName, index) in localUserNames: blobContainers[index].name]
