# Azure Storage SFTP Deployment Guide

This guide deploys the resources defined in `sftp/main.bicep` by using the values in `sftp/main.bicepparam`.

## Resources Deployed

- One Standard LRS `StorageV2` storage account
- Hierarchical namespace (HNS), SFTP, and local users enabled
- One private Blob container per local user, named `<prefix>-<username>`
- Exactly three SFTP local users authenticated with SSH public keys
- Each local user is restricted to its own container
- One virtual network with separate Nginx proxy and private endpoint subnets
- One Blob private endpoint and a linked `privatelink.blob.core.windows.net` private DNS zone
- Two Ubuntu VMs in an availability set, each running Nginx Stream as a transparent TCP proxy
- One Standard public load balancer and one static Standard public IP address
- Public TCP 22 forwarded by the load balancer to Nginx TCP 2222
- Storage public network access disabled and a minimum TLS version of 1.2
- No `SecurityControl` tag by default; it can be enabled through a deployment parameter

The proxy VMs have no public IP addresses. Nginx does not terminate SSH; it forwards the encrypted TCP stream to Azure Storage SFTP through the Blob private endpoint. The client therefore authenticates directly to Azure Storage and receives the Azure Storage SSH host key.

The load balancer distributes new TCP connections across both proxy VMs and removes an instance from rotation when its TCP 2222 health probe fails. The availability set separates the two instances across fault and update domains within the selected region.

## Template Structure

- `sftp/main.bicep` coordinates the deployment and exposes consolidated outputs.
- `sftp/storage.bicep` deploys the Storage account, Blob containers, and SFTP local users.
- `sftp/network.bicep` deploys the virtual network, subnets, and proxy network security group.
- `sftp/private-endpoint.bicep` deploys the Blob private endpoint and private DNS resources.
- `sftp/load-balancer.bicep` deploys the Standard public IP and public load balancer.
- `sftp/nginx-proxies.bicep` deploys the availability set, two NICs, and two Nginx proxy VMs.

## Software Prerequisites

Install the following software on the deployment workstation:

1. [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)
2. [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli), using the latest available version
3. Azure Bicep CLI, installed through Azure CLI
4. OpenSSH Client, including `ssh-keygen` and `sftp`

Verify the installed tools:

```powershell
$PSVersionTable.PSVersion
az version
az bicep install
az bicep version
ssh-keygen -?
sftp -?
```

To update an existing Bicep CLI installation:

```powershell
az bicep upgrade
```

## Azure Prerequisites

- An active Azure subscription
- At least the `Contributor` role on the target resource group or subscription
- A region that supports Azure Blob Storage SFTP
- A globally unique storage account name containing 3-24 lowercase letters and numbers
- Permission to register the `Microsoft.Storage`, `Microsoft.Network`, and `Microsoft.Compute` resource providers if they are not already registered

SFTP has an hourly charge while it is enabled, in addition to normal storage and transaction charges. Review current Azure Storage pricing before deployment.

## Prepare the Parameters

From the repository root, open the deployment directory:

```powershell
Set-Location .\sftp
```

The template requires exactly three local users. Generate a separate SSH key pair for each user if suitable keys do not already exist:

```powershell
$sshKeyDirectory = "$HOME\.ssh\azure-sftp"
New-Item -ItemType Directory -Path $sshKeyDirectory -Force | Out-Null

ssh-keygen -t rsa -b 4096 -f "$sshKeyDirectory\sftpuser01" -C "sftpuser01"
ssh-keygen -t rsa -b 4096 -f "$sshKeyDirectory\sftpuser02" -C "sftpuser02"
ssh-keygen -t rsa -b 4096 -f "$sshKeyDirectory\sftpuser03" -C "sftpuser03"
```

Display each public key:

```powershell
Get-Content "$HOME\.ssh\azure-sftp\sftpuser01.pub"
Get-Content "$HOME\.ssh\azure-sftp\sftpuser02.pub"
Get-Content "$HOME\.ssh\azure-sftp\sftpuser03.pub"
```

Generate a separate key pair for emergency administration of the proxy VM:

```powershell
ssh-keygen -t rsa -b 4096 -f "$sshKeyDirectory\proxy-admin" -C "proxy-admin"
Get-Content "$sshKeyDirectory\proxy-admin.pub"
```

Edit `main.bicepparam` and set:

- `storageAccountName` to a globally unique name
- `blobContainerName` to the container name prefix; the default creates `data-sftpuser01`, `data-sftpuser02`, and `data-sftpuser03`
- `enableSecurityControlTag` to `true` only when the storage account requires the `SecurityControl=Ignore` tag; the default is `false`
- `proxyAdminSshPublicKey` to the public key generated for proxy VM administration
- `proxyAdminUsername` to the required Linux administrator username
- `proxyVmSize` to a VM size available in the selected region
- `allowedSftpSourceCidrs` to the public IPv4 CIDR ranges of the SFTP clients
- Each `localUsers` entry to the required username and matching public key

Only public keys belong in `main.bicepparam`. Never place private key content in the parameter file or source control.

The example `203.0.113.0/24` source range is reserved for documentation and isn't routable. Replace it before deployment. Do not use `0.0.0.0/0` unless unrestricted Internet access is an explicit requirement.

## Sign In and Select a Subscription

Set the deployment values for the current PowerShell session:

```powershell
$subscriptionId = '<subscription-id>'
$resourceGroupName = 'rg-sftp'
$location = 'eastus2'
$deploymentName = "sftp-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
```

Authenticate and select the target subscription:

```powershell
az login
az account set --subscription $subscriptionId
az account show --query '{subscription:name, subscriptionId:id, tenantId:tenantId}' --output table
```

Register the required resource providers:

```powershell
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.Compute --wait
```

Create the resource group if it does not already exist:

```powershell
az group create `
  --name $resourceGroupName `
  --location $location `
  --output table
```

## Validate the Deployment

Compile the Bicep template locally:

```powershell
az bicep build --file .\main.bicep --stdout | Out-Null
```

Validate the template and parameter file against Azure Resource Manager:

```powershell
az deployment group validate `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --parameters .\main.bicepparam `
  --output table
```

Preview the proposed changes:

```powershell
az deployment group what-if `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --parameters .\main.bicepparam
```

Review the `what-if` output before continuing. The parameter file uses its `using './main.bicep'` declaration, so `--template-file` must not be supplied with these deployment commands.

## Deploy

Run the resource-group deployment:

```powershell
az deployment group create `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --parameters .\main.bicepparam `
  --output table
```

Display the deployment outputs:

```powershell
az deployment group show `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --query properties.outputs `
  --output jsonc
```

## Verify the Deployment

Read the deployed storage account name from the deployment:

```powershell
$storageAccountName = az deployment group show `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --query 'properties.parameters.storageAccountName.value' `
  --output tsv
```

Verify the storage account configuration and local users:

```powershell
az storage account show `
  --name $storageAccountName `
  --resource-group $resourceGroupName `
  --query '{name:name, location:location, hnsEnabled:isHnsEnabled, sftpEnabled:isSftpEnabled, localUsersEnabled:isLocalUserEnabled, publicNetworkAccess:publicNetworkAccess}' `
  --output table

az storage account local-user list `
  --account-name $storageAccountName `
  --resource-group $resourceGroupName `
  --query '[].{name:name, homeDirectory:homeDirectory}' `
  --output table
```

The `publicNetworkAccess` value must be `Disabled`.

Verify the per-user Blob containers:

```powershell
az storage container-rm list `
  --storage-account $storageAccountName `
  --resource-group $resourceGroupName `
  --query '[].name' `
  --output table
```

Each container name combines the configured prefix and local username. Container-level permission scopes prevent one local user from accessing another user's container.

Read the deployed public IP, private endpoint IP, and proxy VM names:

```powershell
$deploymentOutputs = az deployment group show `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --query properties.outputs `
  --output json | ConvertFrom-Json

$sftpPublicIp = $deploymentOutputs.loadBalancerPublicIpAddress.value
$storagePrivateIp = $deploymentOutputs.storageBlobPrivateEndpointIpAddress.value
$proxyVmNames = $deploymentOutputs.proxyVirtualMachineNames.value

$sftpPublicIp
$storagePrivateIp
$proxyVmNames
```

Use Azure Run Command to confirm on both instances that cloud-init installed Nginx, the Stream listener is active, and the Storage hostname resolves to the private endpoint:

```powershell
foreach ($proxyVmName in $proxyVmNames) {
  az vm run-command invoke `
    --resource-group $resourceGroupName `
    --name $proxyVmName `
    --command-id RunShellScript `
    --scripts "cloud-init status --wait" "nginx -t" "systemctl is-active nginx" "ss -lnt | grep ':2222'" "getent hosts ${storageAccountName}.blob.core.windows.net" `
    --query 'value[].message' `
    --output tsv
}
```

The resolved Storage address on both VMs must match `$storagePrivateIp`. The VMs have no public IPs and the NSG doesn't expose their SSH daemons; administer them through Azure Run Command, Azure Bastion, or a private network connection.

## Test an SFTP Connection

Create a small test file:

```powershell
Set-Content -Path .\sftp-test.txt -Value 'Azure Storage SFTP connectivity test'
```

Connect through the load balancer as the first local user. Azure Storage SFTP still uses the login format `<storage-account>.<local-user>`:

```powershell
$localUserName = 'sftpuser01'
$sftpLogin = "${storageAccountName}.${localUserName}"

sftp -i "$HOME\.ssh\azure-sftp\sftpuser01" "${sftpLogin}@${sftpPublicIp}"
```

On the first connection, verify the presented SSH host key fingerprint against the [published Azure Storage SFTP host keys](https://learn.microsoft.com/azure/storage/blobs/secure-file-transfer-protocol-host-keys) before accepting it. The load balancer and Nginx proxy don't replace or terminate the Storage SSH session.

At the interactive SFTP prompt, test the assigned permissions:

```text
pwd
ls
put sftp-test.txt
ls
get sftp-test.txt sftp-download-test.txt
rm sftp-test.txt
exit
```

The template grants `rwdlc` permissions on each user's own container: read, write, delete, list, and create. Password authentication and shared-key authentication are disabled for these local users.

## Troubleshooting

- **Storage account name unavailable:** choose another globally unique lowercase alphanumeric name in `main.bicepparam`.
- **Region does not support SFTP:** deploy to a supported Azure region by passing `location` in the parameter file or selecting a resource group in a supported region.
- **Authorization failure:** confirm the signed-in identity has deployment permissions and that the correct subscription is selected.
- **SSH authentication failure:** confirm the public key assigned to the local user matches the private key supplied with `sftp -i`.
- **Connection timeout:** confirm the client public IP is included in `allowedSftpSourceCidrs`, outbound TCP 22 is permitted by the client network, and the load balancer probe reports the proxy VM as healthy.
- **Load balancer probe unhealthy:** use Azure Run Command to inspect `cloud-init status --long`, `systemctl status nginx`, and `journalctl -u nginx` on each proxy VM.
- **Nginx can't reach Storage:** confirm `${storageAccountName}.blob.core.windows.net` resolves on the VM to the Blob private endpoint IP and TCP 22 is permitted within the virtual network.
- **Nginx package installation fails:** confirm the load balancer outbound rule and public IP are deployed and that the VM can reach Ubuntu package repositories.
- **Home directory or permission failure:** confirm that the Blob container name matches the local user's `homeDirectory` and `permissionScopes.resourceName`.

Inspect deployment errors with:

```powershell
az deployment group show `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --query properties.error `
  --output jsonc
```

## Remove the Deployment

Deleting the resource group permanently deletes the storage account and its Blob data:

```powershell
az group delete `
  --name $resourceGroupName `
  --yes
```

Confirm that no retained data or other required resources exist in the deployment resource group before running this command.