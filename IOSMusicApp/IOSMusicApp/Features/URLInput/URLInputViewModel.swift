import Foundation

@MainActor
final class URLInputViewModel: ObservableObject {
    @Published var urlText = ""
    @Published var isLoading = false
    @Published var validationMessage: String?
    @Published var errorMessage: String?
    @Published var resolvedItem: ResolvedMediaItem?

    private let provider: any URLResolutionProvider

    init(
        provider: any URLResolutionProvider,
        urlText: String = ""
    ) {
        self.provider = provider
        self.urlText = urlText
    }

    func clearMessages() {
        validationMessage = nil
        errorMessage = nil
    }

    func clearResolvedItem() {
        resolvedItem = nil
    }

    func resolve() async {
        let trimmedText = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        urlText = trimmedText
        clearMessages()
        resolvedItem = nil

        guard !trimmedText.isEmpty else {
            validationMessage = "Paste or type a YouTube video URL to continue."
            return
        }

        guard let url = URL(string: trimmedText), url.scheme != nil, url.host != nil else {
            validationMessage = "Enter a valid URL, such as https://www.youtube.com/watch?v=..."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            resolvedItem = try await provider.resolve(url: url)
        } catch let error as ProviderError {
            switch error {
            case .invalidURL:
                validationMessage = "That link does not look like a valid YouTube video URL."
            case .unsupportedURL:
                validationMessage = "This screen currently supports direct YouTube video URLs only."
            case .metadataFetchFailed:
                errorMessage = "We could not read media details from that URL right now."
            case .mappingFailed:
                errorMessage = "We found the media but could not map it into the app yet."
            case .downloadResolutionFailed(let message):
                errorMessage = message ?? "The provider reported a download resolution failure."
            case .unsupportedMediaType:
                errorMessage = "The resolved media type is not supported."
            case .notImplementedInSpike:
                errorMessage = "This provider path is still a spike and is not fully implemented."
            }
        } catch {
            errorMessage = "Something went wrong while resolving the URL. Please try again."
        }
    }
}
