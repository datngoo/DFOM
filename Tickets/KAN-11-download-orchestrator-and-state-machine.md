# KAN-11 Download Orchestrator And State Machine

## Summary

Implement the download workflow and state transitions for media items.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-5
- KAN-6
- KAN-7
- KAN-10

## Description

Build the domain and data flow that starts a download from a resolved YouTube URL item, tracks progress, updates persisted state, and finalizes the media item on success or failure.

Suggested states:

- `notDownloaded`
- `queued`
- `downloading`
- `downloaded`
- `failed`

## Acceptance Criteria

- Download can be started from the detail screen
- Download flow supports separate audio and video choices
- A media item record is created or updated before transfer starts
- Progress updates are exposed to the UI
- Success moves the file into managed local storage
- Failure updates the item into a failed state

## Notes

- Keep V1 to one active download at a time if that simplifies the flow
- State transitions should be testable
