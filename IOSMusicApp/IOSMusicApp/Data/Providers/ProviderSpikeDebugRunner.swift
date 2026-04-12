#if DEBUG
import Foundation
import OSLog

enum ProviderSpikeDebugRunner {
    private static let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "ProviderSpike")
    private static let kan7Argument = "--kan7-provider-spike-debug"
    private static let kan9Argument = "--kan9-provider-debug"

    static var isEnabledForCurrentLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(kan7Argument) || arguments.contains(kan9Argument)
    }

    static func runOnLaunchIfEnabled() {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains(kan7Argument) {
            Task {
                await runSpikeSample()
            }

            return
        }

        guard arguments.contains(kan9Argument) else {
            return
        }

        Task {
            await runConcreteProviderChecks()
        }
    }

    static func runSpikeSample() async {
        let provider = YouTubeProviderSpike()
        let sampleURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!

        do {
            let item = try await provider.resolve(url: sampleURL)
            let audioDescriptor = try await provider.resolveDownload(for: item, mediaType: .audio)
            let videoDescriptor = try await provider.resolveDownload(for: item, mediaType: .video)

            logger.debug("KAN-7 sample resolved item id: \(item.providerItemId, privacy: .public)")
            logger.debug("KAN-7 sample audio URL: \(audioDescriptor.remoteURL.absoluteString, privacy: .public)")
            logger.debug("KAN-7 sample video URL: \(videoDescriptor.remoteURL.absoluteString, privacy: .public)")
        } catch {
            logger.error("KAN-7 provider spike debug failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func runConcreteProviderChecks() async {
        let provider = YouTubeURLResolutionProvider()
        let validURL = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let invalidURL = URL(string: "https://vimeo.com/12345")!

        do {
            let item = try await provider.resolve(url: validURL)
            logger.debug("KAN-9 resolved title: \(item.title, privacy: .public)")
            logger.debug("KAN-9 resolved creator: \(item.creatorName ?? "unknown", privacy: .public)")
        } catch {
            logger.error("KAN-9 valid URL resolution failed: \(String(describing: error), privacy: .public)")
        }

        do {
            _ = try await provider.resolve(url: invalidURL)
            logger.error("KAN-9 unsupported URL unexpectedly resolved")
        } catch let error as ProviderError {
            logger.debug("KAN-9 unsupported URL failed cleanly with: \(String(describing: error), privacy: .public)")
        } catch {
            logger.error("KAN-9 unsupported URL failed with unexpected error: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
