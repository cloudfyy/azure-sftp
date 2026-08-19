@description('Azure region for the storage account.')
param location string

@description('Globally unique storage account name.')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Whether to add the SecurityControl=Ignore tag to the storage account.')
param enableSecurityControlTag bool

@description('Public IPv4 addresses or CIDR ranges allowed to access the storage account.')
@minLength(1)
@maxLength(400)
param allowedIpRanges string[]

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
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: [for ipRange in allowedIpRanges: {
        action: 'Allow'
        value: ipRange
      }]
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output sftpEndpoint string = 'sftp://${storageAccount.name}.blob.${environment().suffixes.storage}'
