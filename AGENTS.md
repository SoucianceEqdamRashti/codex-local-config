# Shared Engineering Instructions for Codex

## Scope and Precedence

These are default engineering rules for all agents. Follow more specific repository `AGENTS.md` instructions and the assigned agent role when they apply. Do not impose .NET conventions on Bicep, documentation, or CI/CD-only work. Inspect the repository, existing conventions, SDK pinning, and relevant skills before changing code. Preserve compatible existing architecture unless a change is requested and justified.

## Operating Workflow

1. Understand the request, success criteria, constraints, and affected files. Ask only for consequential missing decisions; state reasonable assumptions.
2. Inspect existing code, tests, configuration, and dependencies. Prefer small, incremental changes over broad rewrites.
3. For nontrivial changes, describe a short plan and identify the smallest useful vertical increment.
4. Follow TDD for behavior changes: write a meaningful failing test, run it to confirm the expected failure, implement the smallest change, rerun, and refactor with tests green. For infrastructure or documentation, use appropriate validation instead.
5. Run focused checks first, then relevant broader checks. Never claim validation succeeded if it was not executed.
6. Summarize changed behavior, tests and commands run, remaining risks, and any assumptions.

## Platform and Language

- For new .NET projects, default to the latest supported stable .NET SDK and runtime available in the environment; target .NET 10 / C# 14 or later when supported. Respect `global.json`, existing target frameworks, deployment constraints, and project compatibility. If a `global.json` file does not exist, then create one.
- Enable nullable reference types and implicit usings when appropriate. Prefer modern, readable C# syntax (file-scoped namespaces, primary constructors where they improve clarity, collection expressions, pattern matching, records for suitable immutable data, and required members when useful). Do not use new syntax solely for novelty.
- Favor strong typing, explicit domain concepts, immutability where practical, small cohesive classes, and meaningful names. Avoid magic strings and numbers; centralize reusable constants or options.
- Use async end-to-end for I/O. Propagate `CancellationToken`; avoid `.Result`, `.Wait()`, fire-and-forget tasks, and unnecessary `Task.Run` in server code.
- Use built-in dependency injection, options validation, `TimeProvider` for time-dependent logic, and `System.Text.Json` with reused serialization options or source generation where justified.
- Avoid speculative abstractions, premature optimization, and new dependencies without clear benefit. Verify package/API compatibility and consult official Microsoft Learn/.NET documentation for uncertain or version-specific behavior.

## Architecture: Feature-First and Pragmatic

- Prefer Vertical Slice Architecture for application features: group endpoint, request/response contracts, validation, business behavior, and related tests by feature or bounded context, not by technical layer alone.
- Use ASP.NET Core Minimal APIs by default for new HTTP APIs. Define endpoints in cohesive feature modules and register them explicitly. Use typed results (`TypedResults` / `Results<...>`) when useful, appropriate status codes, route groups, endpoint names, OpenAPI metadata, authorization, and input validation.
- Keep HTTP concerns at the boundary. Separate business invariants from transport and persistence concerns. Do not expose EF entities as public API contracts by default.
- Apply DDD selectively where domain complexity warrants it: clear aggregates, invariants, value objects, and bounded contexts. Avoid anemic ceremony for simple CRUD.
- Do not introduce MediatR, a generic repository/unit-of-work wrapper over EF Core, or CQRS layers by default. Add these only when a concrete requirement justifies their cost.
- Prefer explicit dependencies and direct, testable orchestration. For distributed work, consider idempotency, retries, outbox/inbox patterns, eventual consistency, and observability where needed.
- Record consequential architecture decisions and trade-offs in concise ADRs when appropriate.

## Entity Framework Core

- Prefer EF Core 10+ for new .NET 10 applications when supported. Follow existing version constraints in maintained projects.
- Use `DbContext` directly in application slices where suitable. Configure entity mappings with `IEntityTypeConfiguration<T>` when mappings become nontrivial; keep persistence configuration out of endpoint handlers.
- Use async queries and pass cancellation tokens. Project read models to required fields, use `AsNoTracking()` for read-only queries, and avoid premature materialization and N+1 queries.
- Use explicit transaction boundaries only when necessary; understand EF Core's implicit `SaveChanges` transaction. Use optimistic concurrency for conflicting updates when appropriate.
- Treat schema migrations as reviewed source artifacts. Never silently apply destructive migrations or modify production databases.
- Parameterize SQL; never concatenate untrusted input into raw SQL. Prefer LINQ unless measured needs justify SQL or bulk operations.
- Evaluate indexes, query plans, pagination, batching, and change tracking based on measured workloads. Avoid indiscriminate `Include` chains.

## Testing: xUnit v3 and TDD

- Default to xUnit v3 for new test projects, using compatible runner and test SDK packages. Respect existing test frameworks in established repositories unless migration is requested.
- Test names should communicate behavior, preferably `Given_Condition_When_Action_Then_Outcome`, or equally clear descriptive names. Use `[Fact]` and `[Theory]` with meaningful cases.
- Follow Arrange / Act / Assert; test observable outcomes, boundary conditions, invalid input, cancellation, authorization, concurrency, and failure paths as relevant.
- Prefer fast, deterministic unit tests for business behavior. Mock external boundaries, not the system under test; avoid overspecifying implementation details. Prefer simple fakes over elaborate mocking setups.
- Add focused integration tests for Minimal API HTTP contracts, EF Core persistence/query behavior, migrations, and external integration boundaries. Use `WebApplicationFactory` where appropriate.
- Avoid network-dependent or time-dependent tests unless explicitly classified as integration/end-to-end tests. Use `TimeProvider` and deterministic data.
- Do not aim for arbitrary coverage percentages; prioritize meaningful risk-based coverage and regression protection.
- For bug fixes, first add a test reproducing the defect whenever feasible.

## Integration Testing Standards

- Use xUnit v3 for all automated tests.
- Use Testcontainers for .NET for database integration tests.
- Run integration tests against the same database engine used in production (e.g., SQL Server or PostgreSQL).
- NEVER use EF Core InMemory provider for integration tests.
- NEVER substitute SQLite for SQL Server or PostgreSQL.
- NEVER mock or fake DbContext, DbSet, or repositories in database integration tests.
- Use WebApplicationFactory<Program> for ASP.NET Core Minimal API integration tests.
- Start the database container before tests and configure the application to use its connection string.
- Apply EF Core migrations to the test database.
- Ensure tests are isolated and repeatable.
- Clean up test data between tests using Respawn or an equivalent database reset strategy.
- Dispose of containers and resources after tests.
- If Docker or the container runtime is unavailable, report the blocker. Never silently fall back to an in-memory database.

## Security Engineering and Testing

- Apply secure-by-default principles to all generated code.
- Follow OWASP ASVS and OWASP API Security Top 10.
- Apply least privilege to identities, APIs, databases, and Azure resources.
- Never hardcode secrets, credentials, or access tokens.
- Treat all external input as untrusted.

### Security Testing

- Consider security implications for every new or modified API endpoint, database operation, and infrastructure resource.
- Delegate security reviews and security test generation to the `security-tester` subagent when relevant.
- Prioritize authentication, authorization, tenant isolation, injection, and sensitive data exposure.
- Generate automated security regression tests for identified risks.
- Use property-based security tests when invariants can be expressed across multiple inputs.
- Prefer reproducible tests over manual verification.
- Never substitute mocked security behavior for real authorization checks in integration tests.

### Security Validation

- Run applicable security tests after code changes.
- Report discovered vulnerabilities with evidence, severity, and recommended remediation.
- Do not silently suppress security findings or weaken security controls to make tests pass.
- Only perform active security scans against explicitly authorized environments.
- Never execute destructive security tests against production systems.

### Security Skills

- Use `dotnet-security-tests` for application security.
- Use `api-security-testing` for OWASP API testing.
- Use `azure-security-audit` for Azure infrastructure.
- Use `security-ci-pipeline` for automated CI/CD checks.

## Security, Reliability, and Observability

- Enforce authentication and authorization at API boundaries and for resource-level access; never rely on UI checks alone.
- Validate untrusted input and return consistent, safe problem details. Do not leak secrets, tokens, connection strings, PII, or stack traces.
- Prefer managed identities and least-privilege access for Azure workloads. Use configuration providers/secret stores rather than hardcoded credentials.
- Use structured `ILogger` messages with stable templates, meaningful log levels, and correlation/trace context. Add OpenTelemetry traces, metrics, and health checks where operationally useful.
- Use resilience policies (timeouts, retries with backoff, circuit breakers) only for appropriate transient operations; avoid retry storms and non-idempotent retries.
- Consider graceful shutdown, cancellation, bounded concurrency, and resource disposal.

## Infrastructure and delivery agent boundaries

- Azure/Bicep agents: prefer reusable modules, typed parameters, symbolic references, secure defaults, explicit scopes, consistent naming and tags; validate with Bicep build/lint and Azure deployment what-if when credentials and target scope are available. A what-if is a remote Azure evaluation, not an offline/local-only check. Never deploy without approval. For Bicep changes, use snapshot validation. For Azure Deployment Stacks, use the azure-stack-tool skill PowerShell workflow for both what-if and approved deployments.
- CI/CD agents: use least-privilege identities, pinned/approved dependencies, build-test-scan gates, environment separation, artifact provenance, and deployment approvals where warranted. Do not print secrets in logs.
- Architecture and requirements agents: establish business goals, measurable nonfunctional requirements, constraints, alternatives, and acceptance criteria before prescribing technology.

## Local Validation and Completion

Run commands appropriate to the changed solution, adapting paths, framework, and test runner to the repository:

```powershell
dotnet --info
dotnet restore
dotnet build --no-restore
dotnet test
# Where applicable and configured:
dotnet format --verify-no-changes
```

For xUnit v3, determine whether the repository uses VSTest or Microsoft.Testing.Platform and use its supported test invocation; do not assume every project supports the same `dotnet test` switches. For TDD, run the smallest relevant test first, then the wider suite. Do not auto-fix unrelated formatting or test failures without explaining the scope.

Before finalizing, verify: requirements met; public contracts and security reviewed; tests meaningful and passing; build/format checks run; documentation updated if behavior changed; no generated files edited manually; no secrets introduced. Report exact validation outcomes and blockers. Never fabricate tool execution or success.

## Skills and Documentation

Use available relevant `SKILL.md` files for specialized workflows (Vertical Slice, DDD, EF Core, Bicep, architecture reviews, requirements, and CI/CD). Treat skills as task guidance rather than reasons to add complexity. Prefer official .NET, ASP.NET Core, EF Core, xUnit, and Azure documentation; use Microsoft Learn MCP when configured. When documentation conflicts with the installed SDK/package version, verify the version-specific behavior before coding.
