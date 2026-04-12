# YouTube Extractor Bridge

The iOS app uses a bridge-based download provider in normal runtime because extracting downloadable YouTube media URLs directly inside the app is fragile and fails on common protected or ciphered items.

## Runtime Wiring

- Metadata resolution stays in-app through `YouTubeURLResolutionProvider`
- Download resolution uses `YouTubeBridgeDownloadProvider`
- Transfer still uses `MediaFileDownloader`
- Managed local storage still uses `ApplicationSupportFileStorage`

## Bridge Configuration

Set the bridge base URL in the app Info.plist via the `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL` key.

In this project, `Info.plist` contains:

- `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL = $(YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL)`
- `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST = $(YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST)`
- `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT = $(YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT)`

That value is supplied from the Xcode build setting:

- `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL`
- `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST`
- `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT`

Example value:

```text
https://your-extractor.example.com
```

Current development behavior:

- Debug simulator runs default to `http://127.0.0.1:8080`
- Debug physical-device runs build the bridge URL from `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST` and `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT`
- Release builds require an explicit `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL`
- The final resolved bridge URL is logged at runtime together with whether the app is on Simulator or a physical device

You can override the value for local testing by setting the same key as an environment variable in the Run scheme:

```text
YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL=http://192.168.1.42:8080
```

Or keep `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL` empty in Debug and set only:

```text
YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST=192.168.1.42
YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT=8080
```

If the key is missing or empty and no Debug simulator fallback applies, the app fails the download handoff with a clear configuration error instead of fabricating media.

## Simulator vs Real Device

Simulator example:

```text
http://127.0.0.1:8080
```

Real iPhone example on the same LAN as the Mac running the bridge:

```text
http://192.168.1.42:8080
```

Why `localhost` is not valid on a real iPhone:

- on Simulator, `127.0.0.1` points at the Mac host bridge process
- on a real iPhone, `127.0.0.1` points back to the phone itself, not to the Mac
- for real-device testing, use the Mac's LAN IP address instead

Single source of truth for URL construction:

- `YouTubeExtractorBridgeConfiguration` resolves the final base URL
- precedence is `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL` environment override, then `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL`, then Debug device host and port, then Debug simulator fallback
- `YouTubeExtractorBridgeClient` appends `/resolve-download` onto that resolved base URL

## Reachability Check

Before testing the app, verify the bridge is reachable:

1. Start the bridge on the Mac.
2. From Simulator, open `http://127.0.0.1:8080`.
3. From a real iPhone browser on the same Wi-Fi, open `http://<your-mac-lan-ip>:8080`.
4. Make sure the bridge server listens on `0.0.0.0` or on the Mac LAN IP, not only `127.0.0.1`.
5. If the page does not respond, the app will fail with a bridge transport error rather than a configuration error.

## ATS For Local Development

- Debug builds now enable a small Info.plist-preprocessed ATS relaxation so local `http://` bridge URLs can be used during development, including a configured LAN bridge host.
- Release builds do not include that Debug-only ATS relaxation.

## Request Shape

The app sends:

```http
POST /resolve-download
Content-Type: application/json
Accept: application/json
```

```json
{
  "provider": "youtube",
  "providerItemId": "dQw4w9WgXcQ",
  "sourcePageURL": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "mediaType": "audio"
}
```

`mediaType` is `"audio"` or `"video"`.

## Success Response Shape

```json
{
  "downloadURL": "https://cdn.example.com/path/to/media.m4a",
  "mimeType": "audio/mp4",
  "fileExtension": "m4a",
  "provider": "youtube",
  "providerItemId": "dQw4w9WgXcQ"
}
```

The app maps this directly into `DownloadDescriptor`.

## Error Response Shape

Recommended error payload:

```json
{
  "error": "no_downloadable_media",
  "message": "No direct downloadable audio stream was available."
}
```

Recommended behavior:

- `404` or `422` with `error: "no_downloadable_media"` means the extractor found no downloadable media for the requested type
- other `4xx` responses mean the extractor explicitly rejected the request
- `5xx` responses are treated as invalid bridge responses by the app

## What Stays Unchanged From KAN-19

- Only managed relative paths are persisted
- Absolute sandbox URLs are still reconstructed at runtime from Application Support
- Launch reconciliation behavior is unchanged
- Library and offline audio/video players are unchanged
- Download finalization still flows through `DownloadOrchestrator`
