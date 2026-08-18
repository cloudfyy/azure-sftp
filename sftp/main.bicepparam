using './main.bicep'

param storageAccountName = 'stsftpexample001'
param blobContainerName = 'data'
param enableSecurityControlTag = true
param targetStorageResourceGroupName = 'rg-sftp-example'
param targetStorageAccountName = 'stfilesexample001'
param targetFileShareName = 'data'
param pipelineConcurrency = 10
param copyActivityTimeout = '0.02:00:00'
param copyActivityRetryCount = 5
param copyActivityRetryIntervalInSeconds = 60
param localUsers = [
	{
		name: 'sftpuser01'
		sshPublicKey: 'REPLACE_WITH_SFTPUSER01_SSH_PUBLIC_KEY'
	}
	{
		name: 'sftpuser02'
		sshPublicKey: 'REPLACE_WITH_SFTPUSER02_SSH_PUBLIC_KEY'
	}
	{
		name: 'sftpuser03'
		sshPublicKey: 'REPLACE_WITH_SFTPUSER03_SSH_PUBLIC_KEY'
	}
]
