#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TemplateFile,
    [Parameter(Mandatory)][string]$SnapshotParameterFile,
    [Parameter(Mandatory)][string[]]$DeploymentParameterFile,
    [Parameter(Mandatory)][guid]$Subscription,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$StackName,
    [guid]$SnapshotSubscription = 'aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e',
    [string]$SnapshotResourceGroup = 'rg-products-snapshot',
    [string]$SnapshotLocation = 'swedencentral',
    [string]$BicepCommand = 'bicep',
    [string]$OutputDirectory = './stack-reports'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

Write-Host '=== Bicep snapshot validation ==='
$snapshotExit = 1
try {
    $snapshotFile = (Get-Item -LiteralPath $SnapshotParameterFile).FullName
    $bicep = Get-Command $BicepCommand -CommandType Application, ExternalScript | Select-Object -First 1
    & $bicep.Source snapshot $snapshotFile --mode validate --subscription-id "$SnapshotSubscription" --resource-group $SnapshotResourceGroup --location $SnapshotLocation
    $snapshotExit = $LASTEXITCODE
}
catch {
    Write-Warning "Snapshot validation could not run. $($_.Exception.Message)"
}
Write-Host "Snapshot exit code $snapshotExit"

Write-Host ''
Write-Host '=== Azure deployment stack what-if ==='
$stackExit = 2
try {
    $workflow = Join-Path $PSScriptRoot 'Invoke-StackWorkflow.ps1'
    $stackInputs = @{
        Scope = 'group'
        Subscription = $Subscription
        ResourceGroup = $ResourceGroup
        StackName = $StackName
        TemplateFile = $TemplateFile
        ParameterFile = $DeploymentParameterFile
        OutputDirectory = $OutputDirectory
        WhatIfOnly = $true
        Markdown = $true
    }
    & $workflow @stackInputs
    $stackExit = $LASTEXITCODE
}
catch {
    Write-Warning "Stack what-if could not run. $($_.Exception.Message)"
}
Write-Host "Stack what-if exit code $stackExit"

if ($stackExit -ne 0) { exit $stackExit }
exit $snapshotExit
