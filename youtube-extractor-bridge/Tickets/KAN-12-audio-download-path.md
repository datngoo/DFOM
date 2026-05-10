# KAN-12 Audio Download Path

## Summary

Implement the end-to-end audio download path using the shared download orchestration.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-11

## Description

Add audio-specific handling for download resolution, file type management, persistence, and playback readiness.

## Acceptance Criteria

- User can download an audio item from the detail screen
- Audio file is saved locally
- Media item metadata reflects audio type and local file path
- Downloaded audio item appears in the library
- Audio item is ready for offline playback

## Notes

- Thumbnail caching is optional for audio in V1
- Keep file format handling explicit and visible in code
