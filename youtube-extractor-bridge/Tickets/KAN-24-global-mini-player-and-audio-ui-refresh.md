# KAN-24 Global Mini Player And Audio UI Refresh

## Summary

Enhance audio playback experience by adding a global mini player bar, improving audio player controls, and persisting playback mode.

## Type

Task

## Priority

Medium

## Status

To Do

## Dependencies

- KAN-14
- KAN-15
- KAN-21
- KAN-22

## Description

Improve the offline audio playback experience with a simple global mini player that remains visible across the app whenever an audio item is active.

Also refresh the main audio player controls so the playback actions feel more consistent and media-focused, and persist the selected playback mode so it restores on app relaunch.

The implementation should reuse the existing playback system, avoid introducing a second player, and keep the mini player intentionally minimal.

## Goals

- Add a global mini player bar that is visible across the app when an audio item is active
- Hide the mini player when no audio item is active
- Show the current audio title and a single play or pause toggle in the mini player
- Allow the mini player to open the audio detail screen when tapped
- Refresh the main audio player controls to use media icons instead of text buttons
- Keep playback mode selection persisted across app relaunches
- Preserve the existing audio playback architecture and behavior wherever possible

## Non-Goals

- Do not introduce a second audio player instance or parallel playback flow
- Do not add advanced mini player behavior such as scrubbing, queue controls, expanded gestures, or artwork-heavy layouts
- Do not redesign unrelated Library, playlist, video, or download flows
- Do not expand scope into a broader playback architecture refactor

## Functional Requirements

- A global mini player bar appears at the bottom of the app whenever an audio item is active
- The mini player is hidden when no audio item is active
- The mini player shows the current audio title
- Long titles in the mini player truncate with ellipsis
- The mini player includes exactly one play or pause button with toggle behavior
- Tapping the mini player opens the audio detail screen for the active item
- The main audio player replaces text-based playback controls with media icons
- The main audio player includes Previous, Play or Pause, and Next controls
- The main audio player uses a single toggle play or pause button rather than separate controls
- The selected playback mode is persisted locally
- The persisted playback mode is restored on app relaunch
- The default playback mode is play through list
- The implementation reuses the current playback state and player infrastructure
- The mini player and full audio player remain synchronized with the same playback source of truth

## UX Notes

- Keep the mini player visually simple and lightweight for MVP
- Prioritize clarity and consistency over animation-heavy behavior
- Use familiar media control icons for Previous, Play or Pause, and Next actions
- Ensure the bottom mini player does not feel like a separate destination and instead acts as a lightweight entry point back into the full player
- Preserve good readability for long titles by truncating cleanly rather than wrapping to multiple lines

## Technical Notes

- Reuse the existing playback system and shared playback state
- Do not introduce a second player, duplicate playback coordinator, or separate playback lifecycle
- Prefer wiring the mini player from the same active audio state already used by the full audio player
- Persist playback mode using the app's existing lightweight persistence approach when feasible
- Restore playback mode during app startup or player initialization without requiring manual user action
- Keep the UI refresh isolated to audio playback surfaces and avoid unnecessary architectural churn

## Acceptance Criteria

- When an audio item is active, a mini player bar is visible across the app at the bottom of the screen
- When no audio item is active, the mini player is not shown
- The mini player displays the current audio title
- Long mini player titles truncate with ellipsis instead of overflowing
- The mini player contains only one play or pause toggle button
- Tapping the mini player opens the audio detail screen for the active audio item
- The full audio player shows icon-based Previous, Play or Pause, and Next controls
- The full audio player no longer relies on text buttons for these playback actions
- The play or pause control behaves as a single toggle button
- The selected playback mode persists after the app is closed and relaunched
- On fresh state or when no saved value exists, playback mode defaults to play through list
- The mini player and full player stay synchronized with the same playback state
- Existing audio playback functionality continues to work without regression
- No second audio player is introduced

## Suggested Implementation Steps

- Identify the existing shared audio playback state and the root-level UI location best suited for presenting a global mini player
- Add a simple bottom mini player container that binds to the active audio item and current playback state
- Wire mini player tap behavior to open the existing audio detail screen
- Refresh the full audio player controls to use media icons for Previous, Play or Pause, and Next
- Persist the playback mode selection using the existing persistence pattern already used by the app where practical
- Restore the saved playback mode during player setup or app launch
- Verify that mini player state and full player state remain synchronized through the same playback flow

## Manual Test Cases

- Start playback of an audio item and verify the mini player appears at the bottom of the app
- Stop or clear active audio and verify the mini player disappears
- Play an item with a long title and verify the mini player title truncates with ellipsis
- Tap the mini player and verify the app opens the audio detail screen for the active item
- Use the mini player play or pause button and verify playback toggles correctly
- Use the full player Previous, Play or Pause, and Next icon controls and verify each action works correctly
- Change playback mode, relaunch the app, and verify the selected mode is restored
- Clear saved playback mode state or test fresh install behavior and verify the default mode is play through list
- Confirm the mini player and full player remain in sync when toggling playback from either surface
- Verify no duplicate playback session or second player behavior appears during use
