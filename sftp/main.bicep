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

@description('Resource group containing the existing Azure Files storage account.')
param targetStorageResourceGroupName string

@description('Existing Azure Files storage account name.')
@minLength(3)
@maxLength(24)
param targetStorageAccountName string

@description('Existing Azure file share name.')
param targetFileShareName string

@description('Maximum number of concurrent ADF copy pipeline runs. Additional runs are queued.')
@minValue(1)
@maxValue(50)
param pipelineConcurrency int = 10

@description('Timeout for each ADF copy activity run, formatted as d.hh:mm:ss.')
param copyActivityTimeout string = '0.02:00:00'

@description('Number of retries after an ADF copy activity failure.')
@minValue(0)
param copyActivityRetryCount int = 5

@description('Delay in seconds between ADF copy activity retries.')
@minValue(30)
param copyActivityRetryIntervalInSeconds int = 60

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

module dataFactory './adf.bicep' = {
  params: {
    dataFactoryName: 'adf-${storageAccountName}'
    location: location
    sourceContainerNames: [for (localUser, index) in localUsers: blobContainers[index].name]
    sourceStorageAccountName: storageAccount.name
    targetFileShareName: targetFileShareName
    targetStorageAccountName: targetStorageAccountName
    targetStorageResourceGroupName: targetStorageResourceGroupName
    pipelineConcurrency: pipelineConcurrency
    copyActivityTimeout: copyActivityTimeout
    copyActivityRetryCount: copyActivityRetryCount
    copyActivityRetryIntervalInSeconds: copyActivityRetryIntervalInSeconds
  }
}

output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output sftpEndpoint string = 'sftp://${storageAccount.name}.blob.${environment().suffixes.storage}'
output localUserNames string[] = [for localUser in localUsers: localUser.name]
output blobContainerNames string[] = [for (localUser, index) in localUsers: blobContainers[index].name]
output sftpLoginAddresses string[] = [for localUser in localUsers: 'sftp://${storageAccount.name}.${localUser.name}@${storageAccount.name}.blob.${environment().suffixes.storage}']
output dataFactoryId string = dataFactory.outputs.dataFactoryId
output dataFactoryPipelineName string = dataFactory.outputs.pipelineName
output dataFactoryTriggerNames string[] = dataFactory.outputs.triggerNames
