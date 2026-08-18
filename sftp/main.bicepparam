using './main.bicep'

param storageAccountName = 'stsftpexample001'
param blobContainerNamePrefix = 'data'
param enableSecurityControlTag = false
param proxyAdminSshPublicKey = '<proxy-admin-ssh-public-key>'
param proxyAdminUsername = 'azureuser'
param proxyVmSize = 'Standard_B2s'
param localUsers = [
	{
		name: 'sftpuser01'
		sshPublicKey: '<sftpuser01-ssh-public-key>'
	}
	{
		name: 'sftpuser02'
		sshPublicKey: '<sftpuser02-ssh-public-key>'
	}
	{
		name: 'sftpuser03'
		sshPublicKey: '<sftpuser03-ssh-public-key>'
	}
]
