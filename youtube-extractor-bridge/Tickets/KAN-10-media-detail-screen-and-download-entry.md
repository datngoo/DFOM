# KAN-10 Media Detail Screen And Download Entry

## Summary

Create the media detail screen and the initial entry point for downloading a resolved YouTube item.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-8
- KAN-9

## Description

After a user submits a valid YouTube URL and the app resolves the item, open a detail screen showing richer metadata and explicit download choices.

The detail screen should show:

- Thumbnail
- Title
- Creator
- Duration if available
- Source URL or provider label if useful
- Download action for audio
- Download action for video
- Current download state if already known

## Acceptance Criteria

- Successful URL resolution opens a detail screen
- Detail screen renders selected item metadata
- Separate audio and video download actions are visible
- The screen can show download status placeholders

## Notes

- This ticket can stop at the handoff to download orchestration
- Actual file transfer is covered later
