using './main.bicep'

param storageAccountName = 'stsftpreplace001'
param blobContainerNamePrefix = 'data'
param enableSecurityControlTag = false
param localUsers = [
	{
		name: 'sftpuser01'
		sshPublicKey: ''
	}
	{
		name: 'sftpuser02'
		sshPublicKey: ''
	}
	{
		name: 'sftpuser03'
		sshPublicKey: ''
	}
]
