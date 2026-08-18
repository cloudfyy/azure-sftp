# Azure Storage SFTP Deployment Guide

This guide deploys the resources defined in `main.bicep` by using the values in `main.bicepparam`.

## Resources Deployed

- One Standard LRS `StorageV2` storage account
- Hierarchical namespace (HNS), SFTP, and local users enabled
- One private Blob container per local user, named `<prefix>-<username>`
- Exactly three SFTP local users authenticated with SSH public keys
- Each local user is restricted to its own container
- One system-assigned managed identity Azure Data Factory
- One Blob event trigger per SFTP container
- An event-driven pipeline that copies each completed, non-empty upload to an existing Azure file share
- A configurable pipeline concurrency limit; excess runs wait in the Data Factory queue
- A configurable copy timeout and retry policy
- Blob Reader and Azure Files Privileged Contributor role assignments for the Data Factory identity
- Public network access enabled and a minimum TLS version of 1.2
- No `SecurityControl` tag by default; it can be enabled through a deployment parameter

The destination path is `<share>/<container>/<relative-folder>/<file-name>`. Azure Data Factory creates Event Grid event subscriptions for the started storage event triggers; Azure may display a platform-managed System Topic associated with the source storage account.

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
- Permission to create role assignments on both storage accounts, such as `User Access Administrator` or `Owner`
- Permission for `Microsoft.EventGrid/eventSubscriptions/write` on the source storage account
- An existing Azure Files storage account and file share
- A region that supports Azure Blob Storage SFTP
- A globally unique storage account name containing 3-24 lowercase letters and numbers
- Permission to register the `Microsoft.Storage` resource provider if it is not already registered

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

Edit `main.bicepparam` and set:

- `storageAccountName` to a globally unique name
- `blobContainerName` to the container name prefix; the default creates `data-sftpuser01`, `data-sftpuser02`, and `data-sftpuser03`
- `enableSecurityControlTag` to `true` only when the storage account requires the `SecurityControl=Ignore` tag; the default is `false`
- `targetStorageResourceGroupName` to the resource group containing the existing Azure Files storage account
- `targetStorageAccountName` to the existing Azure Files storage account name
- `targetFileShareName` to the existing file share name
- `pipelineConcurrency` to the maximum simultaneous copy pipeline runs; the initial value is `10`
- `copyActivityTimeout` to the maximum duration of one copy attempt in `d.hh:mm:ss` format; the initial value is two hours
- `copyActivityRetryCount` to the number of retries after a failed copy; the initial value is `5`
- `copyActivityRetryIntervalInSeconds` to the fixed delay between retries; the initial value is `60` and the minimum is `30`
- Each `localUsers` entry to the required username and matching public key

Only public keys belong in `main.bicepparam`. Never place private key content in the parameter file or source control.

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
az provider register --namespace Microsoft.EventGrid --wait
az provider register --namespace Microsoft.DataFactory --wait
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

Start the ADF triggers and add the required `SftpCommit` Event Grid filter after each deployment:

```powershell
.\configure-adf-triggers.ps1 `
  -ResourceGroupName $resourceGroupName `
  -DataFactoryName "adf-$storageAccountName" `
  -StorageAccountName $storageAccountName
```

The Data Factory ARM API deploys storage event triggers in the stopped state and does not expose the SFTP Data API filter. The script performs these two idempotent post-deployment operations without changing the pipeline or storage data.

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

Verify the per-user Blob containers:

```powershell
az storage container-rm list `
  --storage-account $storageAccountName `
  --resource-group $resourceGroupName `
  --query '[].name' `
  --output table
```

Each container name combines the configured prefix and local username. Container-level permission scopes prevent one local user from accessing another user's container.

Verify the Data Factory pipeline and started triggers:

```powershell
$dataFactoryName = "adf-$storageAccountName"

az datafactory pipeline show `
  --factory-name $dataFactoryName `
  --resource-group $resourceGroupName `
  --name pl_copy_sftp_upload_to_azure_files `
  --query name `
  --output tsv

az datafactory trigger list `
  --factory-name $dataFactoryName `
  --resource-group $resourceGroupName `
  --query '[].{name:name, state:properties.runtimeState}' `
  --output table
```

## Test an SFTP Connection

Create a small test file:

```powershell
Set-Content -Path .\sftp-test.txt -Value 'Azure Storage SFTP connectivity test'
```

Connect as the first local user. Azure Storage SFTP uses the login format `<storage-account>.<local-user>`:

```powershell
$localUserName = 'sftpuser01'
$sftpLogin = "${storageAccountName}.${localUserName}"
$sftpHostName = "${storageAccountName}.blob.core.windows.net"

sftp -i "$HOME\.ssh\azure-sftp\sftpuser01" "${sftpLogin}@${sftpHostName}"
```

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

After the upload, verify that the file appears under `<container-name>/sftp-test.txt` in the configured Azure file share. Nested source folders are preserved below the container directory.

Azure Storage SFTP first emits `SftpCreate` and then `SftpCommit`. The post-deployment script filters Event Grid on `data.api = SftpCommit`, so only the completed upload starts the pipeline, including an intentional zero-byte file. Event Grid delivery is at least once, so a repeated event overwrites the same destination path.

The pipeline accepts up to `pipelineConcurrency` simultaneous runs. Additional event-triggered runs remain queued in Data Factory until a slot is available. Start with `10`, monitor queued duration and Azure Files throttling, and reduce the value for large files or increase it gradually after load testing. Each failed copy attempt waits `copyActivityRetryIntervalInSeconds` before retrying, up to `copyActivityRetryCount` times; the interval is fixed rather than exponential.

Azure Data Factory managed identity authentication for an Azure Files sink supports files up to 4 MB. Use a SAS or account key stored in Azure Key Vault if larger files must be copied.

## Troubleshooting

- **Storage account name unavailable:** choose another globally unique lowercase alphanumeric name in `main.bicepparam`.
- **Region does not support SFTP:** deploy to a supported Azure region by passing `location` in the parameter file or selecting a resource group in a supported region.
- **Authorization failure:** confirm the signed-in identity has deployment permissions and that the correct subscription is selected.
- **SSH authentication failure:** confirm the public key assigned to the local user matches the private key supplied with `sftp -i`.
- **Connection timeout:** verify that public network access is allowed and that outbound TCP port 22 is permitted by the client network.
- **Home directory or permission failure:** confirm that the Blob container name matches the local user's `homeDirectory` and `permissionScopes.resourceName`.
- **Trigger creation fails:** confirm the deployment identity can create Event Grid event subscriptions on the source storage account.
- **Copy activity authorization fails:** allow time for the managed identity role assignments to propagate, then rerun or upload the file again.
- **Files larger than 4 MB fail:** managed identity authentication has an Azure Files sink limit; configure a Key Vault-backed SAS or account key instead.

Inspect deployment errors with:

```powershell
az deployment group show `
  --name $deploymentName `
  --resource-group $resourceGroupName `
  --query properties.error `
  --output jsonc
```

## Remove the Deployment

Deleting the resource group permanently deletes the source storage account, its Blob data, and the Data Factory:

```powershell
az group delete `
  --name $resourceGroupName `
  --yes
```

The existing destination Azure Files storage account and share are not deleted when they are in a different resource group. Confirm that no retained data or other required resources exist in the deployment resource group before running this command.