import SwiftUI
import SwiftData
import OSLog

struct MediaDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MediaDetailViewModel
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "MediaDetailView")

    init(item: ResolvedMediaItem) {
        _viewModel = StateObject(wrappedValue: MediaDetailViewModel(item: item))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let thumbnailURL = viewModel.item.thumbnailURL {
                    // AsyncImage may still emit normal thumbnail-fetch network logs.
                    // Download-flow logs come from MediaDetailViewModel / DownloadOrchestrator / runtime transport.
                    AsyncImage(url: thumbnailURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.secondarySystemBackground))
                            ProgressView()
                        }
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.item.title)
                        .font(.title2.weight(.semibold))

                    if let creatorName = viewModel.item.creatorName, !creatorName.isEmpty {
                        Text(creatorName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Provider", value: viewModel.item.provider)
                    DetailRow(label: "Provider Item ID", value: viewModel.item.providerItemId)
                    DetailRow(label: "Source URL", value: viewModel.item.sourcePageURL.absoluteString)
                    DetailRow(
                        label: "Available Types",
                        value: viewModel.item.availableMediaTypes.map { $0.rawValue.capitalized }.joined(separator: ", ")
                    )

                    if let durationSeconds = viewModel.item.durationSeconds {
                        DetailRow(label: "Duration", value: formattedDuration(durationSeconds))
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                )

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        Task {
                            await viewModel.startAudioDownload()
                        }
                    } label: {
                        Text("Download Audio")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isStartingDownload || !viewModel.item.availableMediaTypes.contains(.audio))

                    Button {
                        Task {
                            await viewModel.startVideoDownload()
                        }
                    } label: {
                        Text("Download Video")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isStartingDownload || !viewModel.item.availableMediaTypes.contains(.video))

                    downloadStateView(
                        title: "Audio Status",
                        state: viewModel.audioState,
                        statusMessage: viewModel.audioStatusMessage,
                        errorMessage: viewModel.audioErrorMessage
                    )
                    downloadStateView(
                        title: "Video Status",
                        state: viewModel.videoState,
                        statusMessage: viewModel.videoStatusMessage,
                        errorMessage: viewModel.videoErrorMessage
                    )

                    if viewModel.isStartingDownload {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Preparing download handoff...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            logger.debug("Composing detail flow with YouTubeBridgeDownloadProvider, MediaFileDownloader, and ApplicationSupportFileStorage")
            viewModel.configureIfNeeded(
                downloadOrchestrator: DownloadOrchestrator(
                    repository: SwiftDataMediaLibraryRepository(modelContext: modelContext),
                    downloadProvider: YouTubeBridgeDownloadProvider(),
                    downloader: MediaFileDownloader(),
                    fileStorage: ApplicationSupportFileStorage()
                )
            )
            await viewModel.refreshStates()
        }
    }

    private func formattedDuration(_ durationSeconds: Double) -> String {
        let totalSeconds = Int(durationSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }

    @ViewBuilder
    private func downloadStateView(
        title: String,
        state: DownloadStateSnapshot?,
        statusMessage: String?,
        errorMessage: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let state {
                Text(statusLabel(for: state))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let progress = state.progress, state.status == .downloading {
                    ProgressView(value: progress)
                }
            } else {
                Text("Not started")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func statusLabel(for state: DownloadStateSnapshot) -> String {
        switch state.status {
        case .notDownloaded:
            return "Not downloaded"
        case .queued:
            return "Queued"
        case .downloading:
            let percentage = Int((state.progress ?? 0) * 100)
            return "Downloading \(percentage)%"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Failed"
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(
            item: ResolvedMediaItem(
                provider: "youtube",
                providerItemId: "dQw4w9WgXcQ",
                title: "Never Gonna Give You Up",
                creatorName: "Rick Astley",
                thumbnailURL: URL(string: "https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg"),
                durationSeconds: 213,
                sourcePageURL: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!,
                availableMediaTypes: [.audio, .video]
            )
        )
    }
    .modelContainer(for: [MediaItem.self], inMemory: true)
}
