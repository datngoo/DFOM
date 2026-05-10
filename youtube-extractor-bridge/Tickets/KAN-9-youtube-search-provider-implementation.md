# KAN-9 YouTube URL Resolution Provider Implementation

## Summary

Implement the primary YouTube URL resolution provider and map the resolved video into app models.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-7
- KAN-8

## Description

Implement the concrete provider used by the app to resolve a direct YouTube video URL into a normalized media item that the UI can display and offer for download.

Resolved data should include:

- Source item ID
- Title
- Creator/channel name if available
- Thumbnail URL
- Duration if available
- Source page URL
- Available download options for audio and video if inferable

## Acceptance Criteria

- URL resolution provider returns a usable media model
- Resolved metadata displays correctly after URL submission
- Mapping logic is separated from view code
- Provider failures are translated into app-level errors

## Notes

- Keep transport DTOs isolated from SwiftUI
- Avoid mixing actual file transfer logic into this ticket
