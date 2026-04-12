import Foundation

enum StoredMediaKind: String, CaseIterable {
    case audio
    case video

    var fileNameStem: String {
        rawValue
    }
}
