#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('group','sub')][string]$Scope,
    [Parameter(Mandatory)][guid]$Subscription,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$StackName,
    [Parameter(Mandatory)][string]$TemplateFile,
    [string[]]$ParameterFile,
    [string]$ResourceGroup,
    [string]$Location,
    [ValidateSet('detachAll','deleteResources','deleteAll')][string]$ActionOnUnmanage = 'detachAll',
    [ValidateSet('none','denyDelete','denyWriteAndDelete')][string]$DenySettingsMode = 'none',
    [switch]$DenySettingsApplyToChildScopes,
    [switch]$AllowUnmanage,
    [switch]$WhatIfOnly,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ApprovedPlanHash,
    [switch]$Markdown,
    [string]$OutputDirectory = './stack-reports',
    [ValidateRange(1,10)][int]$VerificationAttempts = 3
)
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot/AzureStackTool.psm1" -Force -ErrorAction Stop
$report = Invoke-StackWorkflow @PSBoundParameters
Write-Host "Stack workflow finished with status $($report.Status)"
exit $report.ExitCode

