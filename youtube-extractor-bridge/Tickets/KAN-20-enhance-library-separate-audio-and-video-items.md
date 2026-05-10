# KAN-20 Enhance Library: Separate Audio And Video Items

## Summary

Enhance the Library screen so downloaded items are organized into separate Audio and Video groups for easier browsing.

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
- KAN-17

## Description

Currently, all downloaded media items are shown together in a single Library list. Update the Library experience so persisted items are visually separated by media type.

Scope:

- Load existing persisted library items as before
- Separate items into two distinct groups: Audio and Video
- Filter based on the existing media type field
- Keep the current item row and card layout unchanged
- Keep existing tap behavior and navigation to the correct player flow unchanged
- Use a simple MVP UI approach, preferably section headers inside the Library screen
- Empty states should be handled cleanly for missing groups

User flow:

Open Library
-> App loads persisted items
-> Show Audio section and Video section when applicable
-> User taps an item
-> App opens the correct offline player

## Acceptance Criteria

- Audio and Video items are visually separated in the Library UI
- Each item appears in the correct group based on media type
- Existing item layout remains unchanged
- User can still tap any item to open playback
- Library still loads correctly from persisted data
- No regression in current library or player navigation behavior
- If there are no audio items, an empty state is shown for Audio when both groups are being displayed
- If there are no video items, an empty state is shown for Video when both groups are being displayed
- If only one media type exists, show only the populated section and do not show an unnecessary empty section
- Existing sort behavior within each group remains stable and predictable

## Notes

- Prefer section headers over tabs for MVP unless the existing implementation strongly favors tabs
- Reuse the current Library view model and repository flow where possible
- Keep this ticket focused on Library grouping only, not player redesign
- Avoid unnecessary UI polish and prioritize clarity and no regressions
