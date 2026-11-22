---
name: bicep-docs
description: Generate or check Markdown and HTML documentation for Bicep deployment entrypoints. Use when Bicep infrastructure or its dependencies are added or changed, or when someone asks to regenerate or verify Bicep reports.
---

# Bicep documentation

Identify the deployment entrypoints affected by the change, including entrypoints that import changed local Bicep files. Prefer a repository-provided generator and its output conventions. Use the bundled generator when a repository has no generator.

Run [Update-BicepDocs.ps1](scripts/Update-BicepDocs.ps1) from PowerShell 7 with Bicep CLI 0.49.2. Pass one or more source paths with `-EntryPoint`. Use `-BicepPath` if the pinned CLI is outside PATH. Use `-NoRestore` only when the referenced modules are already cached.

The generator creates `bicep_readme.md` and `bicep_report.html` beside each `main.bicep`. Other entrypoints use their base name followed by `.bicep_readme.md` and `.bicep_report.html`. An adjacent `bicep-docs-values.json` can map `title` and individual output names to display strings for the HTML report. The default HTML configuration supplies the bundled Scriban template. If a project relies on custom module aliases or other compilation settings, pass `-HtmlConfig` pointing to a project configuration that carries those settings and selects the HTML Scriban template.

For CI, keep the generator, template, and configuration in the repository so the check can run without Codex. Pass all intended entrypoints and `-Check` to detect stale or missing reports. Include the entrypoints, their dependencies, and documentation inputs and outputs in the check's change coverage.

Generate from the Bicep source contract. Keep environment parameter values and secrets out of report inputs.
