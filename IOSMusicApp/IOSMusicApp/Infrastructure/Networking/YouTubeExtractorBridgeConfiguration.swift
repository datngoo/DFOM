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

    private let bundle: Bundle
    private let environment: [String: String]
    private let bridgeConfig: BridgeConfig
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "YouTubeExtractorBridgeConfiguration")

    init(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bridgeConfig: BridgeConfig = .current
    ) {
        self.bundle = bundle
        self.environment = environment
        self.bridgeConfig = bridgeConfig
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
            mode=\(resolution.mode, privacy: .public) \
            runtime=\(runtimeEnvironmentLabel, privacy: .public)
            """
        )
        #endif

        return url
    }

    private func resolveBridgeBaseURL() -> BridgeBaseURLResolution {
        if let environmentValue = normalizedString(environment[bridgeConfig.environmentOverrideKey]) {
            return BridgeBaseURLResolution(
                rawValue: environmentValue,
                source: "environment",
                mode: "override"
            )
        }

        if let configuredRemoteBaseURL = bridgeConfig.remoteBaseURL {
            return BridgeBaseURLResolution(
                rawValue: configuredRemoteBaseURL,
                source: "bridge-config-remote-base-url",
                mode: "remote"
            )
        }

        if let configuredBaseURL = normalizedString(
            bundle.object(forInfoDictionaryKey: bridgeConfig.legacyInfoDictionaryKey) as? String
        ) {
            return BridgeBaseURLResolution(
                rawValue: configuredBaseURL,
                source: "info-plist-base-url",
                mode: "override"
            )
        }

        if let debugDeviceBaseURL = debugDeviceBaseURL() {
            return BridgeBaseURLResolution(
                rawValue: debugDeviceBaseURL,
                source: "debug-device-host-port",
                mode: "local"
            )
        }

        if let simulatorFallbackBaseURL = debugSimulatorFallbackBaseURL() {
            return BridgeBaseURLResolution(
                rawValue: simulatorFallbackBaseURL,
                source: "debug-simulator-fallback",
                mode: "local"
            )
        }

        return BridgeBaseURLResolution(
            rawValue: nil,
            source: "missing",
            mode: "missing"
        )
    }

    private func debugDeviceBaseURL() -> String? {
        #if DEBUG
        #if !targetEnvironment(simulator)
        guard let host = normalizedString(
            bundle.object(forInfoDictionaryKey: bridgeConfig.debugDeviceHostInfoDictionaryKey) as? String
        ) else {
            return nil
        }

        let port = normalizedPort(bundle.object(forInfoDictionaryKey: bridgeConfig.debugPortInfoDictionaryKey))
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
        return "http://127.0.0.1:\(bridgeConfig.defaultDebugPort)"
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

        return bridgeConfig.defaultDebugPort
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
    let mode: String
}
