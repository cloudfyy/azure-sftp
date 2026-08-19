@description('Name of the existing storage account.')
param storageAccountName string

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

@description('Blob container name corresponding to each local user by array index.')
@minLength(3)
@maxLength(3)
param blobContainerNames string[]

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource sftpLocalUsers 'Microsoft.Storage/storageAccounts/localUsers@2025-06-01' = [for (localUser, index) in localUsers: {
  parent: storageAccount
  name: localUser.name
  properties: {
    allowAclAuthorization: false
    hasSharedKey: false
    hasSshKey: true
    hasSshPassword: false
    homeDirectory: blobContainerNames[index]
    permissionScopes: [
      {
        permissions: 'rwdlc'
        resourceName: blobContainerNames[index]
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

output localUserNames string[] = [for localUser in localUsers: localUser.name]
output sftpLoginAddresses string[] = [for localUser in localUsers: 'sftp://${storageAccount.name}.${localUser.name}@${storageAccount.name}.blob.${environment().suffixes.storage}']
