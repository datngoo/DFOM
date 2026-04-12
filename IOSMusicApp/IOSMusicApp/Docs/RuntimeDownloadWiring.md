# Runtime Download Wiring

## Current Runtime Types

- URL resolution provider: `YouTubeURLResolutionProvider`
- Download provider: `YouTubeBridgeDownloadProvider`
- Downloader transport: `MediaFileDownloader`

## What This Means

- URL resolution is real and network-backed through the current YouTube metadata path.
- Download transport is a real network downloader.
- Download resolution now uses an external extractor bridge for direct downloadable stream URLs.

## Current Download Resolution Limits

Normal runtime depends on bridge availability and the bridge returning a direct downloadable URL for the requested media type.

If that does not happen, the app still fails cleanly with explicit bridge/configuration errors.

The normal app runtime does not:

- injects `YouTubeProviderSpike`
- injects `FakeMediaFileDownloader`
- silently falls back to bundled sample media

## Fake/Spike Types Still Present

- `YouTubeProviderSpike`: preview/debug helper only
- `FakeMediaFileDownloader`: debug/test helper only
- `StubDownloadProvider`: inactive stub
- `StubDownloadStarter`: inactive stub

## Remaining Gap

The remaining blocker is outside the iOS app codebase:

- the extractor bridge must be deployed and reachable
- for physical iPhone testing, the bridge must listen on `0.0.0.0` or the Mac LAN IP, not only `127.0.0.1`
- the bridge must support the YouTube items being requested
