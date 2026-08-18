using './main.bicep'

param storageAccountName = 'stsftpexample001'
param blobContainerName = 'data'
param enableSecurityControlTag = true
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
