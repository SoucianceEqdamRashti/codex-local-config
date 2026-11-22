#Requires -Version 7.0

function Invoke-AzNative {
    param([string[]]$Arguments)

    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        $PSNativeCommandUseErrorActionPreference = $false
        $cli = Get-Command az -CommandType Application -ErrorAction Stop | Select-Object -First 1
        # az.cmd passes through cmd.exe on Windows. Reject shell metacharacters before invocation.
        if ($cli.Source -match '\.(cmd|bat)$' -and @($Arguments -match '[\x00-\x1f"&|<>^%!()]').Count) {
            throw 'The Windows Azure CLI launcher cannot safely accept one of the arguments. Use paths and names without cmd.exe metacharacters.'
        }
        $stdout = & $cli.Source @Arguments --output json --only-show-errors 2> $stderrPath | Out-String
        return @{
            ExitCode = $LASTEXITCODE
            Stdout = $stdout
            Stderr = [IO.File]::ReadAllText($stderrPath)
        }
    }
    finally {
        Remove-Item -LiteralPath $stderrPath -ErrorAction SilentlyContinue
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments, [string]$Artifact)

    $response = Invoke-AzNative -Arguments $Arguments
    if ($Artifact) {
        [IO.File]::WriteAllText("$Artifact.json", $response.Stdout)
        [IO.File]::WriteAllText("$Artifact.stderr.txt", $response.Stderr)
    }
    $data = $null
    $errorMessage = $null
    if ($response.ExitCode -ne 0) {
        $errorMessage = "Azure CLI exited with code $($response.ExitCode)."
    }
    if ($response.Stdout.Trim()) {
        try {
            $data = ConvertFrom-Json -InputObject $response.Stdout -AsHashtable -NoEnumerate -ErrorAction Stop
        }
        catch {
            if (!$errorMessage) { $errorMessage = 'Azure CLI returned malformed JSON.' }
        }
    }
    if (!$errorMessage -and $null -eq $data) { $errorMessage = 'Azure CLI returned no JSON data.' }
    return @{ ExitCode = $response.ExitCode; Data = $data; Error = $errorMessage }
}

function ConvertTo-StackChangeSummary {
    param([System.Collections.IDictionary]$Preview)

    $body = $Preview.properties ?? $Preview
    if ($body.error -or ($body.provisioningState -and $body.provisioningState -ne 'Succeeded') -or
        $body.changes.resourceChanges -isnot [array]) {
        throw 'The stack what-if did not return a completed resource change array.'
    }
    $seen = @{}
    foreach ($change in $body.changes.resourceChanges) {
        $id = $change.id
        $unresolved = $id -match '^\[[\s\S]+\]$' -and
            ($change.changeType -eq 'unsupported' -or $change.changeCertainty -eq 'potential')
        if ((!$unresolved -and $id -notmatch '^/subscriptions/[^/]+(?:/[^/]+)+$') -or $seen.ContainsKey($id)) {
            throw 'The stack what-if returned a missing, invalid or duplicate ARM resource ID.'
        }
        $seen[$id] = $true
        $segments = ($id -split '/providers/')[-1] -split '/'
        $resourceType = $change.type
        if ($unresolved) {
            $resourceType = $resourceType ?? 'Unknown'
        }
        elseif (!$resourceType) {
            if ($id -notmatch '/providers/') {
                $resourceType = 'Microsoft.Resources/resourceGroups'
            }
            else {
                $types = for ($i = 1; $i -lt $segments.Count; $i += 2) { $segments[$i] }
                $resourceType = "$($segments[0])/$($types -join '/')"
            }
        }
        $action = switch ($change.changeType) {
            'create' { 'Create' }
            'modify' { 'Modify' }
            'delete' { 'Delete' }
            'detach' { 'Detach' }
            'noChange' { 'Unchanged' }
            default { 'Uncertain' }
        }
        if ($unresolved -or ($change.changeCertainty -eq 'potential' -and $action -notin 'Delete','Detach')) {
            $action = 'Uncertain'
        }
        $resourceName = if ($unresolved) { $change.symbolicName ?? '(unresolved resource ID)' } else { ($id -split '/')[-1] }
        [pscustomobject]@{
            Resource = $resourceName
            ResourceId = $id
            ResourceType = $resourceType
            PlannedAction = $action
            Certainty = $change.changeCertainty
            ManagementStatusChange = $change.managementStatusChange
            DenyStatusChange = $change.denyStatusChange
            ApiVersion = $change.apiVersion
            Delta = @($change.resourceConfigurationChanges.delta | Where-Object { $null -ne $_ })
            Configuration = $change.resourceConfigurationChanges
            UnsupportedReason = $change.unsupportedReason
        }
    }
}

function Test-ResourceDelta {
    param($Delta, $Live)

    $verified = 0
    $inconclusive = $false
    foreach ($property in $Delta) {
        if ($property.changeType -eq 'noEffect') { continue }
        # Use directly addressable scalar values. ARM can omit, normalize, or redact other paths.
        if ($property.changeType -notin 'modify','create' -or $property.children -or
            $property.path -notmatch '^[\w-]+(\.[\w-]+)*$' -or
            $property.path -match '(^|\.)(provisioningState|etag|systemData|id)(\.|$)' -or
            $null -eq $property.after -or $property.after -is [System.Collections.ICollection] -or
            ($property.after -is [string] -and $property.after -match '^\[')) {
            $inconclusive = $true
            continue
        }
        $value = $Live
        foreach ($key in $property.path.Split('.')) {
            if ($value -isnot [System.Collections.IDictionary] -or !$value.Contains($key)) {
                $value = $null
                break
            }
            $value = $value[$key]
        }
        if ($null -eq $value) {
            $inconclusive = $true
            continue
        }
        if ((ConvertTo-Json -InputObject $value -Compress -Depth 100) -cne
            (ConvertTo-Json -InputObject $property.after -Compress -Depth 100)) {
            return 'Mismatch'
        }
        $verified++
    }
    if ($verified -and !$inconclusive) { return 'Match' }
    return 'Not Verified'
}

function Compare-StackDeployment {
    param([object[]]$Plan, [hashtable]$Evidence)

    $plannedIds = @{}
    foreach ($item in $Plan) {
        $plannedIds[$item.ResourceId] = $true
        $record = $Evidence[$item.ResourceId]
        $actual = 'Unknown'
        $result = 'Not Verified'
        if ($record.Failed) {
            $actual = 'Failed'
            $result = 'Failed'
        }
        elseif ($record.Deleted -or $record.Detached -or $record.Created) {
            $actual, $matchingAction = if ($record.Deleted) { 'Deleted','Delete' }
                elseif ($record.Detached) { 'Detached','Detach' }
                else { 'Created','Create' }
            $result = if ($item.PlannedAction -eq $matchingAction) { 'Match' }
                elseif ($item.PlannedAction -eq 'Uncertain') { 'Not Verified' }
                else { 'Mismatch' }
        }
        elseif ($item.PlannedAction -eq 'Modify' -and $record.Live) {
            $result = Test-ResourceDelta $item.Delta $record.Live
            if ($result -eq 'Match') { $actual = 'Modified' }
            if ($result -eq 'Mismatch') { $actual = 'Property differs' }
        }
        elseif ($item.PlannedAction -eq 'Unchanged' -and $record.PostAction -eq 'Unchanged' -and $record.PostCertainty -ne 'potential') {
            $actual = 'No residual change'
            $result = 'Match'
        }
        [pscustomobject]@{
            Resource = $item.Resource; ResourceId = $item.ResourceId
            Expected = $item.PlannedAction; Actual = $actual; Result = $result
            PostPreview = $record.PostAction
        }
    }
    foreach ($id in ($Evidence.Keys | Sort-Object)) {
        if ($plannedIds.ContainsKey($id)) { continue }
        $record = $Evidence[$id]
        $actual = if ($record.Failed) { 'Failed' }
            elseif ($record.Deleted) { 'Deleted' }
            elseif ($record.Detached) { 'Detached' }
            elseif ($record.Created) { 'Created' }
            else { continue }
        [pscustomobject]@{
            Resource = ($id -split '/')[-1]; ResourceId = $id
            Expected = 'None'; Actual = $actual; Result = 'Unexpected'
            PostPreview = $record.PostAction
        }
    }
}

function Get-StackPlanHash {
    param($Settings, $Files, $Changes, [string]$StackLastModified)

    $payload = [ordered]@{
        Settings = $Settings
        Files = @($Files | ForEach-Object { (Get-FileHash -LiteralPath $_ -ErrorAction Stop).Hash })
        StackLastModified = $StackLastModified
        Changes = $Changes
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $payload -Depth 100 -Compress))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-StackOperations {
    param([string]$DeploymentId, [string]$Directory)

    $visited = @{}
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($DeploymentId)
    while ($queue.Count) {
        $id = $queue.Dequeue()
        if ($visited.ContainsKey($id) -or
            $id -notmatch '^/subscriptions/([^/]+)(?:/resourceGroups/([^/]+))?/providers/Microsoft\.Resources/deployments/([^/]+)$') {
            continue
        }
        $visited[$id] = $true
        $scope = if ($Matches[2]) { 'group' } else { 'sub' }
        $command = @('deployment','operation',$scope,'list','--subscription',$Matches[1],'--name',$Matches[3])
        if ($Matches[2]) { $command += @('--resource-group',$Matches[2]) }
        $response = Invoke-AzJson $command (Join-Path $Directory "operations-$($visited.Count)")
        if ($response.Error -or $response.Data -isnot [array]) { continue }
        foreach ($operation in $response.Data) {
            $operation
            $target = $operation.properties.targetResource
            if ($target.resourceType -eq 'Microsoft.Resources/deployments' -and $target.id) {
                $queue.Enqueue($target.id)
            }
        }
    }
}

function Get-StackEvidence {
    param($Stack, $Operations)

    $evidence = @{}
    $Stack = $Stack ?? @{}
    $stackRecords = [ordered]@{ deletedResources = 'Deleted'; detachedResources = 'Detached'; failedResources = 'Failed' }
    foreach ($key in $stackRecords.Keys) {
        foreach ($resource in $Stack[$key]) {
            if (!$resource.id) { continue }
            if (!$evidence.ContainsKey($resource.id)) { $evidence[$resource.id] = @{} }
            $evidence[$resource.id][$stackRecords[$key]] = $true
        }
    }
    foreach ($operation in $Operations) {
        $details = $operation.properties
        $id = $details.targetResource.id
        if ($id -notmatch '^/subscriptions/' -or $details.targetResource.resourceType -eq 'Microsoft.Resources/deployments') { continue }
        if (!$evidence.ContainsKey($id)) { $evidence[$id] = @{} }
        if ($details.provisioningState -in 'Failed','Canceled') { $evidence[$id].Failed = $true }
        if ($details.provisioningState -ne 'Succeeded') { continue }
        if ($details.provisioningOperation -eq 'Delete') { $evidence[$id].Deleted = $true }
        if ($details.statusCode -in 'Created',201 -and $details.provisioningOperation -in 'Create','CreateOrUpdate') {
            $evidence[$id].Created = $true
        }
    }
    return $evidence
}

function Invoke-StackWorkflow {
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
    $directory = $null
    $report = [ordered]@{ ExitCode = 2; Status = 'PreviewFailed'; Error = $null }
    try {
        if (($Scope -eq 'group' -and (!$ResourceGroup -or $Location)) -or
            ($Scope -eq 'sub' -and (!$Location -or $ResourceGroup))) {
            throw 'Supply ResourceGroup for group scope or Location for subscription scope.'
        }
        $template = (Get-Item -LiteralPath $TemplateFile).FullName
        $parameterPaths = @($ParameterFile | Where-Object { $_ } | ForEach-Object { (Get-Item -LiteralPath $_).FullName })
        $files = @($template) + $parameterPaths
        $directory = (New-Item -Force -ItemType Directory -Path (Join-Path $OutputDirectory ([guid]::NewGuid().ToString('N')))).FullName
        $report.OutputDirectory = $directory
        $stackScope = "/subscriptions/$Subscription"
        $common = @('--subscription',"$Subscription",'--action-on-unmanage',$ActionOnUnmanage,
            '--deny-settings-mode',$DenySettingsMode,'--resources-without-delete-support','fail')
        if ($Scope -eq 'group') {
            $stackScope += "/resourceGroups/$ResourceGroup"
            $common += @('--resource-group',$ResourceGroup)
        }
        else { $common += @('--location',$Location) }
        if ($DenySettingsApplyToChildScopes) { $common += '--deny-settings-apply-to-child-scopes' }
        if (@($parameterPaths -match '\.bicepparam$').Count -and $parameterPaths.Count -ne 1) {
            throw 'Use a single .bicepparam file or one or more JSON parameter files.'
        }
        $common += @('--template-file',$template)
        foreach ($file in $parameterPaths) {
            $parameter = if ($file -match '\.bicepparam$') { $file } else { "@$file" }
            $common += @('--parameters',$parameter)
        }
        $stackId = "$stackScope/providers/Microsoft.Resources/deploymentStacks/$StackName"
        $report.StackId = $stackId
        $report.ActionOnUnmanage = $ActionOnUnmanage
        $report.DenySettingsMode = $DenySettingsMode
        $report.DenySettingsApplyToChildScopes = [bool]$DenySettingsApplyToChildScopes
        $previewCommand = @('stack-whatif',$Scope,'create','--no-pretty-print','--retention-interval','P1D','--stack-id',$stackId)
        $initialFilesHash = Get-StackPlanHash @() $files @() ''
        $preview = Invoke-AzJson ($previewCommand + @('--name',"preview-$([guid]::NewGuid().ToString('N'))") + $common) (Join-Path $directory 'what-if')
        if ($preview.Error) { throw $preview.Error }
        if ((Get-StackPlanHash @() $files @() '') -ne $initialFilesHash) {
            throw 'The template or parameter files changed during preview.'
        }
        $plan = @(ConvertTo-StackChangeSummary $preview.Data)
        $previewBody = $preview.Data.properties ?? $preview.Data
        $report.Plan = $plan
        $report.PreviewId = $preview.Data.id
        $report.StackChanges = $previewBody.changes
        $report.Totals = [ordered]@{}
        $actions = [ordered]@{ Created = 'Create'; Modified = 'Modify'; Deleted = 'Delete'; Detached = 'Detach'; Unchanged = 'Unchanged'; Uncertain = 'Uncertain' }
        foreach ($label in $actions.Keys) {
            $report.Totals[$label] = @($plan | Where-Object PlannedAction -EQ $actions[$label]).Count
        }
        $settings = @($stackId,$ActionOnUnmanage,$DenySettingsMode,[bool]$DenySettingsApplyToChildScopes,$Location)
        $fingerprintChanges = [ordered]@{
            Resources = @($plan | Sort-Object ResourceId)
            DenySettings = $previewBody.changes.denySettingsChange
            DeploymentScope = $previewBody.changes.deploymentScopeChange
        }
        $report.PlanHash = Get-StackPlanHash $settings $files $fingerprintChanges $previewBody.deploymentStackLastModified
        $plan | Format-Table Resource, ResourceType, PlannedAction, Certainty, ResourceId -AutoSize | Out-Host
        foreach ($item in ($plan | Where-Object PlannedAction -In 'Delete','Detach','Uncertain')) {
            Write-Host "$($item.PlannedAction) $($item.ResourceId)"
        }
        Write-Host (($report.Totals.Keys | ForEach-Object { "$_=$($report.Totals[$_])" }) -join '  ')
        Write-Host "Stack $stackId | Unmanage policy $ActionOnUnmanage | Deny settings $DenySettingsMode"
        Write-Host "Plan hash $($report.PlanHash)"
        Write-Host "Artifacts $directory"
        if ($WhatIfOnly) {
            $report.ExitCode = 0
            $report.Status = 'PreviewOnly'
            return [pscustomobject]$report
        }

        $report.ExitCode = 4
        $report.Status = 'ApprovalRequired'
        if (!$AllowUnmanage -and ($ActionOnUnmanage -ne 'detachAll' -or $report.Totals.Deleted -or $report.Totals.Detached -or $report.Totals.Uncertain)) {
            throw 'Deployment requires -AllowUnmanage to acknowledge the policy and any planned or uncertain removals.'
        }
        if ($ApprovedPlanHash) {
            if ($ApprovedPlanHash -ne $report.PlanHash) { throw 'The reviewed plan hash differs from the fresh preview.' }
        }
        else {
            if ((Read-Host 'Type the displayed plan hash to approve this stack deployment') -ne $report.PlanHash) {
                throw 'Deployment approval was declined.'
            }
            $refresh = Invoke-AzJson ($previewCommand + @('--name',"approve-$([guid]::NewGuid().ToString('N'))") + $common) (Join-Path $directory 'approval-what-if')
            if ($refresh.Error) { throw $refresh.Error }
            $refreshBody = $refresh.Data.properties ?? $refresh.Data
            $refreshedChanges = [ordered]@{
                Resources = @(ConvertTo-StackChangeSummary $refresh.Data | Sort-Object ResourceId)
                DenySettings = $refreshBody.changes.denySettingsChange
                DeploymentScope = $refreshBody.changes.deploymentScopeChange
            }
            if ((Get-StackPlanHash $settings $files $refreshedChanges $refreshBody.deploymentStackLastModified) -ne $report.PlanHash) {
                throw 'The reviewed plan changed while waiting for approval. Review a fresh preview.'
            }
        }
        if ((Get-StackPlanHash $settings $files $fingerprintChanges $previewBody.deploymentStackLastModified) -ne $report.PlanHash) {
            throw 'The template or parameter files changed after preview.'
        }

        $report.ExitCode = 3
        $report.Status = 'DeploymentFailed'
        $deployment = Invoke-AzJson (@('stack',$Scope,'create','--name',$StackName) + $common) (Join-Path $directory 'deployment')
        $stack = $deployment.Data.properties ?? $deployment.Data
        $report.Deployment = [ordered]@{
            ExitCode = $deployment.ExitCode; Error = $deployment.Error; Status = $stack.provisioningState
            DeploymentId = $stack.deploymentId; CorrelationId = $stack.correlationId
        }
        $deploymentSucceeded = !$deployment.Error -and $stack.provisioningState -eq 'Succeeded'
        $operations = @(Get-StackOperations $stack.deploymentId $directory | Where-Object { $_ })
        $report.OperationIds = @($operations | ForEach-Object { $_.id ?? $_.operationId } | Where-Object { $_ })
        $evidence = Get-StackEvidence $stack $operations
        if ($deploymentSucceeded) {
            $report.ExitCode = 5
            $report.Status = 'Discrepancies'
            $post = Invoke-AzJson ($previewCommand + @('--name',"verify-$([guid]::NewGuid().ToString('N'))") + $common) (Join-Path $directory 'post-what-if')
            try {
                if ($post.Error) { throw $post.Error }
                $report.PostPlan = @(ConvertTo-StackChangeSummary $post.Data)
                foreach ($item in $report.PostPlan) {
                    if (!$evidence.ContainsKey($item.ResourceId)) { $evidence[$item.ResourceId] = @{} }
                    $evidence[$item.ResourceId].PostAction = $item.PlannedAction
                    $evidence[$item.ResourceId].PostCertainty = $item.Certainty
                }
            }
            catch { $report.PostPreviewError = $_.Exception.Message }
        }
        $reads = @($plan | Where-Object { $_.PlannedAction -eq 'Modify' -and !$evidence[$_.ResourceId].Failed })
        for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
            for ($i = 0; $i -lt $reads.Count; $i++) {
                $item = $reads[$i]
                if (!$evidence.ContainsKey($item.ResourceId)) { $evidence[$item.ResourceId] = @{} }
                $record = $evidence[$item.ResourceId]
                $command = @('resource','show','--ids',$item.ResourceId)
                if ($item.ApiVersion) { $command += @('--api-version',$item.ApiVersion) }
                $live = Invoke-AzJson $command (Join-Path $directory "resource-$i-attempt-$attempt")
                $record.Live = $null
                if (!$live.Error -and $live.Data.id -eq $item.ResourceId) { $record.Live = $live.Data }
            }
            $report.Reconciliation = @(Compare-StackDeployment $plan $evidence)
            if (!$reads.Count -or !@($report.Reconciliation | Where-Object {
                $_.Expected -in 'Create','Modify' -and $_.Result -in 'Mismatch','Not Verified'
            }).Count) { break }
            if ($attempt -lt $VerificationAttempts) { Start-Sleep -Seconds (2 * $attempt) }
        }

        $report.Reconciliation | Format-Table Resource, Expected, Actual, Result, ResourceId -AutoSize | Out-Host
        if ($deploymentSucceeded -and !$report.PostPreviewError -and !@($report.Reconciliation | Where-Object Result -NE 'Match').Count) {
            $report.ExitCode = 0
            $report.Status = 'Reconciled'
        }
    }
    catch {
        $report.Error = $_.Exception.Message
        Write-Warning $report.Error
    }
    finally {
        if ($directory) {
            if ($Markdown) {
                $lines = @('# Azure deployment stack', '', "Status **$($report.Status)**", '', '| Resource ID | Planned action |', '| --- | --- |')
                $lines += @($report.Plan | ForEach-Object { "| $($_.ResourceId -replace '\|','&#124;') | $($_.PlannedAction) |" })
                if ($report.Reconciliation) {
                    $lines += @('', '| Resource ID | Expected | Actual | Result |', '| --- | --- | --- | --- |')
                    $lines += @($report.Reconciliation | ForEach-Object {
                        "| $($_.ResourceId -replace '\|','&#124;') | $($_.Expected) | $($_.Actual) | $($_.Result) |"
                    })
                }
                $lines | Set-Content -LiteralPath (Join-Path $directory 'summary.md') -Encoding utf8
            }
            ConvertTo-Json -InputObject $report -Depth 100 | Set-Content -LiteralPath (Join-Path $directory 'report.json') -Encoding utf8
        }
    }
    return [pscustomobject]$report
}

Export-ModuleMember -Function Invoke-StackWorkflow, ConvertTo-StackChangeSummary, Compare-StackDeployment

