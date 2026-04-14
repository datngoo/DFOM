# KAN-22 Background Audio, Lock Screen Now Playing, and Basic Track Navigation

## Summary

Enhance offline audio playback so downloaded audio continues playing when the app goes to background or the iPhone screen is locked, while also supporting lock screen metadata, remote controls, and basic previous/next track navigation.

## Type

Task

## Priority

Medium

## Status

To Do

## Dependencies

- KAN-15
- KAN-14

## Description

Extend the existing offline audio playback flow to support background playback behavior for downloaded audio items.

Also publish basic Now Playing information to the lock screen and Control Center, support remote play and pause controls, and add basic previous and next track navigation for downloaded audio items using the current library ordering as playback context.

The implementation should remain minimal and focused on audio only.

## Scope of Change

Included scope:

- Enable background audio capability for the app target
- Configure the audio session for playback so offline audio can continue in background
- Publish Now Playing metadata for the current offline audio item
- Show title on the lock screen and in Control Center
- Show creator when available
- Show artwork when available, without making artwork required for playback
- Support play and pause from Control Center
- Support play and pause from the lock screen
- Add basic Previous and Next controls to the audio player
- Support moving between downloaded audio items using existing library ordering
- Update metadata correctly when switching tracks
- Keep in-app audio player state synchronized with remote controls
- Reuse the current offline audio playback path from KAN-15

Excluded scope:

- Do not introduce playlist or queue systems
- Do not redesign or refactor the overall player architecture
- Do not change download flow, library persistence, or navigation structure
- Do not expand scope to video playback
- Do not add advanced remote command support beyond play, pause, previous, and next

## Acceptance Criteria

- Downloaded offline audio continues playing when the iPhone screen is locked
- Downloaded offline audio continues playing when the app goes to background
- Lock screen displays the current track title
- Lock screen displays creator information when available
- Control Center displays the current track title
- Control Center displays creator information when available
- Artwork is shown when available but playback still works cleanly when artwork is missing
- Play and pause from Control Center work
- Play and pause from the lock screen work
- Previous and Next buttons exist in the audio player
- User can move between downloaded audio items
- Existing library ordering is used as the playback context for Previous and Next behavior
- Metadata updates correctly when switching tracks
- Lock screen info updates correctly when switching tracks
- No crash occurs when user is at the first or last item
- In-app player state remains synchronized with remote controls
- Existing foreground offline audio playback continues to work
- Existing background audio behavior remains stable
- No regression is introduced to unrelated flows

## Notes

- Keep the implementation minimal and safe
- Focus on audio only and do not modify video behavior unless absolutely necessary
- Prefer a small dedicated helper or coordinator for audio session and Now Playing integration
- Avoid large refactors to playback architecture, library flow, download flow, or persistence
- Previous and Next behavior only needs to support basic navigation across downloaded audio items already available in the library
