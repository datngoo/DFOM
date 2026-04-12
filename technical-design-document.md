# iOS Music App Technical Design Document

## 1. Document Purpose

This document defines the proposed technical design for a personal-use iOS music/media app based on the V1 scope in `Defined product scope and V1 requirements.txt`.

The goal is to produce a buildable, realistic, and maintainable plan before implementation begins.

## 2. Product Summary

### Objective

Build a personal iOS app for learning iOS architecture and mobile development that can:

- Accept a direct YouTube video URL
- Resolve a single media item from that URL
- Show result details
- Download audio or video for offline use
- Persist media and metadata locally
- Play downloaded media offline
- Show a local library after app relaunch

### Target User

- Single user: project owner

### Platform

- iOS only
- Must run on a real iPhone

## 3. Scope

### In Scope for V1

- Direct YouTube video URL input
- URL resolution to a single media item
- Item detail view
- Audio download option
- Video download option
- Local library view
- Offline playback
- Local persistence of downloaded items and metadata
- Local thumbnail caching for downloaded video items

### Out of Scope for V1

- App Store release
- Multi-user support
- Social features
- Recommendations
- Cloud sync
- Advanced UI polish

## 4. Key Product Risks

### 4.1 Content Source and Compliance Risk

The requirement says the app should resolve YouTube URLs and download audio/video. That creates a major design risk:

- Official YouTube APIs support search metadata, but media download/offline behavior is restricted
- Direct downloading from YouTube may violate platform terms, depending on the method used
- Third-party extraction tooling can be unstable and may break frequently
- App Store distribution would be especially problematic, though V1 is not targeting App Store release

### Design Decision

The architecture should **not** tightly couple the app to a single YouTube-specific download implementation.

Instead, V1 should use a **provider-based architecture**:

- `URLResolutionProvider` for resolving a pasted URL into media metadata
- `DownloadProvider` for media acquisition
- `MetadataMapper` for transforming external data into app models

This keeps the app usable even if the initial provider approach changes later.

### 4.2 Persistence Expectations

The requirement says data should remain after relaunch and "where possible" after rebuild. On iPhone, uninstalling or replacing app containers can remove app sandbox data.

### Design Decision

For V1, the persistence target should be:

- Survives normal app relaunch
- Survives device reboot
- Usually survives reinstall-from-Xcode only if container is preserved, but this should not be guaranteed

This should be documented as a practical limitation, not a bug.

## 5. Recommended Technical Approach

### 5.1 App Stack

- Language: Swift
- UI framework: SwiftUI
- Concurrency: Swift Concurrency (`async/await`, `Task`, actors where useful)
- Local database: SwiftData
- Media playback: `AVFoundation` / `AVPlayer`
- Networking: `URLSession`
- File storage: app sandbox, primarily Application Support

### 5.2 Why This Stack

- SwiftUI keeps the learning project modern and fast to iterate on
- SwiftData is sufficient for V1 local metadata persistence
- AVFoundation is the standard native solution for offline playback
- URLSession supports resumable downloads and system-friendly networking

## 6. High-Level Architecture

The app should follow a layered architecture with clear responsibilities.

### 6.1 Layers

#### Presentation Layer

SwiftUI screens and view models.

Responsibilities:

- Render URL input, details, library, and player UI
- Trigger user actions
- Observe state changes
- Show loading, progress, success, and error states

#### Domain Layer

Use cases and business rules.

Responsibilities:

- Resolve a direct media URL
- Start/cancel downloads
- Load library
- Resolve playable local files
- Enforce state transitions for media items

#### Data Layer

Repositories, local persistence, file storage, and provider integration.

Responsibilities:

- Talk to external provider(s)
- Save and query metadata
- Store downloaded files
- Reconcile file system and database state

## 7. Module Breakdown

For a small V1, this can start as a single Xcode app target with internal folder-based modularization. If the project grows, it can later split into Swift Packages.

### Proposed Internal Modules

- `App`
- `Features/URLInput`
- `Features/Detail`
- `Features/Library`
- `Features/Player`
- `Domain`
- `Data`
- `Infrastructure/Networking`
- `Infrastructure/Persistence`
- `Infrastructure/FileStorage`

## 8. Functional Design

### 8.1 URL Input And Resolution

#### User Flow

1. User pastes or types a YouTube video URL
2. App validates the URL format
3. App sends the URL to the provider abstraction
4. Provider resolves metadata for the specific media item
5. Resolved data is mapped into app models
6. App opens the item detail screen

#### Resolved Media Data Needed

- Provider item ID
- Title
- Channel/creator name
- Thumbnail URL
- Duration if available
- Source URL
- Available resource choices for audio and video if inferable

#### URL Input UX Notes

- Support paste-friendly input
- Support explicit resolve submission
- Show validation, loading, and retry states
- No result list is needed in this phase

### 8.2 Item Detail

#### Purpose

Show enough metadata for the user to decide whether to download.

#### UI Elements

- Thumbnail/artwork
- Title
- Creator/source
- Duration
- Audio download action
- Video download action
- Download progress or status

### 8.3 Download

#### User Flow

1. User chooses either audio or video from the detail screen
2. App resolves a downloadable media source using the provider
3. App creates a library record in pending state
4. File download begins
5. Progress updates are shown
6. On success, file is moved to managed local storage
7. If the item is a video, the thumbnail is cached locally where possible
8. Metadata is updated to downloaded state
9. Item becomes playable offline

#### Download States

- `notDownloaded`
- `queued`
- `downloading`
- `downloaded`
- `failed`

#### Download Requirements

- Support one-item download for V1 success criteria
- Prefer serial downloads in V1 for simplicity
- Save file atomically after successful transfer
- Store enough metadata to rebuild library screen from local persistence
- Support both audio and video as separate user-selectable outputs

### 8.4 Library

#### User Flow

1. User opens Library tab
2. App loads persisted items from local database
3. Items are sorted by most recent download
4. User can open or play an item

#### Library Metadata

- Internal item ID
- Provider/source ID
- Title
- Creator
- Thumbnail path or remote thumbnail URL
- File path
- Media kind
- File size if available
- Download date
- Download status
- Playback duration if known
- Selected resource type for the downloaded item

### 8.5 Offline Playback

#### User Flow

1. User taps a downloaded item
2. App validates local file existence
3. Player screen opens
4. AVPlayer plays local content

#### V1 Playback Features

- Play/pause
- Seek bar
- Elapsed and remaining time
- Basic Now Playing metadata if practical

#### Not Required for V1

- Background audio polish
- Playlist queue management
- Lock screen remote controls
- Playback speed controls

## 9. Non-Functional Requirements

### Performance

- URL resolution should feel responsive on a real device
- Library should open quickly from local storage
- Playback should start promptly for local files

### Reliability

- App should recover gracefully if a file is missing but the database record exists
- Failed downloads should not leave corrupt library records

### Maintainability

- Provider abstraction should isolate unstable external integrations
- Repositories should hide storage implementation details from UI

### Security and Privacy

- No account system in V1
- Store only local media metadata needed for app function
- Avoid collecting analytics in V1

## 10. Data Model

### 10.1 Core Entity: MediaItem

Suggested fields:

- `id: UUID`
- `provider: String`
- `providerItemId: String`
- `title: String`
- `creatorName: String?`
- `mediaType: MediaType`
- `sourcePageUrl: String?`
- `thumbnailUrl: String?`
- `thumbnailLocalPath: String?`
- `localFilePath: String?`
- `downloadStatus: DownloadStatus`
- `downloadProgress: Double`
- `durationSeconds: Double?`
- `fileSizeBytes: Int64?`
- `createdAt: Date`
- `downloadedAt: Date?`
- `lastPlayedAt: Date?`

### 10.2 Enums

#### MediaType

- `audio`
- `video`
- `unknown`

#### DownloadStatus

- `notDownloaded`
- `queued`
- `downloading`
- `downloaded`
- `failed`

## 11. Storage Design

### 11.1 Database

Use SwiftData to persist `MediaItem` metadata.

Why:

- Native Apple framework
- Good enough for a single-user offline library
- Lower setup cost than Core Data for this project

### 11.2 File Storage

Use the app sandbox `Application Support` directory for managed media files.

Suggested structure:

```text
Application Support/
  Media/
    <media-item-uuid>/
      media.bin
      thumbnail.jpg
```

### 11.3 File Naming Strategy

- Do not trust source titles for file names
- Use app-generated UUID-based folders
- Store human-readable metadata in the database, not the path

### 11.4 Storage Reconciliation

On app launch:

- Load persisted library metadata
- Validate file existence for downloaded items
- If file is missing, mark item as failed or unavailable

## 12. Networking Design

### 12.1 Search Networking

- URL resolution requests go through a provider client
- Provider client returns transport DTOs
- Mapper transforms DTOs into domain/app models

### 12.2 Download Networking

- Use `URLSessionDownloadTask` where feasible
- Write to temporary file first
- Move to managed storage after completion

### 12.3 Error Categories

- Network unavailable
- Provider response invalid
- Download source unavailable
- Local file move failed
- Playback file missing

## 13. Provider Abstraction

This is the most important architectural choice in the project.

### 13.1 Protocols

Suggested protocols:

```swift
protocol URLResolutionProvider {
    func resolve(url: URL) async throws -> ResolvedMediaItem
}

protocol DownloadProvider {
    func resolveDownload(for item: ResolvedMediaItem, resourceType: MediaType) async throws -> DownloadDescriptor
}
```

### 13.2 Why This Matters

- URL resolution and download may come from different implementations
- External media source rules may change
- Swapping provider strategy should not require rewriting the app

### 13.3 V1 Recommendation

Treat the provider layer as replaceable from day one. Even in a small learning project, this is worth it because the unstable part is the external integration, not the app shell.

## 14. App Navigation

### Recommended Tab Structure

- Input
- Library

### Navigation Flows

- Input tab -> URL resolution -> detail -> choose audio/video -> download
- Library tab -> item detail or direct player

### Modal/Push Strategy

- Use `NavigationStack`
- Player can be pushed or presented as a sheet; push is simpler for V1 consistency

## 15. UI Screen Plan

### 15.1 URL Input Screen

Components:

- URL text field
- Paste-friendly input behavior
- Resolve action
- Validation/loading/error states

### 15.2 Detail Screen

Components:

- Large thumbnail
- Metadata block
- Audio download action
- Video download action
- Progress state
- Error state

### 15.3 Library Screen

Components:

- Downloaded items list
- Empty state
- Status badges
- Tap to open player

### 15.4 Player Screen

Components:

- Artwork/thumbnail
- Title
- Play/pause
- Seek slider
- Time labels

## 16. State Management

### Recommended Pattern

- One view model per feature screen
- Repositories injected into view models
- Observable state owned by feature boundaries

### Example View Models

- `URLInputViewModel`
- `MediaDetailViewModel`
- `LibraryViewModel`
- `PlayerViewModel`

### State Principles

- Keep provider DTOs out of SwiftUI views
- Views render app state, not raw network responses
- Persist only durable state
- Keep ephemeral state like active URL input text in memory

## 17. Error Handling Strategy

### User-Facing Error Principles

- Show simple messages
- Allow retry for URL resolution and download failures
- Keep partial failures isolated

### Examples

- URL resolution failed -> inline retry state
- Download failed -> item remains in library with failed state or is cleaned up
- Local file missing -> show unavailable message and allow delete/retry

## 18. Logging and Debugging

For V1, lightweight logging is enough.

Recommended:

- Use `Logger` from `OSLog`
- Log URL resolution requests, download lifecycle events, file moves, and playback failures

Do not log:

- Sensitive tokens if any provider uses them
- Full local paths unless needed for debugging

## 19. Testing Strategy

### Unit Tests

Test:

- URL resolution mapping
- Download state transitions
- Repository behavior
- File storage path generation
- Library reconciliation logic

### Integration Tests

Test:

- URL resolution flow with mocked provider
- Download completion pipeline with mocked transport
- Playback opening for local files

### Manual Device Tests

Essential because the app must run on a real iPhone.

Test scenarios:

- Paste a valid YouTube video URL
- Resolve the URL into a media item
- Open details
- Download one audio item
- Download one video item
- Kill and relaunch app
- Confirm library persists
- Play downloaded media offline with network disabled

## 20. Build Phasing

### Phase 1: App Foundation

- Create project structure
- Add tab navigation
- Add models, repositories, protocols, and persistence setup

### Phase 2: URL Input Flow

- Build URL input UI
- Wire provider abstraction
- Resolve a single item and show details

### Phase 3: Download Flow

- Add download orchestration
- Persist records
- Save files locally

### Phase 4: Library and Playback

- Build library screen
- Validate file persistence
- Add offline player

### Phase 5: Hardening

- Improve error states
- Add reconciliation at launch
- Add tests and device validation

## 21. Resolved Design Decisions

### 21.1 Content Source Strategy

- YouTube is the primary provider for this personal-use learning project
- For this phase, the app accepts a direct YouTube video URL instead of keyword search
- The architecture still keeps provider behavior isolated because the integration may be fragile over time

### 21.2 Media Scope

- V1 supports both audio and video
- Implementation should still be broken into small phases so audio and video paths can be built and validated independently

### 21.3 Thumbnail Handling

- Audio thumbnail caching is optional for V1
- Video thumbnail caching should be supported for downloaded items so the library remains recognizable offline

## 22. Recommended V1 Simplifications

To maximize the chance of success, I recommend:

- Start with a single provider implementation behind protocols
- Support single-item download flow before any queueing
- Keep URL input limited to one resolved item at a time
- Use local thumbnail caching only for downloaded items, with video as the priority
- Keep player features minimal

## 23. Success Mapping

The proposed design satisfies the stated success criteria as follows:

- Install on iPhone -> native SwiftUI iOS app
- Paste a valid YouTube URL -> URL input and resolution flow
- Resolve the media item -> provider mapping and detail flow
- Download one audio or video item -> download orchestration and local file storage
- See it in library -> SwiftData-backed library screen
- Play it offline -> AVPlayer on local files
- Library remains after relaunch -> persisted metadata plus sandbox file storage

## 24. Recommended Initial File/Folder Structure

```text
IOSMusicApp/
  App/
  Features/
    URLInput/
    Detail/
    Library/
    Player/
  Domain/
    Models/
    UseCases/
    Protocols/
  Data/
    Repositories/
    Providers/
    Mappers/
  Infrastructure/
    Networking/
    Persistence/
    FileStorage/
    Logging/
  Resources/
  Tests/
```

## 25. Final Recommendation

This app is very feasible as a personal iPhone project if the architecture is kept clean and the risky part is isolated.

The best implementation path is:

- Use SwiftUI + SwiftData + AVFoundation
- Build a provider abstraction before any source-specific integration
- Treat URL resolution/download source integration as replaceable
- Keep V1 deliberately narrow and verifiable on a real device

If we move to implementation next, the first coding step should be turning this design into a concrete project scaffold and deciding the provider strategy before any network code is written.
