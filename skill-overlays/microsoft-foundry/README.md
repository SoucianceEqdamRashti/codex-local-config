# Microsoft Foundry skill overlay

This overlay adds private Standard File Search troubleshooting to the separately installed Microsoft Foundry skill. It was verified against version 1.2.36. It includes the reference and the two routing edits to the installed skill. It does not provide a standalone skill.

From the shared skills repository root, set the installed skill path and apply the overlay. Review a version with changed routing before applying the patch.

```powershell
$overlay = (Resolve-Path './skill-overlays/microsoft-foundry').Path
$installed = (Resolve-Path '<installed microsoft-foundry skill directory>').Path
$patch = Join-Path $overlay 'routing.patch'
$reference = 'resource/private-network/references/private-file-search-troubleshooting.md'

git -C $installed apply --check $patch
if ($LASTEXITCODE -ne 0) { throw 'The routing patch is already applied or the installed skill has changed.' }
Copy-Item -LiteralPath (Join-Path $overlay $reference) -Destination (Join-Path $installed $reference)
git -C $installed apply $patch
if ($LASTEXITCODE -ne 0) { throw 'The routing patch could not be applied.' }
```
