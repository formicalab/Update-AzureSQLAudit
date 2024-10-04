#requires -version 7

<#
    .SYNOPSIS
    Enable/Disable audit for a list of Azure SQL Servers.

    .DESCRIPTION
    This script reads a CSV file with a list of Azure SQL Servers and enables or disables audit for each of them.
    If the -EnableAudit switch is specified, the script will enable audit for the server.
    If the -DisableAudit switch is specified, the script will disable audit for the server.
    If neither -EnableAudit nor -DisableAudit are specified, the script will only check the current status of the audit.

    .PARAMETER CSVFile
    The path to the CSV file with the list of Azure SQL servers. The file must have a header with at least the following columns:
    - subscriptionName: the name of the subscription
    - resourceGroup: the name of the resource group
    - name: the name of the Azure SQL Server

    .PARAMETER WorkspaceId
    The Id of the log analytics workspace to use for audit.

    .PARAMETER EnableAudit
    If specified, enables audit for the Azure sql servers.

    .PARAMETER DisableAudit
    If specified, disables audit for the Azure sql servers.

    .EXAMPLE
    .\Update-AzureSQLAudit.ps1 -CSVFile .\sqlServers.csv -WorkspaceId "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/myworkspace" -EnableAudit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Specify the CSV file with the list of Azure SQL Servers")]
    [string]$CSVFile,
     
    [Parameter(Mandatory = $false, HelpMessage = "Specify the Id of the log analytics workspace to use")]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $false, HelpMessage = "Specify if you want to enable audit settings")]
    [switch]$EnableAudit,

    [Parameter(Mandatory = $false, HelpMessage = "Specify if you want to disable audit settings")]
    [switch]$DisableAudit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# if EnableAudit and DisableAudit are both specified, throw an error
if ($EnableAudit -and $DisableAudit) {
    throw "You cannot specify both -EnableAudit and -DisableAudit"
}

# if EnableAudit is specified but WorkspaceId is not, throw an error
if ($EnableAudit -and -not $WorkspaceId) {
    throw "You must specify the -WorkspaceId parameter when using -EnableAudit"
}

# read the last line of the file and try to understand if delimiter is ; or ,
$delimiter = ','
$csvContent = Get-Content -Path $CSVFile -Tail 1
if ($csvContent -match ';') {
    $delimiter = ';'
}

# verify that Az module is installed
if (-not (Get-Module -Name Az -ListAvailable)) {
    throw "You must install the Az module before running this script"
}

# verify that we have an active context
if (-not (Get-AzContext)) {
    throw "You must be logged in to Azure before running this script (use: Connect-AzAccount)"
}

# import the list of Azure SQL Servers
$sqlServers = Import-Csv -Path $CSVFile -Delimiter $delimiter

# save current subscription
$currentSubscription = (Get-AzContext).Subscription.Name

# Iterate through each Azure SQL Server and fetch audit status
Write-Host "Processing $($sqlServers.Count) Azure SQL Servers..."
$i = 0
$sqlServers | Foreach-Object  {

    $i++
    Write-Host -NoNewline "[$i] $($_.subscriptionName): $($_.resourceGroup)/$($_.name): "

    # if the subscription is different from the current one, switch to it
    if ($currentSubscription -ne $_.subscriptionName) {
        Set-AzContext -SubscriptionName $_.subscriptionName | Out-Null
        $currentSubscription = $_.subscriptionName
    }

    $currentAuditSettings =  Get-AzSqlServerAudit -ResourceGroupName $_.ResourceGroup -ServerName $_.Name  -WarningAction SilentlyContinue
    $ourAuditAlreadyInUse = ($currentAuditSettings.LogAnalyticsTargetState -eq "Enabled") -and ($currentAuditSettings.WorkspaceResourceId -eq $WorkspaceId)
    
    if ($currentAuditSettings.LogAnalyticsTargetState -eq "Disabled") {
        if ($EnableAudit) {
            Set-AzSqlServerAudit -ResourceGroupName $_.ResourceGroup -ServerName $_.Name -LogAnalyticsTargetState Enabled -WorkspaceResourceId $WorkspaceId
            Write-Host "Enabled"
        }
        else {
            Write-Host "---"
        }
    }
    else {
        if ($EnableAudit) {
            if ($ourAuditAlreadyInUse) {
                Write-Host "Already enabled"
            }
            else {
                Write-Host "Skipped (other settings in use, check manually)"
            }
        }
        elseif ($DisableAudit) {
            if ($ourAuditAlreadyInUse) {
                Set-AzSqlServerAudit -ResourceGroupName $_.ResourceGroup -ServerName $_.Name -LogAnalyticsTargetState Disabled -WorkspaceResourceId $null\
                Write-Host "Disabled"
            }
            else {
                Write-Host "Skipped (other settings in use, check manually)"
            }
        }
        else {
            if ($ourAuditAlreadyInUse) {
                Write-Host "Already enabled"
            }
            else {
                Write-Host "Other settings in use"
            }
        }
    }
}