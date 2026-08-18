@description('Azure region for the proxy resources.')
param location string

@description('Suffix used to keep resource names unique.')
param resourceSuffix string

@description('Proxy subnet resource ID.')
param proxySubnetId string

@description('Load balancer backend pool resource ID.')
param backendPoolId string

@description('Storage Blob hostname resolved through Private DNS.')
param storageBlobHostName string

@description('SSH public key for emergency administration from the private network.')
param proxyAdminSshPublicKey string

@description('Linux administrator username.')
param proxyAdminUsername string

@description('Size of each Nginx proxy VM.')
param proxyVmSize string

var instanceCount = 2
var nginxCloudInit = replace('''
#cloud-config
package_update: true
packages:
	- nginx
	- libnginx-mod-stream
write_files:
	- path: /etc/nginx/nginx.conf
		owner: root:root
		permissions: '0644'
		content: |
			user www-data;
			worker_processes auto;
			pid /run/nginx.pid;
			include /etc/nginx/modules-enabled/*.conf;

			events {
					worker_connections 1024;
			}

			stream {
					proxy_connect_timeout 10s;
					proxy_timeout 1h;

					upstream storage_sftp {
							server __STORAGE_BLOB_HOST__:22;
					}

					server {
							listen 2222;
							proxy_pass storage_sftp;
					}
			}
runcmd:
	- [nginx, -t]
	- [systemctl, enable, nginx]
	- [systemctl, restart, nginx]
''', '__STORAGE_BLOB_HOST__', storageBlobHostName)

resource proxyAvailabilitySet 'Microsoft.Compute/availabilitySets@2024-03-01' = {
	name: 'avset-sftp-proxy-${resourceSuffix}'
	location: location
	sku: {
		name: 'Aligned'
	}
	properties: {
		platformFaultDomainCount: 2
		platformUpdateDomainCount: 5
	}
}

resource proxyNetworkInterfaces 'Microsoft.Network/networkInterfaces@2024-05-01' = [for index in range(0, instanceCount): {
	name: 'nic-sftp-proxy-${resourceSuffix}-${index + 1}'
	location: location
	properties: {
		ipConfigurations: [
			{
				name: 'ipconfig1'
				properties: {
					privateIPAllocationMethod: 'Dynamic'
					subnet: {
						id: proxySubnetId
					}
					loadBalancerBackendAddressPools: [
						{
							id: backendPoolId
						}
					]
				}
			}
		]
	}
}]

resource proxyVirtualMachines 'Microsoft.Compute/virtualMachines@2024-07-01' = [for index in range(0, instanceCount): {
	name: 'vm-sftp-proxy-${resourceSuffix}-${index + 1}'
	location: location
	properties: {
		availabilitySet: {
			id: proxyAvailabilitySet.id
		}
		hardwareProfile: {
			vmSize: proxyVmSize
		}
		osProfile: {
			computerName: 'sftpproxy${index + 1}'
			adminUsername: proxyAdminUsername
			customData: base64(nginxCloudInit)
			linuxConfiguration: {
				disablePasswordAuthentication: true
				provisionVMAgent: true
				ssh: {
					publicKeys: [
						{
							path: '/home/${proxyAdminUsername}/.ssh/authorized_keys'
							keyData: proxyAdminSshPublicKey
						}
					]
				}
			}
		}
		storageProfile: {
			imageReference: {
				publisher: 'Canonical'
				offer: '0001-com-ubuntu-server-jammy'
				sku: '22_04-lts-gen2'
				version: 'latest'
			}
			osDisk: {
				createOption: 'FromImage'
				managedDisk: {
					storageAccountType: 'StandardSSD_LRS'
				}
			}
		}
		networkProfile: {
			networkInterfaces: [
				{
					id: proxyNetworkInterfaces[index].id
					properties: {
						primary: true
					}
				}
			]
		}
	}
}]

output virtualMachineIds string[] = [for index in range(0, instanceCount): proxyVirtualMachines[index].id]
output virtualMachineNames string[] = [for index in range(0, instanceCount): proxyVirtualMachines[index].name]
