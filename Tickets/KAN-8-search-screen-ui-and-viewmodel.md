# KAN-8 URL Input Screen UI And ViewModel

## Summary

Build the URL input screen UI and view model with loading, validation, and error states.

## Type

Task

## Priority

High

## Status

To Do

## Dependencies

- KAN-4
- KAN-7

## Description

Create the SwiftUI entry screen and state management for direct YouTube URL input. The screen should support pasting or typing a video URL, submitting it, validating it, and moving to the resolved item flow.

## Acceptance Criteria

- URL input screen exists in the app tab navigation
- User can type or paste a YouTube video URL
- User can submit the URL for resolution
- Loading state is shown while resolving the URL
- Validation error is shown for invalid or unsupported URLs
- Error state is shown for resolution failures
- Successful resolution leads to the selected media detail flow

## Notes

- Use mock provider data first if needed to finish the UI cleanly
- Keep the view model provider-driven and testable
- This ticket replaces keyword search for the current phase
