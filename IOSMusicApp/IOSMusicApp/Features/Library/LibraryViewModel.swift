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
}
