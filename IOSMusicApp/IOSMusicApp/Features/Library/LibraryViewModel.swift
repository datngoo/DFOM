import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    enum MediaTypeFilter: String, CaseIterable, Identifiable {
        case all
        case audio
        case video

        var id: String {
            rawValue
        }

        var title: String {
            rawValue.capitalized
        }
    }

    @Published var selectedFilter: MediaTypeFilter = .all

    func filteredItems(from items: [MediaItem]) -> [MediaItem] {
        switch selectedFilter {
        case .all:
            return items
        case .audio:
            return items.filter { $0.mediaType == .audio }
        case .video:
            return items.filter { $0.mediaType == .video }
        }
    }

    func filteredPlaylists(from playlists: [Playlist]) -> [Playlist] {
        switch selectedFilter {
        case .all:
            return playlists
        case .audio:
            return playlists.filter { $0.mediaType == .audio || $0.mediaType == .unknown }
        case .video:
            return playlists.filter { $0.mediaType == .video || $0.mediaType == .unknown }
        }
    }

    func compatiblePlaylists(for item: MediaItem, from playlists: [Playlist]) -> [Playlist] {
        playlists.filter { $0.canAccept(item) }
    }

    var emptyStateTitle: String {
        switch selectedFilter {
        case .all:
            return "No Downloads Yet"
        case .audio:
            return "No Audio Items"
        case .video:
            return "No Video Items"
        }
    }

    var emptyStateDescription: String {
        switch selectedFilter {
        case .all:
            return "Persisted audio, video, and failed items will appear here."
        case .audio:
            return "Downloaded and failed audio items will appear here."
        case .video:
            return "Downloaded and failed video items will appear here."
        }
    }

    var downloadsSectionTitle: String {
        switch selectedFilter {
        case .all:
            return "Downloads"
        case .audio:
            return "Audio Downloads"
        case .video:
            return "Video Downloads"
        }
    }

    var playlistsEmptyStateDescription: String {
        switch selectedFilter {
        case .all:
            return "Create a playlist to organize downloaded audio or video items."
        case .audio:
            return "Audio playlists and empty playlists will appear here."
        case .video:
            return "Video playlists and empty playlists will appear here."
        }
    }
}
