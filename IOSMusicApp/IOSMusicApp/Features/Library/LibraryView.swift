import SwiftUI
import SwiftData
import UIKit
import OSLog

struct LibraryView: View {
    private enum Layout {
        static let screenPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 12
        static let smallSpacing: CGFloat = 8
        static let cardCornerRadius: CGFloat = 16
        static let cardPadding: CGFloat = 14
    }

    @Environment(\.modelContext) private var modelContext
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
    private let fileStorage: LocalFileStorage
    private let logger = Logger(subsystem: "IOSMusicApp", category: "LibraryView")

    init(fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        self.fileStorage = fileStorage
        _viewModel = StateObject(wrappedValue: LibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            List {
                playlistsSection

                Section(viewModel.downloadsSectionTitle) {
                    if displayedMediaItems.isEmpty {
                        Text(displayedPlaylists.isEmpty ? viewModel.emptyStateTitle : viewModel.emptyStateDescription)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayedMediaItems) { item in
                            if isPlayableAudioItem(item) {
                                NavigationLink {
                                    LibraryMediaDetailView(
                                        item: item,
                                        audioPlaylist: playableAudioItems,
                                        fileStorage: fileStorage
                                    )
                                } label: {
                                    libraryRow(for: item)
                                }
                            } else if isPlayableVideoItem(item) {
                                NavigationLink {
                                    LibraryMediaDetailView(item: item, fileStorage: fileStorage)
                                } label: {
                                    libraryRow(for: item)
                                }
                            } else {
                                NavigationLink {
                                    LibraryMediaDetailView(item: item, fileStorage: fileStorage)
                                } label: {
                                    libraryRow(for: item)
                                }
                            }
                        }
                        .onDelete(perform: deleteItems)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top) {
                filterPicker
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatePlaylistPresented = true
                    } label: {
                        Label("Create Playlist", systemImage: "plus")
                    }
                }
            }
            .task {
                await migratePersistedManagedPathsIfNeeded()
            }
            .sheet(isPresented: $isCreatePlaylistPresented) {
                CreatePlaylistView()
            }
            .sheet(item: $itemPendingPlaylistSelection) { item in
                AddToPlaylistView(
                    item: item,
                    playlists: compatiblePlaylists(for: item)
                )
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        var playlistsToReset: [UUID: Playlist] = [:]

        for offset in offsets {
            let item = displayedMediaItems[offset]
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

        guard hasChanges else {
            return
        }

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

    private var displayedMediaItems: [MediaItem] {
        viewModel.filteredItems(from: mediaItems)
    }

    private var displayedPlaylists: [Playlist] {
        viewModel.filteredPlaylists(from: playlists)
    }

    private var playableAudioItems: [MediaItem] {
        mediaItems.filter(isPlayableAudioItem)
    }

    private var filterPicker: some View {
        Picker("Media Type", selection: $viewModel.selectedFilter) {
            ForEach(LibraryViewModel.MediaTypeFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .disabled(mediaItems.isEmpty && playlists.isEmpty)
    }

    private func isPlayableAudioItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .audio)
    }

    private func isPlayableVideoItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .video)
    }

    private func isPlayableLibraryItem(_ item: MediaItem, expectedMediaType: MediaType) -> Bool {
        guard item.mediaType == expectedMediaType,
              item.downloadStatus == .downloaded else {
            return false
        }

        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }

    private func canAddToPlaylist(_ item: MediaItem) -> Bool {
        isPlayableAudioItem(item) || isPlayableVideoItem(item)
    }

    private func compatiblePlaylists(for item: MediaItem) -> [Playlist] {
        viewModel.compatiblePlaylists(for: item, from: playlists)
    }

    private var playlistsSection: some View {
        Section("Playlists") {
            Button {
                isCreatePlaylistPresented = true
            } label: {
                Label("Create New Playlist", systemImage: "plus.circle")
            }

            if displayedPlaylists.isEmpty {
                Text(viewModel.playlistsEmptyStateDescription)
                    .foregroundStyle(.secondary)
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

    private func libraryRow(for item: MediaItem) -> some View {
        MediaItemRow(item: item, fileStorage: fileStorage)
    }
}

private struct MediaItemRow: View {
    let item: MediaItem
    let fileStorage: LocalFileStorage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            artworkView

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.headline)

                Text(item.creatorName ?? "Unknown creator")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(item.mediaType.rawValue.capitalized) • \(statusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let localFilePath = item.localFilePath, !localFilePath.isEmpty {
                    Text(localFilePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let thumbnailImage {
            Image(uiImage: thumbnailImage)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let remoteThumbnailURL = preferredRemoteThumbnailURL {
            AsyncImage(url: remoteThumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderArtwork
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
        guard item.mediaType == .video else {
            return nil
        }

        return item.thumbnailRemoteURL
    }

    private var statusLabel: String {
        if item.downloadStatus == .downloaded,
           item.localFilePath != nil,
           (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) == nil {
            return "Unavailable"
        }

        switch item.downloadStatus {
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .notDownloaded:
            return "Not Downloaded"
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.secondarySystemBackground))
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: item.mediaType == .video ? "film" : "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}

private struct LibraryMediaDetailView: View {
    private enum Layout {
        static let screenPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 10
        static let cardPadding: CGFloat = 14
        static let cardCornerRadius: CGFloat = 16
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
                MediaItemRow(item: item, fileStorage: fileStorage)

                VStack(alignment: .leading, spacing: Layout.itemSpacing) {
                    if isPlayableAudioItem(item) {
                        NavigationLink {
                            AudioPlayerView(
                                item: item,
                                playlist: audioPlaylist,
                                fileStorage: fileStorage
                            )
                        } label: {
                            Text("Play")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    } else if isPlayableVideoItem(item) {
                        NavigationLink {
                            VideoPlayerView(item: item, fileStorage: fileStorage)
                        } label: {
                            Text("Play")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    if canAddToPlaylist(item) {
                        Button {
                            isPlaylistPickerPresented = true
                        } label: {
                            Text("Add to Playlist")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }

                VStack(alignment: .leading, spacing: Layout.itemSpacing) {
                    DetailValueRow(label: "Creator", value: item.creatorName ?? "Unknown creator")
                    DetailValueRow(label: "Type", value: item.mediaType.rawValue.capitalized)
                    DetailValueRow(label: "Status", value: statusLabel)

                    if let localFilePath = item.localFilePath, !localFilePath.isEmpty {
                        DetailValueRow(label: "Local Path", value: localFilePath)
                    }
                }
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color(.secondarySystemBackground))
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

    private func compatiblePlaylists(for item: MediaItem) -> [Playlist] {
        playlists.filter { $0.canAccept(item) }
    }

    private func canAddToPlaylist(_ item: MediaItem) -> Bool {
        isPlayableAudioItem(item) || isPlayableVideoItem(item)
    }

    private func isPlayableAudioItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .audio)
    }

    private func isPlayableVideoItem(_ item: MediaItem) -> Bool {
        isPlayableLibraryItem(item, expectedMediaType: .video)
    }

    private func isPlayableLibraryItem(_ item: MediaItem, expectedMediaType: MediaType) -> Bool {
        guard item.mediaType == expectedMediaType,
              item.downloadStatus == .downloaded else {
            return false
        }

        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }

    private var statusLabel: String {
        if item.downloadStatus == .downloaded,
           item.localFilePath != nil,
           (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) == nil {
            return "Unavailable"
        }

        switch item.downloadStatus {
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Failed"
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .notDownloaded:
            return "Not Downloaded"
        }
    }
}

private struct DetailValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: playlist.mediaType == .video ? "film.stack" : "music.note.list")
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)

                Text("\(playlistTypeLabel) • \(playlist.itemCount) item\(playlist.itemCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var playlistTypeLabel: String {
        switch playlist.mediaType {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .unknown:
            return "Empty"
        }
    }
}

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
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createPlaylist()
                    }
                    .disabled(playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func createPlaylist() {
        let trimmedName = playlistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Playlist name is required."
            return
        }

        let playlist = Playlist(name: trimmedName)
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
                Section("Downloaded Item") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)

                        Text(item.mediaType.rawValue.capitalized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Compatible Playlists") {
                    if playlists.isEmpty {
                        Text("No compatible playlists yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playlists) { playlist in
                            Button {
                                addItem(to: playlist)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(playlist.name)
                                            .foregroundStyle(.primary)

                                        Text("\(playlistTypeLabel(for: playlist)) • \(playlist.itemCount) item\(playlist.itemCount == 1 ? "" : "s")")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    if playlist.contains(item) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(playlist.contains(item))
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create New") {
                        isCreatePlaylistPresented = true
                    }
                }
            }
            .sheet(isPresented: $isCreatePlaylistPresented) {
                CreatePlaylistView { playlist in
                    addItem(to: playlist)
                }
            }
        }
    }

    private func addItem(to playlist: Playlist) {
        guard playlist.canAccept(item) else {
            errorMessage = "This playlist only supports \(playlist.mediaType.rawValue) items."
            return
        }

        guard !playlist.contains(item) else {
            dismiss()
            return
        }

        let nextSortOrder = (playlist.entries.map(\.sortOrder).max() ?? -1) + 1
        let entry = PlaylistEntry(sortOrder: nextSortOrder, playlist: playlist, mediaItem: item)

        if playlist.mediaType == .unknown {
            playlist.setMediaType(item.mediaType)
        }

        modelContext.insert(entry)

        do {
            playlist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Could not add this item to the playlist."
        }
    }

    private func playlistTypeLabel(for playlist: Playlist) -> String {
        switch playlist.mediaType {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .unknown:
            return "Empty"
        }
    }
}

private struct PlaylistDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let playlist: Playlist
    let fileStorage: LocalFileStorage

    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.headline)

                    Text("\(playlistTypeLabel) • \(playlist.itemCount) item\(playlist.itemCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Items") {
                if sortedEntries.isEmpty {
                    Text("Add downloaded \(playlistItemTypeLabel) items from the Library to build this playlist.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedEntries) { entry in
                        if let item = entry.mediaItem {
                            if isPlayableAudioItem(item) {
                                NavigationLink {
                                    AudioPlayerView(
                                        item: item,
                                        playlist: playableAudioItems,
                                        fileStorage: fileStorage
                                    )
                                } label: {
                                    MediaItemRow(item: item, fileStorage: fileStorage)
                                }
                            } else if isPlayableVideoItem(item) {
                                NavigationLink {
                                    VideoPlayerView(item: item, fileStorage: fileStorage)
                                } label: {
                                    MediaItemRow(item: item, fileStorage: fileStorage)
                                }
                            } else {
                                MediaItemRow(item: item, fileStorage: fileStorage)
                            }
                        }
                    }
                    .onDelete(perform: removeItems)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sortedEntries: [PlaylistEntry] {
        playlist.sortedEntries.filter { $0.mediaItem != nil }
    }

    private var playableAudioItems: [MediaItem] {
        sortedEntries.compactMap(\.mediaItem).filter(isPlayableAudioItem)
    }

    private var playlistTypeLabel: String {
        switch playlist.mediaType {
        case .audio:
            return "Audio"
        case .video:
            return "Video"
        case .unknown:
            return "Empty"
        }
    }

    private var playlistItemTypeLabel: String {
        switch playlist.mediaType {
        case .audio:
            return "audio"
        case .video:
            return "video"
        case .unknown:
            return "audio or video"
        }
    }

    private func removeItems(at offsets: IndexSet) {
        let entriesToDelete = offsets.compactMap { index in
            sortedEntries.indices.contains(index) ? sortedEntries[index] : nil
        }

        if entriesToDelete.count == sortedEntries.count {
            playlist.setMediaType(.unknown)
        }

        for entry in entriesToDelete {
            modelContext.delete(entry)
        }

        do {
            playlist.syncMediaTypeRawValueIfNeeded()
            try modelContext.save()
        } catch {
            errorMessage = "Could not remove item from playlist."
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
              item.downloadStatus == .downloaded else {
            return false
        }

        return (try? fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)) != nil
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [MediaItem.self, Playlist.self, PlaylistEntry.self], inMemory: true)
}
