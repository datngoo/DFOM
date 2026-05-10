import Foundation

struct BridgeConfig {
    static let current = BridgeConfig()

    // Set this to your deployed bridge server when you want the app to use remote resolution.
    // Leave it empty to keep the current local bridge fallback behavior.
    private static let configuredRemoteBaseURL = ""

    let remoteBaseURL: String?
    let environmentOverrideKey: String
    let legacyInfoDictionaryKey: String
    let debugDeviceHostInfoDictionaryKey: String
    let debugPortInfoDictionaryKey: String
    let defaultDebugPort: Int

    init(
        remoteBaseURL: String? = BridgeConfig.configuredRemoteBaseURL,
        environmentOverrideKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL",
        legacyInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL",
        debugDeviceHostInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST",
        debugPortInfoDictionaryKey: String = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT",
        defaultDebugPort: Int = 8080
    ) {
        self.remoteBaseURL = Self.normalizedString(remoteBaseURL)
        self.environmentOverrideKey = environmentOverrideKey
        self.legacyInfoDictionaryKey = legacyInfoDictionaryKey
        self.debugDeviceHostInfoDictionaryKey = debugDeviceHostInfoDictionaryKey
        self.debugPortInfoDictionaryKey = debugPortInfoDictionaryKey
        self.defaultDebugPort = defaultDebugPort
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
