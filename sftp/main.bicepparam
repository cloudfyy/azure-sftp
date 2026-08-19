using './main.bicep'

param storageAccountName = 'stsftpreplace001'
param blobContainerNamePrefix = 'data'
param enableSecurityControlTag = false
param allowedIpRanges = [
	'203.0.113.10'
]
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
