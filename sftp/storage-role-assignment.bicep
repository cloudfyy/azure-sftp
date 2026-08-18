targetScope = 'resourceGroup'

@description('Existing storage account receiving the role assignment.')
param storageAccountName string

@description('Managed identity principal receiving the role.')
param principalId string

@description('Fully qualified role definition resource ID.')
param roleDefinitionId string

resource storageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: storageAccountName
}

resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: roleDefinitionId
  }
}

output roleAssignmentId string = storageRoleAssignment.id
