[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$DataFactoryName,

    [Parameter(Mandatory)]
    [string]$StorageAccountName
)

$ErrorActionPreference = 'Stop'

function Invoke-AzureCliJson {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $result = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }

    return $result | ConvertFrom-Json
}

$account = Invoke-AzureCliJson -Arguments @('account', 'show', '--output', 'json')
$sourceResourceId = "/subscriptions/$($account.id)/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"

$triggers = Invoke-AzureCliJson -Arguments @(
    'datafactory', 'trigger', 'list',
    '--resource-group', $ResourceGroupName,
    '--factory-name', $DataFactoryName,
    '--output', 'json'
)

foreach ($trigger in $triggers) {
    Write-Host "Starting ADF trigger $($trigger.name)"
    & az datafactory trigger start `
        --resource-group $ResourceGroupName `
        --factory-name $DataFactoryName `
        --name $trigger.name `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start ADF trigger $($trigger.name)."
    }
}

$eventSubscriptions = Invoke-AzureCliJson -Arguments @(
    'eventgrid', 'event-subscription', 'list',
    '--source-resource-id', $sourceResourceId,
    '--output', 'json'
)
$dataFactorySubscriptions = @($eventSubscriptions) | Where-Object {
    $_.destination.endpointBaseUrl -like '*datafactory.azure.com*'
}

if ($dataFactorySubscriptions.Count -ne @($triggers).Count) {
    throw "Expected $(@($triggers).Count) ADF Event Grid subscriptions but found $($dataFactorySubscriptions.Count)."
}

$accessToken = & az account get-access-token `
    --resource 'https://management.azure.com/' `
    --query accessToken `
    --output tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'Failed to acquire an Azure Resource Manager access token.'
}

foreach ($eventSubscription in $dataFactorySubscriptions) {
    $patchBody = @{
        filter = @{
            includedEventTypes = @($eventSubscription.filter.includedEventTypes)
            subjectBeginsWith = $eventSubscription.filter.subjectBeginsWith
            subjectEndsWith = ''
            advancedFilters = @(
                @{
                    operatorType = 'StringIn'
                    key = 'data.api'
                    values = @('SftpCommit')
                }
            )
        }
    } | ConvertTo-Json -Depth 10 -Compress

    $requestUri = "https://management.azure.com$($eventSubscription.id)?api-version=2025-02-15"
    $response = Invoke-WebRequest `
        -Method Patch `
        -Uri $requestUri `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -ContentType 'application/json' `
        -Body $patchBody `
        -SkipHttpErrorCheck

    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Failed to add SftpCommit to Event Grid subscription $($eventSubscription.name): HTTP $($response.StatusCode) $($response.Content)"
    }

    Write-Host "Configured SftpCommit-only filtering for $($eventSubscription.filter.subjectBeginsWith)"
}

Write-Host 'ADF storage event triggers are started and configured for SFTP commits.'