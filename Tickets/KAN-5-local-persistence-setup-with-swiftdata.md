# KAN-5 Local Persistence Setup With SwiftData

## Summary

Set up SwiftData and persist a basic `MediaItem` model.

## Type

Task

## Priority

Highest

## Status

To Do

## Dependencies

- KAN-4

## Description

Add the initial persistence layer using SwiftData. Create the first version of the `MediaItem` entity and verify records can be saved and loaded.

Initial fields should include:

- Internal ID
- Provider name
- Provider item ID
- Title
- Creator name
- Media type
- Download status
- Local file path
- Thumbnail local path
- Created date
- Downloaded date

## Acceptance Criteria

- SwiftData is configured in the app
- `MediaItem` model compiles and persists
- A simple test or debug flow can create and fetch sample items
- Data remains after app relaunch

## Notes

- Keep the schema lean but extensible
- Prefer fields needed by the first feature slices only
