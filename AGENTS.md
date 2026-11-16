
# Global Development Instructions

## General
- Prefer simple, maintainable solutions.
- Follow existing project conventions.
- Avoid unnecessary abstractions.
- Work incrementally.
- Ask when requirements are ambiguous.
- Never introduce secrets into source control.

## .NET
- Prefer modern C# and supported .NET versions from dotnet 10+.
- Use dependency injection and async/await.
- Follow SOLID principles pragmatically.
- Use structured logging.
- Handle cancellation and exceptions.
- Avoid magic strings and duplicated logic.
- Use Vertical Slice Architecture with names focusing on domain and intent.

## Azure
- Prefer managed identities.
- Apply least privilege.
- Use IaC for infrastructure.
- Consider observability, cost and resilience.
- Follow Azure Well-Architected principles.

## Testing
- Use xUnit for .NET tests.
- Prefer Given_When_Then test naming.
- Test behavior rather than implementation.
- Run relevant tests after changes.

## Agent Delegation
- requirements: unclear or complex requirements.
- architect: significant design decisions.
- dotnet-coder: C# implementation.
- azure-infra: Azure and IaC changes.
- tester: testing and coverage analysis.
- ui-ux: UI implementation and UX reviews.

Delegate only when useful.
Run independent tasks in parallel.
Avoid concurrent edits to the same files.
The main agent owns final integration.
Report which agents were used.
