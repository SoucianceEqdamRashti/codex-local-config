---
name: azure-stack-tool
description: Validate Bicep changes with snapshots and use the bundled PowerShell workflow to preview, deploy, and reconcile Azure Deployment Stacks at resource-group or subscription scope.
---

## Bicep snapshots

Use Bicep CLI 0.41.2 or later. Use a repository-specific test .bicepparam file with nonsecret fixture values and fixed synthetic deployment context. Use the repository's pinned CLI version and existing snapshot conventions when available.

```powershell
bicep snapshot ./infra/example.preview.bicepparam --mode validate --subscription-id aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e --resource-group rg-bicep-snapshot --location swedencentral
```

Use the same arguments with `--mode overwrite` to create the first baseline or accept an intentional change after reviewing the diff. Review and commit the generated baseline with the Bicep changes. Snapshot validation evaluates the template locally. The live stack what-if checks Azure state and stack actions.

## Stack preview and deployment

Resolve `scripts/Invoke-StackWorkflow.ps1` relative to this skill directory. Pass the target subscription GUID, stack name, scope, template and deployment-specific parameter files. Use `-ResourceGroup` for `-Scope group` or `-Location` for `-Scope sub`. For a resource-group target, `scripts/Invoke-InfraPreviews.ps1` can run snapshot validation and the live what-if together with separate headings and exit codes. Pass the explicit template file and separate snapshot and deployment parameter files.

```powershell
$workflow = Join-Path $skillDirectory 'scripts/Invoke-StackWorkflow.ps1'
$inputs = @{
    Scope = 'group'
    Subscription = $subscriptionId
    ResourceGroup = $resourceGroup
    StackName = $stackName
    TemplateFile = $templateFile
    ParameterFile = $deploymentParameterFile
}
& $workflow @inputs -WhatIfOnly -Markdown
& $workflow @inputs -ApprovedPlanHash $approvedPlanHash -Markdown
```

Run the first command to preview. It creates an expiring Azure what-if record. Show the change table, full IDs for deletes and detaches, uncertain changes, the unmanage policy, and the report path. Keep raw reports access-restricted because Azure responses may contain sensitive values.

Run the second command only after the user approves the reviewed plan and settings. Feed the reviewed `PlanHash` from `report.json` into `-ApprovedPlanHash` with the same inputs. If the fresh preview changes the hash, present the new plan and obtain fresh approval. Pass `-AllowUnmanage` only with explicit authorization for the policy and possible removals.

Summarize the deployment state and reconciliation report. A successful deployment operation alone cannot establish a property change. Preserve `Not Verified` for inconclusive rows. Workflow exit codes are 0 for successful preview or reconciliation, 2 for preview failure, 3 for deployment failure, 4 for approval failure, and 5 for reconciliation discrepancies.
