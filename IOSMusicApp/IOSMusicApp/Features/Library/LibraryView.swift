import SwiftUI
import SwiftData
import UIKit
import OSLog

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlaybackController: AudioPlaybackController
    @Query(
        sort: [
            SortDescriptor(\MediaItem.downloadedDate, order: .reverse),
            SortDescriptor(\MediaItem.createdDate, order: .reverse)
        ]
    ) private var mediaItems: [MediaItem]
    @Query(
        sort: [
            SortDescriptor(\Playlist.createdDate, order: .reverse),
            SortDescriptor(\Playlist.name)
        ]
    ) private var playlists: [Playlist]
    @StateObject private var viewModel: LibraryViewModel
    @State private var isCreatePlaylistPresented = false
    @State private var itemPendingPlaylistSelection: MediaItem?
    @State private var itemPendingDeletion: MediaItem?
    @State private var itemPendingMetadataEdit: MediaItem?
    @State private var itemPendingVideoPlayback: MediaItem?
    @State private var songSearchText = ""
    private let fileStorage: LocalFileStorage
    private let logger = Logger(subsystem: "IOSMusicApp", category: "LibraryView")

    init(fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        self.fileStorage = fileStorage
        _viewModel = StateObject(wrappedValue: LibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            List {
                libraryControlsHeader

                switch viewModel.selectedTab {
                case .songs, .videos:
                    mediaItemsSection
                case .playlists:
                    playlistsSection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Library")
            .toolbar {
                if viewModel.selectedTab == .playlists {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isCreatePlaylistPresented = true
                        } label: {
                            Label("Create Playlist", systemImage: "plus")
                        }
                    }
                }
            }
            .task {
                await ensureDefaultPlaylistsIfNeeded()
                await migratePersistedManagedPathsIfNeeded()
            }
            .sheet(isPresented: $isCreatePlaylistPresented) {
                CreatePlaylistView()
            }
            .sheet(item: $itemPendingPlaylistSelection) { item in
                AddToPlaylistView(
                    item: item,
                    playlists: compatibleAudioPlaylists(for: item)
                )
            }
            .sheet(item: $itemPendingMetadataEdit) { item in
                EditSongMetadataView(item: item)
            }
            .fullScreenCover(item: $itemPendingVideoPlayback) { item in
                VideoPlayerView(item: item, fileStorage: fileStorage)
            }
            .alert(
                "Delete Item?",
                isPresented: Binding(
                    get: { itemPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { itemPendingDeletion = nil }
                    }
                ),
                presenting: itemPendingDeletion
            ) { item in
                Button("Delete", role: .destructive) {
                    delete(item: item)
                    itemPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    itemPendingDeletion = nil
                }
            } message: { item in
                Text(deleteConfirmationMessage(for: item))
            }
            .onChange(of: viewModel.selectedTab) { _, selectedTab in
                if selectedTab != .songs { songSearchText = "" }
            }
        }
    }

    // MARK: - Section builders

    private var mediaItemsSection: some View {
        Group {
            if viewModel.selectedTab == .songs {
                if displayedMediaItems.isEmpty {
                    emptyStateRow(
                        icon: "music.note",
                        message: viewModel.emptyStateDescription
                    )
                } else {
                    songsActionSection
                    ForEach(displayedMediaItems) { item in
                        songRow(for: item)
                    }
                }
            } else {
                Section(viewModel.sectionTitle) {
                    if displayedMediaItems.isEmpty {
                        emptyStateRow(
                            icon: "film",
                            message: viewModel.emptyStateDescription
                        )
                    } else {
                        ForEach(displayedMediaItems) { item in
                            if viewModel.selectedTab == .videos, isPlayableVideoItem(item) {
                                videoRow(for: item)
                            } else {
                                NavigationLink {
                                    if isPlayableAudioItem(item) {
                                        LibraryMediaDetailView(
                                            item: item,
                                            audioPlaylist: playableAudioItems,
                                            fileStorage: fileStorage
                                        )
                                    } else {
                                        LibraryMediaDetailView(item: item, fileStorage: fileStorage)
                                    }
                                } label: {
                                    MediaItemRow(
                                        item: item,
                                        fileStorage: fileStorage,
                                        style: .library
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var playlistsSection: some View {
        Section(viewModel.sectionTitle) {
            Button {
                isCreatePlaylistPresented = true
            } label: {
                Label("Create New Playlist", systemImage: "plus.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }

            if displayedPlaylists.isEmpty {
                emptyStateRow(
                    icon: "music.note.list",
                    message: viewModel.emptyStateDescription
                )
            } else {
                ForEach(displayedPlaylists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist, fileStorage: fileStorage)
                    } label: {
                        PlaylistRow(playlist: playlist)
                    }
                }
            }
        }
    }

    // MARK: - Controls header

    private var libraryControlsHeader: some View {
        VStack(spacing: 0) {
            libraryTabPicker
            if viewModel.selectedTab == .songs {
                songsSearchBar
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color(.systemGroupedBackground))
    }

    private var libraryTabPicker: some View {
        Picker("Library Section", selection: $viewModel.selectedTab) {
            ForEach(LibraryViewModel.LibraryTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, viewModel.selectedTab == .songs ? 10 : 14)
    }

    private var songsSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Search songs", text: $songSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)

            if !songSearchText.isEmpty {
                Button {
                    songSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(.tertiaryLabel))
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .animation(.easeInOut(duration: 0.15), value: songSearchText.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Play actions section

    private var songsActionSection: some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    playAllSongs()
                } label: {
                    Label("Play All  \(playableAudioItems.count)", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(playableAudioItems.isEmpty)

                Button {
                    playRandomSongs()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(playableAudioItems.isEmpty)
            }
            .textCase(nil)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .listSectionSpacing(4)
    }

    // MARK: - Row builders (logic unchanged, styling only)

    private func songRow(for item: MediaItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                playSong(item)
            } label: {
                MediaItemRow(
                    item: item,
                    fileStorage: fileStorage,
                    style: .song
                )
            }
            .buttonStyle(.plain)
            .disabled(!isPlayableAudioItem(item))

            Menu {
                Button {
                    itemPendingMetadataEdit = item
                } label: {
                    Label("Edit Info", systemImage: "pencil")
                }
                Button {
                    itemPendingPlaylistSelection = item
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                Button {
                    queueSongNext(item)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(!isPlayableAudioItem(item))
                Button(role: .destructive) {
                    itemPendingDeletion = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                    )
                    .contentShape(Circle())
            }
            .disabled(item.mediaType != .audio)
        }
    }

    private func videoRow(for item: MediaItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                itemPendingVideoPlayback = item
            } label: {
                MediaItemRow(
                    item: item,
                    fileStorage: fileStorage,
                    style: .library
                )
            }
            .buttonStyle(.plain)
            .disabled(!isPlayableVideoItem(item))

            Menu {
                Button {
                    itemPendingVideoPlayback = item
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!isPlayableVideoItem(item))
                Button(role: .destructive) {
                    itemPendingDeletion = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                    )
                    .contentShape(Circle())
            }
        }
    }

    // MARK: - Empty state helper

    @ViewBuilder
    private func emptyStateRow(icon: String, message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.quaternary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.tertiarySystemFill))
                )

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed properties (unchanged)

    private var displayedMediaItems: [MediaItem] {
        let baseItems = viewModel.filteredItems(from: mediaItems)
        guard viewModel.selectedTab == .songs else { return baseItems }
        let songItems = baseItems.filter { !isPodcastOnlyItem($0) }
        let normalizedSearchText = songSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSearchText.isEmpty else { return songItems }
        return songItems.filter { item in
            item.title.localizedCaseInsensitiveContains(normalizedSearchText) ||
            (item.creatorName?.localizedCaseInsensitiveContains(normalizedSearchText) ?? false)
        }
    }

    private var displayedPlaylists: [Playlist] {
        viewModel.filteredPlaylists(from: playlists)
    }

    private var playableAudioItems: [MediaItem] {
        mediaItems.filter(isPlayableAudioItem)
    }

    // MARK: - Private action functions (100% unchanged)

    private func delete(item: MediaItem) {
        delete(items: [item])
    }

    private func delete(items: [MediaItem]) {
        var playlistsToReset: [UUID: Playlist] = [:]
        for item in items {
            let entries = item.playlistEntries
            for entry in entries {
                if let playlist = entry.playlist, playlist.entries.count <= 1 {
                    playlistsToReset[playlist.id] = playlist
                }
                modelContext.delete(entry)
            }
            do {
                try fileStorage.deleteStoredFiles(for: item.id)
            } catch {
                logger.error("Failed to delete stored files for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            modelContext.delete(item)
        }
        do {
            for playlist in playlistsToReset.values {
                playlist.setMediaType(.unknown)
                playlist.syncMediaTypeRawValueIfNeeded()
            }
            try modelContext.save()
        } catch {
            logger.error("Failed to persist Library deletion: \(String(describing: error), privacy: .public)")
        }
    }

    @MainActor
    private func migratePersistedManagedPathsIfNeeded() async {
        var hasChanges = false
        for item in mediaItems {
            if let normalizedLocalPath = normalizedManagedPathIfAvailable(item.localFilePath),
               normalizedLocalPath != item.localFilePath {
                item.localFilePath = normalizedLocalPath
                hasChanges = true
            }
            if let normalizedThumbnailPath = normalizedManagedPathIfAvailable(item.thumbnailLocalPath),
               normalizedThumbnailPath != item.thumbnailLocalPath {
                item.thumbnailLocalPath = normalizedThumbnailPath
                hasChanges = true
            }
        }
        guard hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to migrate managed Library paths: \(String(describing: error), privacy: .public)")
        }
    }

    private func normalizedManagedPathIfAvailable(_ persistedPath: String?) -> String? {
        guard let normalizedPath = try? fileStorage.normalizedManagedPathIfAvailable(persistedPath) else {
            return nil
        }
        return normalizedPath
    }

    @MainActor
    private func ensureDefaultPlaylistsIfNeeded() async {
        guard !playlists.contains(where: \.isPodcastsPlaylist) else { return }
        let podcastsPlaylist = Playlist(name: Playlist.podcastsName, mediaType: .audio)
        modelContext.insert(podcastsPlaylist)
        do {
            podcastsPlaylist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
        } catch {
            logger.error("Failed to create default Podcasts playlist: \(String(describing: error), privacy: .public)")
        }
    }

    private func isPlayableAudioItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .audio)
    }

    private func isPlayableVideoItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .video)
    }

    private func isPlayableLibraryItem(_ item: MediaItem, expectedMediaType: MediaType) -> Bool {
        guard item.mediaType == expectedMediaType,
              item.downloadStatus == .downloaded else { return false }
        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }

    private func compatibleAudioPlaylists(for item: MediaItem) -> [Playlist] {
        viewModel.compatiblePlaylists(for: item, from: playlists)
    }

    private func isPodcastOnlyItem(_ item: MediaItem) -> Bool {
        item.playlistEntries.contains { entry in
            entry.playlist?.isPodcastsPlaylist == true
        }
    }

    private func playSong(_ item: MediaItem) {
        guard isPlayableAudioItem(item) else { return }
        audioPlaybackController.configure(item: item, playlist: playableAudioItems, fileStorage: fileStorage)
        audioPlaybackController.play()
    }

    private func queueSongNext(_ item: MediaItem) {
        guard isPlayableAudioItem(item) else { return }
        audioPlaybackController.enqueueNext(item: item, from: playableAudioItems, fileStorage: fileStorage)
    }

    private func playAllSongs() {
        guard !playableAudioItems.isEmpty else { return }
        audioPlaybackController.startQueue(items: playableAudioItems, startAt: 0, fileStorage: fileStorage)
    }

    private func playRandomSongs() {
        let shuffledItems = playableAudioItems.shuffled()
        guard !shuffledItems.isEmpty else { return }
        audioPlaybackController.startQueue(items: shuffledItems, startAt: 0, fileStorage: fileStorage)
    }

    private func deleteConfirmationMessage(for item: MediaItem) -> String {
        switch item.mediaType {
        case .audio:
            return "\"\(item.title)\" will be removed from your library and playlists."
        case .video:
            return "\"\(item.title)\" will be removed from your library."
        case .unknown:
            return "\"\(item.title)\" will be removed from your library."
        }
    }
}

// MARK: - MediaItemRow

private struct MediaItemRow: View {
    enum Style {
        case library
        case song
    }

    let item: MediaItem
    let fileStorage: LocalFileStorage
    let style: Style

    private enum ArtworkLayout {
        static let size: CGFloat = 52
        static let cornerRadius: CGFloat = 9
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            artworkView
                .frame(width: ArtworkLayout.size, height: ArtworkLayout.size)
                .clipShape(RoundedRectangle(cornerRadius: ArtworkLayout.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(artistLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if style == .library {
                    HStack(spacing: 4) {
                        statusChip
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: Artwork

    @ViewBuilder
    private var artworkView: some View {
        if let thumbnailImage {
            Image(uiImage: thumbnailImage)
                .resizable()
                .scaledToFill()
        } else if let remoteThumbnailURL = preferredRemoteThumbnailURL {
            AsyncImage(url: remoteThumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderArtwork
                }
            }
        } else {
            placeholderArtwork
        }
    }

    private var thumbnailImage: UIImage? {
        guard let thumbnailLocalPath = item.thumbnailLocalPath,
              !thumbnailLocalPath.isEmpty,
              let thumbnailURL = try? fileStorage.resolveExistingManagedFileURL(from: thumbnailLocalPath) else {
            return nil
        }
        return UIImage(contentsOfFile: thumbnailURL.path)
    }

    private var preferredRemoteThumbnailURL: URL? {
        guard item.mediaType == .video || style == .song else { return nil }
        return item.thumbnailRemoteURL
    }

    private var placeholderArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.secondarySystemFill),
                    Color(.tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.mediaType == .video ? "film" : "music.note")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Status chip

    @ViewBuilder
    private var statusChip: some View {
        let (label, color) = statusChipInfo
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(color.opacity(0.12))
        )
    }

    private var statusChipInfo: (String, Color) {
        if item.downloadStatus == .downloaded,
           item.localFilePath != nil,
           (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) == nil {
            return ("Unavailable", .orange)
        }
        switch item.downloadStatus {
        case .downloaded:  return ("Downloaded", .green)
        case .failed:      return ("Failed", .red)
        case .queued:      return ("Queued", .orange)
        case .downloading: return ("Downloading", .blue)
        case .notDownloaded: return ("Not Downloaded", Color(.tertiaryLabel))
        }
    }

    // MARK: Helpers

    private var artistLabel: String {
        let trimmedCreator = item.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedCreator.isEmpty ? "Unknown artist" : trimmedCreator
    }
}

// MARK: - PlaylistRow

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.75), Color.accentColor.opacity(0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("\(playlist.itemCount) song\(playlist.itemCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - LibraryMediaDetailView

private struct LibraryMediaDetailView: View {
    private enum Layout {
        static let screenPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 20
        static let cardPadding: CGFloat = 16
        static let cardCornerRadius: CGFloat = 14
    }

    @Query(
        sort: [
            SortDescriptor(\Playlist.createdDate, order: .reverse),
            SortDescriptor(\Playlist.name)
        ]
    ) private var playlists: [Playlist]
    @State private var isPlaylistPickerPresented = false

    let item: MediaItem
    let audioPlaylist: [MediaItem]
    let fileStorage: LocalFileStorage

    init(
        item: MediaItem,
        audioPlaylist: [MediaItem] = [],
        fileStorage: LocalFileStorage
    ) {
        self.item = item
        self.audioPlaylist = audioPlaylist
        self.fileStorage = fileStorage
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                // Large artwork header
                artworkHeader

                // Action buttons
                VStack(spacing: 10) {
                    if isPlayableAudioItem(item) {
                        NavigationLink {
                            AudioPlayerView(
                                item: item,
                                playlist: audioPlaylist,
                                fileStorage: fileStorage
                            )
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    } else if isPlayableVideoItem(item) {
                        NavigationLink {
                            VideoPlayerView(item: item, fileStorage: fileStorage)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if canAddToPlaylist(item) {
                        Button {
                            isPlaylistPickerPresented = true
                        } label: {
                            Label("Add to Playlist", systemImage: "text.badge.plus")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Metadata card
                VStack(alignment: .leading, spacing: 12) {
                    DetailValueRow(label: "Creator", value: item.creatorName ?? "Unknown creator")
                    Divider()
                    DetailValueRow(label: "Type", value: item.mediaType.rawValue.capitalized)
                    Divider()
                    DetailValueRow(label: "Status", value: statusLabel)

                    if let localFilePath = item.localFilePath, !localFilePath.isEmpty {
                        Divider()
                        DetailValueRow(label: "Local Path", value: localFilePath)
                    }
                }
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .padding(.horizontal, Layout.screenPadding)
            .padding(.vertical, Layout.screenPadding)
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPlaylistPickerPresented) {
            AddToPlaylistView(
                item: item,
                playlists: compatiblePlaylists(for: item)
            )
        }
    }

    @ViewBuilder
    private var artworkHeader: some View {
        HStack(spacing: 16) {
            // Artwork tile
            Group {
                if let thumbnailLocalPath = item.thumbnailLocalPath,
                   !thumbnailLocalPath.isEmpty,
                   let url = try? fileStorage.resolveExistingManagedFileURL(from: thumbnailLocalPath),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let remoteURL = item.thumbnailRemoteURL {
                    AsyncImage(url: remoteURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: artworkPlaceholder
                        }
                    }
                } else {
                    artworkPlaceholder
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(3)
                Text(item.creatorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.secondarySystemFill), Color(.tertiarySystemFill)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.mediaType == .video ? "film" : "music.note")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // Logic unchanged
    private func compatiblePlaylists(for item: MediaItem) -> [Playlist] {
        guard item.mediaType == .audio else { return [] }
        return playlists.filter { $0.mediaType == .audio || $0.mediaType == .unknown }
    }

    private func canAddToPlaylist(_ item: MediaItem) -> Bool { isPlayableAudioItem(item) }
    private func isPlayableAudioItem(_ item: MediaItem) -> Bool { isPlayableLibraryItem(item, expectedMediaType: .audio) }
    private func isPlayableVideoItem(_ item: MediaItem) -> Bool { isPlayableLibraryItem(item, expectedMediaType: .video) }

    private func isPlayableLibraryItem(_ item: MediaItem, expectedMediaType: MediaType) -> Bool {
        guard item.mediaType == expectedMediaType, item.downloadStatus == .downloaded else { return false }
        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }

    private var statusLabel: String {
        if item.downloadStatus == .downloaded,
           item.localFilePath != nil,
           (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) == nil {
            return "Unavailable"
        }
        switch item.downloadStatus {
        case .downloaded:    return "Downloaded"
        case .failed:        return "Failed"
        case .queued:        return "Queued"
        case .downloading:   return "Downloading"
        case .notDownloaded: return "Not Downloaded"
        }
    }
}

// MARK: - DetailValueRow

private struct DetailValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - CreatePlaylistView (logic unchanged, minor layout polish)

private struct CreatePlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var playlistName = ""
    @State private var errorMessage: String?
    let onCreate: ((Playlist) -> Void)?

    init(onCreate: ((Playlist) -> Void)? = nil) {
        self.onCreate = onCreate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("New Playlist", text: $playlistName)
                        .textInputAutocapitalization(.words)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createPlaylist() }
                        .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createPlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { errorMessage = "Playlist name is required."; return }
        if trimmedName.localizedCaseInsensitiveCompare(Playlist.podcastsName) == .orderedSame {
            errorMessage = "\"\(Playlist.podcastsName)\" is a system playlist and already exists."
            return
        }
        let playlist = Playlist(name: trimmedName, mediaType: .audio)
        modelContext.insert(playlist)
        do {
            playlist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
            onCreate?(playlist)
            dismiss()
        } catch {
            errorMessage = "Could not create playlist right now."
        }
    }
}

// MARK: - EditSongMetadataView (unchanged)

private struct EditSongMetadataView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem
    @State private var songName: String
    @State private var singerName: String
    @State private var errorMessage: String?

    init(item: MediaItem) {
        self.item = item
        _songName = State(initialValue: item.title)
        _singerName = State(initialValue: item.creatorName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Song") {
                    TextField("Song name", text: $songName)
                        .textInputAutocapitalization(.words)
                }
                Section("Singer") {
                    TextField("Singer", text: $singerName)
                        .textInputAutocapitalization(.words)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveChanges() } }
            }
        }
    }

    private func saveChanges() {
        let trimmedSongName = songName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSongName.isEmpty else { errorMessage = "Song name is required."; return }
        let trimmedSingerName = singerName.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = trimmedSongName
        item.creatorName = trimmedSingerName.isEmpty ? nil : trimmedSingerName
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not save the updated song info."
        }
    }
}

// MARK: - AddToPlaylistView (unchanged)

private struct AddToPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem
    let playlists: [Playlist]
    @State private var errorMessage: String?
    @State private var isCreatePlaylistPresented = false

    var body: some View {
        NavigationStack {
            List {
                Section("Song") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text("Audio").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section("Playlists") {
                    if playlists.isEmpty {
                        Text("No song playlists yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                addItem(to: playlist)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name).foregroundStyle(.primary)
                                        Text("Songs • \(playlist.itemCount) item\(playlist.itemCount == 1 ? "" : "s")")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if playlist.contains(item) {
                                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(playlist.contains(item))
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create New") { isCreatePlaylistPresented = true }
                }
            }
            .sheet(isPresented: $isCreatePlaylistPresented) {
                CreatePlaylistView { playlist in addItem(to: playlist) }
            }
        }
    }

    private func addItem(to playlist: Playlist) {
        guard item.mediaType == .audio else { errorMessage = "Only songs can be added to playlists."; return }
        guard playlist.canAccept(item) else { errorMessage = "This playlist only supports songs."; return }
        guard !playlist.contains(item) else { dismiss(); return }
        let nextSortOrder = (playlist.entries.map(\.sortOrder).max() ?? -1) + 1
        let entry = PlaylistEntry(sortOrder: nextSortOrder, playlist: playlist, mediaItem: item)
        if playlist.mediaType == .unknown { playlist.setMediaType(.audio) }
        modelContext.insert(entry)
        do {
            playlist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not add this song to the playlist."
        }
    }
}

// MARK: - PlaylistDetailView (logic unchanged, minor row polish)

private struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlaybackController: AudioPlaybackController
    @Query(
        sort: [
            SortDescriptor(\Playlist.createdDate, order: .reverse),
            SortDescriptor(\Playlist.name)
        ]
    ) private var playlists: [Playlist]

    let playlist: Playlist
    let fileStorage: LocalFileStorage

    @State private var errorMessage: String?
    @State private var itemPendingPlaylistSelection: MediaItem?
    @State private var entryPendingRemoval: PlaylistEntry?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name).font(.headline)
                    Text("\(playlist.itemCount) song\(playlist.itemCount == 1 ? "" : "s")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Songs") {
                if sortedEntries.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "music.note")
                            .font(.title2)
                            .foregroundStyle(.quaternary)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                            )
                        Text("Add downloaded songs from the Library to build this playlist.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(sortedEntries) { entry in
                        if let item = entry.mediaItem {
                            playlistSongRow(for: entry, item: item)
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $itemPendingPlaylistSelection) { item in
            AddToPlaylistView(item: item, playlists: compatiblePlaylists(for: item))
        }
        .alert(
            "Remove Song?",
            isPresented: Binding(
                get: { entryPendingRemoval != nil },
                set: { if !$0 { entryPendingRemoval = nil } }
            ),
            presenting: entryPendingRemoval
        ) { entry in
            Button("Remove", role: .destructive) { remove(entry: entry); entryPendingRemoval = nil }
            Button("Cancel", role: .cancel) { entryPendingRemoval = nil }
        } message: { entry in
            Text("\"\(entry.mediaItem?.title ?? "This song")\" will be removed from this playlist.")
        }
    }

    private var sortedEntries: [PlaylistEntry] {
        playlist.sortedEntries.filter { $0.mediaItem?.mediaType == .audio }
    }

    private var playableAudioItems: [MediaItem] {
        sortedEntries.compactMap(\.mediaItem).filter(isPlayableAudioItem)
    }

    private func playlistSongRow(for entry: PlaylistEntry, item: MediaItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                playSong(item)
            } label: {
                MediaItemRow(item: item, fileStorage: fileStorage, style: .song)
            }
            .buttonStyle(.plain)
            .disabled(!isPlayableAudioItem(item))

            Menu {
                Button {
                    itemPendingPlaylistSelection = item
                } label: {
                    Label("Add to Playlist", systemImage: "text.badge.plus")
                }
                Button {
                    queueSongNext(item)
                } label: {
                    Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .disabled(!isPlayableAudioItem(item))
                Button(role: .destructive) {
                    entryPendingRemoval = entry
                } label: {
                    Label("Remove from Playlist", systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .contentShape(Circle())
            }
        }
    }

    // Logic unchanged
    private func remove(entry: PlaylistEntry) {
        let isRemovingLastEntry = sortedEntries.count == 1
        if isRemovingLastEntry { playlist.setMediaType(.unknown) }
        modelContext.delete(entry)
        do {
            playlist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
        } catch {
            errorMessage = "Could not remove item from playlist."
        }
    }

    private func compatiblePlaylists(for item: MediaItem) -> [Playlist] {
        guard item.mediaType == .audio else { return [] }
        return playlists.filter { candidate in
            candidate.id != playlist.id && (candidate.mediaType == .audio || candidate.mediaType == .unknown)
        }
    }

    private func isPlayableAudioItem(_ item: MediaItem) -> Bool {
        guard item.mediaType == .audio, item.downloadStatus == .downloaded else { return false }
        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }

    private func playSong(_ item: MediaItem) {
        guard isPlayableAudioItem(item) else { return }
        audioPlaybackController.configure(item: item, playlist: playableAudioItems, fileStorage: fileStorage)
        audioPlaybackController.play()
    }

    private func queueSongNext(_ item: MediaItem) {
        guard isPlayableAudioItem(item) else { return }
        audioPlaybackController.enqueueNext(item: item, from: playableAudioItems, fileStorage: fileStorage)
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [MediaItem.self, Playlist.self, PlaylistEntry.self], inMemory: true)
}