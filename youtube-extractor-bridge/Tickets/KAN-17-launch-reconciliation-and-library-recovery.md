# KAN-17 Launch Reconciliation And Library Recovery

## Summary

Add app launch reconciliation so persisted library records and local files stay consistent.

## Type

Task

## Priority

Medium

## Status

To Do

## Dependencies

- KAN-14
- KAN-15
- KAN-16

## Description

On app launch, validate that records marked as downloaded still have their expected local files. If files are missing or broken, update the app state so the user is not shown invalid playable items.

## Acceptance Criteria

- App performs a lightweight reconciliation pass on startup
- Missing local files are detected
- Invalid items are updated to an unavailable or failed state
- Library remains stable after relaunch

## Notes

- Keep reconciliation logic fast and deterministic
- Do not silently crash or leave broken playback actions
