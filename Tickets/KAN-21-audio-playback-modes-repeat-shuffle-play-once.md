# KAN-21 Add Audio Playback Modes (Repeat, Shuffle, Play Once)

## Summary

Enhance the audio playback experience by adding multiple playback modes including repeat, shuffle, and play-once behavior.

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

Extend the existing audio player to support multiple playback modes that control how audio items are played.

Playback modes to support:

- Play Once: Play through the current list once and stop
- Repeat All: Loop the entire list continuously
- Repeat One: Loop the current track
- Shuffle: Play items in random order

Scope:

- Add a playback mode state to the audio player ViewModel or Domain layer
- Add a UI control button to cycle through playback modes
- Ensure mode switching works during active playback
- Apply playback logic based on the selected mode
- Reuse existing player infrastructure without breaking current functionality

User flow:

Open audio item
-> Player opens
-> User taps playback mode button
-> Cycle modes: Play Once -> Repeat All -> Repeat One -> Shuffle
-> Mode applies immediately

## Acceptance Criteria

- User can switch between playback modes via UI control
- Current playback mode is clearly indicated in the UI
- Mode cycles correctly in the defined order
- Playback behavior matches the selected mode
- Play Once stops after the last item
- Repeat All loops the entire list
- Repeat One loops the current track
- Shuffle plays items in random order
- Mode switching works during playback without restarting the app
- No regression in existing audio playback and play, pause, and seek still work
- Works correctly with persisted library items

## Notes

- Keep the implementation simple for V1 and avoid advanced queue management
- Shuffle does not need to guarantee perfect randomness and only needs reasonable variation
- Repeat and shuffle logic should live in player logic rather than the SwiftUI view
- This ticket applies to audio playback only and video is not required
- UI can be minimal and should prioritize clarity over polish
