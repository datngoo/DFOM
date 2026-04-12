# KAN-7 YouTube Provider Spike

## What KAN-7 does

KAN-7 finalizes the app-facing provider contracts for URL resolution and download resolution, then adds a compile-safe YouTube spike implementation.

## What is implemented now

- A normalized `ResolvedMediaItem` model for provider metadata
- A normalized `DownloadDescriptor` model for provider download resolution
- App-facing `ProviderError` cases for common provider failure paths
- A `YouTubeURLParser` that validates common YouTube URL shapes and extracts a video ID
- A `YouTubeProviderSpike` that returns deterministic mock metadata and deterministic placeholder download descriptors
- A DEBUG-only launch-argument runner for manual verification without UI coupling

## What is intentionally not implemented yet

- Real metadata fetching from YouTube
- Real stream extraction or signature deciphering
- Real file transfer or background downloads
- User-facing provider UI flows
- Credential handling, rate limiting, retries, or caching

## Why provider abstraction matters

Provider abstractions keep app code independent from site-specific parsing and later download details. That separation will let later KANs add real resolution logic, alternate providers, and retries without coupling view code to external source behavior.

## Recommended next steps

- KAN-8 should replace deterministic metadata with a real metadata acquisition layer and DTO mapping.
- KAN-9 should introduce real download variant selection and safer descriptor generation before any actual file transfer work starts.

## Main fragility and maintenance risks

- YouTube URL formats and page structures can change over time.
- Any future real integration may be brittle if it relies on undocumented response shapes.
- Stream URLs can be short-lived and may require signature or token handling.
- Provider logic should stay isolated so breakage can be contained and replaced quickly.
