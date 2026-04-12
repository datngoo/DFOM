# YouTube Extractor Bridge

Minimal local Node.js bridge backend for the iOS app's existing `POST /resolve-download` contract.

## What it does

- Listens on port `8080` by default
- Binds to `0.0.0.0` by default so Simulator and physical iPhone testing can reach it from the same LAN
- Exposes `GET /health`
- Exposes `POST /resolve-download`
- Resolves direct YouTube media URLs through a dedicated backend service layer
- Remuxes audio downloads through the bridge into a proper `.m4a` file before the iOS app saves them
- Returns error payloads shaped for the current iOS bridge client

## Project structure

```text
.
├── package.json
├── tsconfig.json
├── src
│   ├── app.ts
│   ├── server.ts
│   ├── config
│   │   └── env.ts
│   ├── errors
│   │   └── httpErrors.ts
│   ├── middleware
│   │   ├── errorHandler.ts
│   │   └── requestLogger.ts
│   ├── routes
│   │   ├── health.ts
│   │   └── resolveDownload.ts
│   ├── services
│   │   └── youtubeExtractorService.ts
│   ├── types
│   │   └── api.ts
│   └── utils
│       └── logger.ts
└── README.md
```

## Requirements

- Node.js `22+`
- npm

## Install

```bash
npm install
```

## Run locally

Development mode:

```bash
npm run dev
```

Production-style build:

```bash
npm run build
npm start
```

The server listens on `0.0.0.0:8080` by default.

Reach it with:

- `http://127.0.0.1:8080` from the Mac itself or from the iOS Simulator
- `http://<your-mac-lan-ip>:8080` from a physical iPhone on the same network

Optional environment variables:

- `PORT` defaults to `8080`
- `HOST` defaults to `0.0.0.0`
- `NODE_ENV` defaults to `development`
- `YT_DLP_PYTHON_PATH` optionally points to a specific Python `3.10+` binary if your machine has multiple Python installations

For real-device testing, do not bind the bridge only to `127.0.0.1`, because a physical iPhone cannot reach the Mac through that loopback address.

## Health check

Mac or Simulator:

```bash
curl http://127.0.0.1:8080/health
```

Physical iPhone reachability check from another device on the same LAN:

```bash
curl http://<your-mac-lan-ip>:8080/health
```

Expected response:

```json
{
  "status": "ok",
  "service": "youtube-extractor-bridge",
  "port": 8080,
  "timestamp": "2026-04-10T00:00:00.000Z"
}
```

## Resolve download examples

Audio request:

```bash
curl -X POST http://127.0.0.1:8080/resolve-download \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "youtube",
    "providerItemId": "dQw4w9WgXcQ",
    "sourcePageURL": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "mediaType": "audio"
  }'
```

Video request:

```bash
curl -X POST http://127.0.0.1:8080/resolve-download \
  -H 'Content-Type: application/json' \
  -d '{
    "provider": "youtube",
    "providerItemId": "dQw4w9WgXcQ",
    "sourcePageURL": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "mediaType": "video"
  }'
```

Example success payload:

```json
{
  "downloadURL": "http://127.0.0.1:8080/downloads/audio/<token>",
  "mimeType": "audio/mp4",
  "fileExtension": "m4a",
  "provider": "youtube",
  "providerItemId": "dQw4w9WgXcQ"
}
```

## Error contract

Invalid request, HTTP `400`:

```json
{
  "error": "invalid_request",
  "message": "The \"mediaType\" field must be either \"audio\" or \"video\"."
}
```

No downloadable media, HTTP `422`:

```json
{
  "error": "no_downloadable_media",
  "message": "No downloadable progressive video stream is available for this YouTube item."
}
```

Extractor failure, HTTP `500`:

```json
{
  "error": "extractor_failure",
  "message": "YouTube extraction failed: ..."
}
```

## Format selection behavior

- `mediaType=audio` prefers direct `audio/mp4` audio-only streams, then falls back to other audio-capable formats
- `mediaType=audio` now resolves through a bridge-hosted remux flow so the app downloads a proper single-file `.m4a` instead of saving a raw DASH audio source
- `mediaType=video` prefers direct progressive `video/mp4` streams that already include both audio and video
- The bridge intentionally does not return video-only DASH streams for `mediaType=video`, because that would require separate muxing before the iOS downloader could use the result as a single downloadable file

## Notes and limitations

- This bridge uses `youtube-dl-exec`, a Node wrapper around `yt-dlp`
- `youtube-dl-exec` downloads a `yt-dlp` binary during `npm install`, and it expects Python `3.10+` to be available locally
- This bridge prefers Homebrew Python automatically on macOS (`/opt/homebrew/bin/python3` or `/usr/local/bin/python3`), and you can override that with `YT_DLP_PYTHON_PATH`
- YouTube format availability can change by video, region, age restriction, account state, or YouTube-side platform changes
- Some videos may only expose adaptive streams, DRM-protected streams, or formats that are not suitable as a single-file direct download
- Direct media URLs from YouTube are time-limited and should be used shortly after resolution
- For a physical iPhone to download from this bridge, the bridge host embedded in returned URLs must be reachable from the phone, which means using the Mac LAN IP instead of `127.0.0.1`
