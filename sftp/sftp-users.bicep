@description('Name of the existing storage account.')
param storageAccountName string

@description('Optional prefix used to generate each private SFTP user container name. When empty, the username is used.')
@maxLength(20)
param blobContainerNamePrefix string

type localUserConfig = {
  @minLength(3)
  @maxLength(42)
  name: string
  sshPublicKey: string
  accessibleUserNames: string[]?
}

@description('Exactly four SFTP local users and their container access assignments.')
@minLength(4)
@maxLength(4)
param localUsers localUserConfig[]

@description('Blob container name corresponding to each local user by array index.')
@minLength(4)
@maxLength(4)
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
    permissionScopes: [for accessibleUserName in (localUser.?accessibleUserNames ?? [localUser.name]): {
      permissions: 'rwdlc'
      resourceName: toLower(empty(blobContainerNamePrefix) ? accessibleUserName : '${blobContainerNamePrefix}-${accessibleUserName}')
      service: 'blob'
    }]
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
