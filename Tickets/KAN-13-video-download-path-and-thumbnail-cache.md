# KAN-13 Video Download Path And Thumbnail Cache

## Summary

Implement the end-to-end video download path and cache thumbnails for downloaded video items.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-11

## Description

Add video-specific handling for download resolution, file storage, and thumbnail caching so downloaded videos are recognizable in the library.

## Acceptance Criteria

- User can download a video item from the detail screen
- Video file is saved locally
- Video thumbnail is cached locally for downloaded items
- Media item metadata stores local thumbnail path for video when available
- Downloaded video item appears in the library with recognizable artwork

## Notes

- Prioritize clear local thumbnail support over UI polish
- Reuse shared download infrastructure from KAN-11
