# KAN-23 Add Playlist Feature

## Summary

Add a simple Playlist feature so users can organize downloaded media into custom playlists from the Library.

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
- KAN-20
- KAN-22

## Description

Introduce an MVP playlist experience for downloaded media. Users should be able to create unlimited playlists, add downloaded items into playlists, open playlists from the Library, and tap items inside a playlist to play them using the existing playback flows.

Each playlist must contain only one media type. The playlist type is determined by the first item added to that playlist. After that, mixing audio and video in the same playlist is not allowed.

The implementation should remain simple, stable, and focused on usability and correctness.

## Scope of Change

Included scope:

- Add a `Create New Playlist` option in the Library
- Allow user to enter a playlist name when creating a playlist
- Support creating unlimited playlists
- Allow user to add a downloaded item to a playlist from that item
- Show existing playlists when user selects `Add to Playlist`
- Only show playlists that are compatible with the selected item's media type
- Determine playlist media type based on the first item added
- Prevent mixing audio and video items in the same playlist
- Allow user to open a playlist from the Library
- Show the list of items inside a playlist
- Allow user to tap a playlist item to play it using the existing playback behavior
- Support basic playlist management for MVP
- Support removing an item from a playlist if implemented as part of the MVP

Excluded scope:

- Do not introduce complex playlist queue systems
- Do not introduce shuffle or repeat logic in this ticket
- Do not refactor the existing playback system
- Do not redesign Library architecture or existing download flows
- Do not change existing KAN-14, KAN-15, KAN-16, or KAN-22 behavior beyond what is necessary to support playlists
- Do not add collaborative, smart, or auto-generated playlists

## Acceptance Criteria

- User can create a playlist from the Library
- User can create multiple playlists without an enforced limit
- User can add a downloaded item to a playlist
- Playlist media type is determined by the first item added
- Playlist enforces the single media type rule after the first item is added
- Incompatible playlists are not shown when user adds an item to a playlist
- User can open a playlist and view its items
- User can tap an item inside a playlist and playback starts using the correct existing player flow
- Removing an item from a playlist works if that capability is included in the MVP implementation
- Existing offline audio playback continues to work correctly
- Existing offline video playback continues to work correctly
- Existing Library functionality continues to work correctly
- No regression is introduced to KAN-14, KAN-15, KAN-16, or KAN-22 behavior

## Notes

- Keep the implementation simple and stable
- Focus on usability and correctness over advanced playlist behavior
- Prefer a straightforward MVP data model and UI flow
- Avoid over-engineering or expanding scope into queue management or player redesign
