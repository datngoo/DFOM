import Foundation

@MainActor
final class LibraryViewModel: ObservableObject {
    enum LibraryTab: String, CaseIterable, Identifiable {
        case songs
        case playlists
        case videos

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .songs:
                return "Songs"
            case .playlists:
                return "Playlists"
            case .videos:
                return "Videos"
            }
        }
    }

    @Published var selectedTab: LibraryTab = .songs

    func filteredItems(from items: [MediaItem]) -> [MediaItem] {
        switch selectedTab {
        case .songs:
            return items.filter { $0.mediaType == .audio }
        case .videos:
            return items.filter { $0.mediaType == .video }
        case .playlists:
            return []
        }
    }

    func filteredPlaylists(from playlists: [Playlist]) -> [Playlist] {
        switch selectedTab {
        case .playlists:
            return playlists.filter { $0.mediaType == .audio || $0.mediaType == .unknown }
        case .songs, .videos:
            return []
        }
    }

    func compatiblePlaylists(for item: MediaItem, from playlists: [Playlist]) -> [Playlist] {
        guard item.mediaType == .audio else {
            return []
        }

        return playlists.filter { $0.canAccept(item) }
    }

    var emptyStateTitle: String {
        switch selectedTab {
        case .songs:
            return "No Songs Yet"
        case .playlists:
            return "No Playlists Yet"
        case .videos:
            return "No Videos Yet"
        }
    }

    var emptyStateDescription: String {
        switch selectedTab {
        case .songs:
            return "Downloaded and failed audio items will appear here."
        case .playlists:
            return "Create playlists to organize downloaded songs."
        case .videos:
            return "Downloaded and failed video items will appear here."
        }
    }

    var sectionTitle: String {
        switch selectedTab {
        case .songs:
            return "Songs"
        case .playlists:
            return "Playlists"
        case .videos:
            return "Videos"
        }
    }
}
