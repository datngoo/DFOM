# KAN-18 Unit And Integration Test Foundation

## Summary

Add the first round of automated tests for core app behavior.

## Type

Task

## Priority

Medium

## Status

To Do

## Dependencies

- KAN-11
- KAN-14
- KAN-17

## Description

Introduce test targets and cover the most important logic for a stable V1.

Recommended coverage:

- Search result mapping
- Download state transitions
- File path generation
- Persistence fetch/save behavior
- Launch reconciliation

## Acceptance Criteria

- Test target exists and runs
- Core non-UI logic has initial automated coverage
- At least one integration-style test exercises a realistic flow with mocks

## Notes

- Focus on high-value logic, not blanket test coverage
