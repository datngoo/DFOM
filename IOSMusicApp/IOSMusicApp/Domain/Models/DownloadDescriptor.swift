import Foundation

struct DownloadDescriptor: Equatable, Sendable {
    let remoteURL: URL
    let mediaType: MediaType
    let suggestedFileExtension: String?
    let mimeType: String?
    let provider: String
    let providerItemId: String

    var resolvedFileFormat: ManagedMediaFileFormat {
        ManagedMediaFileFormat.resolve(
            mediaType: mediaType,
            suggestedFileExtension: suggestedFileExtension,
            mimeType: mimeType
        )
    }
}

enum ManagedMediaFileFormat: String, CaseIterable, Sendable {
    case m4a
    case mp3
    case mp4
    case bin

    var fileExtension: String {
        rawValue
    }

    var mimeType: String {
        switch self {
        case .m4a:
            return "audio/mp4"
        case .mp3:
            return "audio/mpeg"
        case .mp4:
            return "video/mp4"
        case .bin:
            return "application/octet-stream"
        }
    }

    static func resolve(
        mediaType: MediaType,
        suggestedFileExtension: String?,
        mimeType: String?
    ) -> ManagedMediaFileFormat {
        if let normalizedExtension = normalize(fileExtension: suggestedFileExtension),
           let format = allCases.first(where: { $0.fileExtension == normalizedExtension }) {
            return format
        }

        if let normalizedMimeType = normalize(mimeType: mimeType),
           let format = allCases.first(where: { $0.mimeType == normalizedMimeType }) {
            return format
        }

        return defaultFormat(for: mediaType)
    }

    static func defaultFormat(for mediaType: MediaType) -> ManagedMediaFileFormat {
        switch mediaType {
        case .audio:
            return .m4a
        case .video:
            return .mp4
        case .unknown:
            return .bin
        }
    }

    private static func normalize(fileExtension: String?) -> String? {
        guard let fileExtension else {
            return nil
        }

        let trimmedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExtension.isEmpty else {
            return nil
        }

        return trimmedExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private static func normalize(mimeType: String?) -> String? {
        guard let mimeType else {
            return nil
        }

        let trimmedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMimeType.isEmpty else {
            return nil
        }

        return trimmedMimeType.lowercased()
    }
}
