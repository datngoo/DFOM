import Foundation

enum BridgeAPIStyle {
    case legacyResolveDownload
    case stableResolve
}

struct BridgeConfig {
    static let current = BridgeConfig()

    // Set this to your deployed bridge server when you want the app to use remote resolution.
    // Leave it empty to keep the current local bridge fallback behavior.
    private static let configuredRemoteBaseURL = "https://zone-exile-rework.ngrok-free.dev"

    let remoteBaseURL: String?
    let environmentOverrideKey: String
    let legacyInfoDictionaryKey: String
    let debugDeviceHostInfoDictionaryKey: String
    let debugPortInfoDictionaryKey: String
    let defaultDebugPort: Int
    let resolveRequestTimeout: TimeInterval
    let healthRequestTimeout: TimeInterval
    let downloadRequestTimeout: TimeInterval
    let downloadResourceTimeout: TimeInterval
    let resolveRetryDelay: TimeInterval
    let maxResolveRetries: Int

    init(
        remoteBaseURL: String? = BridgeConfig.configuredRemoteBaseURL,
        environmentOverrideKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL",
        legacyInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL",
        debugDeviceHostInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST",
        debugPortInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT",
        defaultDebugPort: Int = 8080,
        resolveRequestTimeout: TimeInterval = 20,
        healthRequestTimeout: TimeInterval = 8,
        downloadRequestTimeout: TimeInterval = 60,
        downloadResourceTimeout: TimeInterval = 900,
        resolveRetryDelay: TimeInterval = 1,
        maxResolveRetries: Int = 1
    ) {
        self.remoteBaseURL = Self.normalizedString(remoteBaseURL)
        self.environmentOverrideKey = environmentOverrideKey
        self.legacyInfoDictionaryKey = legacyInfoDictionaryKey
        self.debugDeviceHostInfoDictionaryKey = debugDeviceHostInfoDictionaryKey
        self.debugPortInfoDictionaryKey = debugPortInfoDictionaryKey
        self.defaultDebugPort = defaultDebugPort
        self.resolveRequestTimeout = resolveRequestTimeout
        self.healthRequestTimeout = healthRequestTimeout
        self.downloadRequestTimeout = downloadRequestTimeout
        self.downloadResourceTimeout = downloadResourceTimeout
        self.resolveRetryDelay = resolveRetryDelay
        self.maxResolveRetries = maxResolveRetries
    }

    var apiStyle: BridgeAPIStyle {
        remoteBaseURL == nil ? .legacyResolveDownload : .stableResolve
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
