# KAN-6 File Storage Service For Local Media

## Summary

Create the local file storage service for downloaded media and cached thumbnails.

## Type

Task

## Priority

Highest

## Status

To Do

## Dependencies

- KAN-4
- KAN-5

## Description

Build a file storage abstraction that manages where media files and thumbnails live inside the app sandbox. Use stable app-generated paths instead of source titles.

Storage targets:

- Downloaded audio files
- Downloaded video files
- Cached video thumbnails

## Acceptance Criteria

- A file storage service exists with create/read/delete helpers
- Files are stored under `Application Support`
- Media items use generated folder names such as UUID-based directories
- Thumbnail caching path support exists for video items
- Missing file handling behavior is defined

## Notes

- Audio thumbnail caching is optional for V1
- Video thumbnail caching should be supported
