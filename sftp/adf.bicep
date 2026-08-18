targetScope = 'resourceGroup'

param location string
param dataFactoryName string
param sourceStorageAccountName string
param sourceContainerNames string[]
param targetStorageResourceGroupName string
param targetStorageAccountName string
param targetFileShareName string

@description('Maximum number of concurrent runs for the copy pipeline. Additional runs are queued.')
@minValue(1)
@maxValue(50)
param pipelineConcurrency int = 10

@description('Timeout for each copy activity run, formatted as d.hh:mm:ss.')
param copyActivityTimeout string = '0.02:00:00'

@description('Number of retries after a copy activity failure.')
@minValue(0)
param copyActivityRetryCount int = 5

@description('Delay in seconds between copy activity retries.')
@minValue(30)
param copyActivityRetryIntervalInSeconds int = 60

var storageBlobDataReaderRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
)
var storageFileDataPrivilegedContributorRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
)

resource sourceStorageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  name: sourceStorageAccountName
}

resource targetStorageAccount 'Microsoft.Storage/storageAccounts@2025-06-01' existing = {
  scope: resourceGroup(targetStorageResourceGroupName)
  name: targetStorageAccountName
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource sourceBlobReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sourceStorageAccount
  name: guid(sourceStorageAccount.id, dataFactory.id, storageBlobDataReaderRoleDefinitionId)
  properties: {
    principalId: dataFactory.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataReaderRoleDefinitionId
  }
}

module targetFileContributorRole './storage-role-assignment.bicep' = {
  scope: resourceGroup(targetStorageResourceGroupName)
  params: {
    principalId: dataFactory.identity.principalId
    roleDefinitionId: storageFileDataPrivilegedContributorRoleDefinitionId
    storageAccountName: targetStorageAccountName
  }
}

resource sourceBlobLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_source_blob_mi'
  properties: {
    type: 'AzureBlobStorage'
    typeProperties: {
      accountKind: 'StorageV2'
      serviceEndpoint: 'https://${sourceStorageAccount.name}.blob.${environment().suffixes.storage}'
    }
  }
}

resource targetFilesLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: 'ls_target_azure_files_mi'
  properties: {
    type: 'AzureFileStorage'
    typeProperties: {
      fileShare: targetFileShareName
      serviceEndpoint: 'https://${targetStorageAccount.name}.file.${environment().suffixes.storage}'
    }
  }
}

resource sourceBlobDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ds_source_blob_binary'
  properties: {
    type: 'Binary'
    parameters: {
      containerName: {
        type: 'String'
      }
      folderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
    }
    linkedServiceName: {
      referenceName: sourceBlobLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureBlobStorageLocation'
        container: {
          type: 'Expression'
          value: '@dataset().containerName'
        }
        folderPath: {
          type: 'Expression'
          value: '@dataset().folderPath'
        }
        fileName: {
          type: 'Expression'
          value: '@dataset().fileName'
        }
      }
    }
  }
}

resource targetFilesDataset 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: 'ds_target_azure_files_binary'
  properties: {
    type: 'Binary'
    parameters: {
      folderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
    }
    linkedServiceName: {
      referenceName: targetFilesLinkedService.name
      type: 'LinkedServiceReference'
    }
    typeProperties: {
      location: {
        type: 'AzureFileStorageLocation'
        folderPath: {
          type: 'Expression'
          value: '@dataset().folderPath'
        }
        fileName: {
          type: 'Expression'
          value: '@dataset().fileName'
        }
      }
    }
  }
}

resource copyPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: 'pl_copy_sftp_upload_to_azure_files'
  properties: {
    concurrency: pipelineConcurrency
    parameters: {
      containerName: {
        type: 'String'
      }
      folderPath: {
        type: 'String'
      }
      fileName: {
        type: 'String'
      }
    }
    activities: [
      {
        name: 'CopyUploadedFileToAzureFiles'
        type: 'Copy'
        dependsOn: []
        policy: {
          timeout: copyActivityTimeout
          retry: copyActivityRetryCount
          retryIntervalInSeconds: copyActivityRetryIntervalInSeconds
          secureInput: false
          secureOutput: false
        }
        typeProperties: {
          source: {
            type: 'BinarySource'
            formatSettings: {
              type: 'BinaryReadSettings'
            }
            storeSettings: {
              type: 'AzureBlobStorageReadSettings'
              recursive: false
            }
          }
          sink: {
            type: 'BinarySink'
            storeSettings: {
              type: 'AzureFileStorageWriteSettings'
              copyBehavior: 'PreserveHierarchy'
            }
          }
          enableStaging: false
        }
        inputs: [
          {
            referenceName: sourceBlobDataset.name
            type: 'DatasetReference'
            parameters: {
              containerName: {
                type: 'Expression'
                value: '@pipeline().parameters.containerName'
              }
              folderPath: {
                type: 'Expression'
                value: '@if(equals(pipeline().parameters.folderPath, pipeline().parameters.containerName), \'\', substring(pipeline().parameters.folderPath, add(length(pipeline().parameters.containerName), 1), sub(length(pipeline().parameters.folderPath), add(length(pipeline().parameters.containerName), 1))))'
              }
              fileName: {
                type: 'Expression'
                value: '@pipeline().parameters.fileName'
              }
            }
          }
        ]
        outputs: [
          {
            referenceName: targetFilesDataset.name
            type: 'DatasetReference'
            parameters: {
              folderPath: {
                type: 'Expression'
                value: '@pipeline().parameters.folderPath'
              }
              fileName: {
                type: 'Expression'
                value: '@pipeline().parameters.fileName'
              }
            }
          }
        ]
      }
    ]
  }
}

resource sftpUploadTriggers 'Microsoft.DataFactory/factories/triggers@2018-06-01' = [for containerName in sourceContainerNames: {
  parent: dataFactory
  name: 'tr_sftp_commit_${containerName}'
  properties: {
    type: 'BlobEventsTrigger'
    pipelines: [
      {
        pipelineReference: {
          referenceName: copyPipeline.name
          type: 'PipelineReference'
        }
        parameters: {
          containerName: containerName
          folderPath: '@triggerBody().folderPath'
          fileName: '@triggerBody().fileName'
        }
      }
    ]
    typeProperties: {
      blobPathBeginsWith: '/${containerName}/blobs/'
      events: [
        'Microsoft.Storage.BlobCreated'
      ]
      ignoreEmptyBlobs: false
      scope: sourceStorageAccount.id
    }
  }
  dependsOn: [
    sourceBlobReaderRole
  ]
}]

output dataFactoryId string = dataFactory.id
output dataFactoryPrincipalId string = dataFactory.identity.principalId
output pipelineName string = copyPipeline.name
output triggerNames string[] = [for (containerName, index) in sourceContainerNames: sftpUploadTriggers[index].name]
