import Foundation
import OSLog

protocol YouTubeExtractorBridgeConfiguring {
    func bridgeBaseURL() throws -> URL
}

struct YouTubeExtractorBridgeConfiguration: YouTubeExtractorBridgeConfiguring {
    enum ConfigurationError: Error, Equatable, LocalizedError {
        case missingBaseURL
        case invalidBaseURL(String)

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "The YouTube extractor bridge base URL is not configured in this build."
            case .invalidBaseURL(let value):
                return "The YouTube extractor bridge base URL is invalid: \(value)"
            }
        }
    }

    static let infoDictionaryKey = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL"
    static let environmentOverrideKey = "YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL"
    static let debugDeviceHostInfoDictionaryKey = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST"
    static let debugPortInfoDictionaryKey = "YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_PORT"
    static let defaultDebugPort = 8080
    static let defaultDebugDeviceHost = "192.168.100.162"

    private let bundle: Bundle
    private let processInfo: ProcessInfo
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeExtractorBridgeConfiguration")

    init(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.bundle = bundle
        self.processInfo = processInfo
    }

    func bridgeBaseURL() throws -> URL {
        let resolution = resolveBridgeBaseURL()

        guard let rawValue = resolution.rawValue else {
            throw ConfigurationError.missingBaseURL
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            throw ConfigurationError.missingBaseURL
        }

        guard let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw ConfigurationError.invalidBaseURL(trimmedValue)
        }

        #if DEBUG
        logger.debug(
            """
            Resolved YouTube extractor bridge base URL: \(url.absoluteString, privacy: .public) \
            source=\(resolution.source, privacy: .public) \
            runtime=\(runtimeEnvironmentLabel, privacy: .public)
            """
        )
        #endif

        return url
    }

    private func resolveBridgeBaseURL() -> BridgeBaseURLResolution {
        if let environmentValue = normalizedString(processInfo.environment[Self.environmentOverrideKey]) {
            return BridgeBaseURLResolution(
                rawValue: environmentValue,
                source: "environment"
            )
        }

        if let configuredBaseURL = normalizedString(bundle.object(forInfoDictionaryKey: Self.infoDictionaryKey) as? String) {
            return BridgeBaseURLResolution(
                rawValue: configuredBaseURL,
                source: "info-plist-base-url"
            )
        }

        if let debugDeviceBaseURL = debugDeviceBaseURL() {
            return BridgeBaseURLResolution(
                rawValue: debugDeviceBaseURL,
                source: "debug-device-host-port"
            )
        }

        if let simulatorFallbackBaseURL = debugSimulatorFallbackBaseURL() {
            return BridgeBaseURLResolution(
                rawValue: simulatorFallbackBaseURL,
                source: "debug-simulator-fallback"
            )
        }

        return BridgeBaseURLResolution(
            rawValue: nil,
            source: "missing"
        )
    }

    private func debugDeviceBaseURL() -> String? {
        #if DEBUG
        #if !targetEnvironment(simulator)
        let host = normalizedString(bundle.object(forInfoDictionaryKey: Self.debugDeviceHostInfoDictionaryKey) as? String)
            ?? Self.defaultDebugDeviceHost
        let port = normalizedPort(bundle.object(forInfoDictionaryKey: Self.debugPortInfoDictionaryKey))
        return "http://\(host):\(port)"
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    private func debugSimulatorFallbackBaseURL() -> String? {
        #if DEBUG
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:\(Self.defaultDebugPort)"
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedPort(_ value: Any?) -> Int {
        if let number = value as? NSNumber {
            let port = number.intValue
            if port > 0 {
                return port
            }
        }

        if let string = value as? String,
           let port = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           port > 0 {
            return port
        }

        return Self.defaultDebugPort
    }

    private var runtimeEnvironmentLabel: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "physical-device"
        #endif
    }
}

private struct BridgeBaseURLResolution {
    let rawValue: String?
    let source: String
}
