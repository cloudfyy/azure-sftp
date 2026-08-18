@description('Azure region for the load balancer resources.')
param location string

@description('Suffix used to keep resource names unique.')
param resourceSuffix string

var publicIpName = 'pip-sftp-${resourceSuffix}'
var loadBalancerName = 'lb-sftp-${resourceSuffix}'
var frontendName = 'sftpFrontend'
var backendPoolName = 'sftpProxyBackendPool'
var probeName = 'nginxTcpProbe'

resource loadBalancerPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource sftpLoadBalancer 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: loadBalancerName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: frontendName
        properties: {
          publicIPAddress: {
            id: loadBalancerPublicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: backendPoolName
      }
    ]
    probes: [
      {
        name: probeName
        properties: {
          protocol: 'Tcp'
          port: 2222
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'sftp'
        properties: {
          protocol: 'Tcp'
          frontendPort: 22
          backendPort: 2222
          enableFloatingIP: false
          idleTimeoutInMinutes: 30
          disableOutboundSnat: true
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, frontendName)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, backendPoolName)
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', loadBalancerName, probeName)
          }
        }
      }
    ]
    outboundRules: [
      {
        name: 'proxyInternetEgress'
        properties: {
          protocol: 'All'
          allocatedOutboundPorts: 1024
          idleTimeoutInMinutes: 15
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', loadBalancerName, backendPoolName)
          }
          frontendIPConfigurations: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', loadBalancerName, frontendName)
            }
          ]
        }
      }
    ]
  }
}

output loadBalancerName string = sftpLoadBalancer.name
output backendPoolId string = resourceId('Microsoft.Network/loadBalancers/backendAddressPools', sftpLoadBalancer.name, backendPoolName)
output publicIpAddress string = loadBalancerPublicIp.properties.ipAddress
