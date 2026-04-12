import SwiftUI
import SwiftData
import UIKit
import OSLog

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\MediaItem.downloadedDate, order: .reverse),
            SortDescriptor(\MediaItem.createdDate, order: .reverse)
        ]
    ) private var mediaItems: [MediaItem]
    @StateObject private var viewModel: LibraryViewModel
    private let fileStorage: LocalFileStorage
    private let logger = Logger(subsystem: "IOSMusicApp", category: "LibraryView")

    init(fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        self.fileStorage = fileStorage
        _viewModel = StateObject(wrappedValue: LibraryViewModel())
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedMediaItems.isEmpty {
                    ContentUnavailableView(
                        viewModel.emptyStateTitle,
                        systemImage: "music.note.list",
                        description: Text(viewModel.emptyStateDescription)
                    )
                } else {
                    List {
                        ForEach(displayedMediaItems) { item in
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
                        .onDelete(perform: deleteItems)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .safeAreaInset(edge: .top) {
                filterPicker
            }
            .navigationTitle("Library")
            .task {
                await migratePersistedManagedPathsIfNeeded()
            }
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for offset in offsets {
            let item = displayedMediaItems[offset]

            do {
                try fileStorage.deleteStoredFiles(for: item.id)
            } catch {
                logger.error("Failed to delete stored files for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            }

            modelContext.delete(item)
        }

        do {
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
        .disabled(mediaItems.isEmpty)
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

#Preview {
    LibraryView()
        .modelContainer(for: [MediaItem.self], inMemory: true)
}
