# KAN-14 Library Screen And Persisted List

## Summary

Build the library screen that shows downloaded audio and video items from local persistence.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-5
- KAN-12
- KAN-13

## Description

Create the library tab and load persisted items from SwiftData. The library should be useful after app relaunch and clearly distinguish status and media type.

## Acceptance Criteria

- Library tab exists in the app
- Downloaded items load from persisted storage
- Audio and video items are both visible
- Video items show cached thumbnail when available
- Empty state exists when there are no downloads
- Failed or missing items have a visible state

## Notes

- Sort by most recent downloaded item first
- Keep the library list implementation simple and reliable
