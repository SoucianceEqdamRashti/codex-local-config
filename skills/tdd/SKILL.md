
---
name: tdd
description: Use for test-driven .NET development.
---

# Test-Driven Development

Follow the Red-Green-Refactor cycle.

1. Understand the required behavior.
2. Write a failing xUnit test.
3. Run the test and confirm it fails.
4. Implement the minimum code to pass.
5. Run the test again.
6. Refactor while keeping tests green.
7. Run all relevant tests.

Prefer:
- Given_When_Then test naming
- Meaningful behavioral assertions
- Integration tests for external dependencies

Do not write tests merely to confirm
implementation details.
Report the tests executed and their results.
