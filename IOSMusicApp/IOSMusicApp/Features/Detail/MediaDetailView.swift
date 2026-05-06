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
                thumbnailHeader
                metadataCard
                downloadSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Detail")
        .navigationBarTitleDisplayMode(.inline)
        // ↓ UNCHANGED — do not touch
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

    // MARK: - Thumbnail + title header

    private var thumbnailHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let thumbnailURL = viewModel.item.thumbnailURL {
                // AsyncImage comment preserved from original — download-flow logs come from ViewModel
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        thumbnailPlaceholder
                    default:
                        ZStack {
                            thumbnailPlaceholder
                            ProgressView().tint(.secondary)
                        }
                    }
                }
                .frame(height: 210)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.item.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if let creatorName = viewModel.item.creatorName, !creatorName.isEmpty {
                    Text(creatorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.secondarySystemFill), Color(.tertiarySystemFill)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Metadata card

    private var metadataCard: some View {
        VStack(spacing: 0) {
            metaRow(label: "Provider", value: viewModel.item.provider.capitalized)
            Divider().padding(.leading, 16)
            metaRow(label: "Item ID", value: viewModel.item.providerItemId)
            Divider().padding(.leading, 16)
            metaRow(
                label: "Available",
                value: viewModel.item.availableMediaTypes.map { $0.rawValue.capitalized }.joined(separator: ", ")
            )
            if let duration = viewModel.item.durationSeconds {
                Divider().padding(.leading, 16)
                metaRow(label: "Duration", value: formattedDuration(duration))
            }
            Divider().padding(.leading, 16)
            metaRow(label: "Source", value: viewModel.item.sourcePageURL.absoluteString)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Download section

    private var downloadSection: some View {
        VStack(spacing: 12) {
            // Audio button
            Button {
                Task { await viewModel.startAudioDownload() }
            } label: {
                Label("Download Audio", systemImage: "music.note")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isStartingDownload || !viewModel.item.availableMediaTypes.contains(.audio))

            // Video button
            Button {
                Task { await viewModel.startVideoDownload() }
            } label: {
                Label("Download Video", systemImage: "film")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isStartingDownload || !viewModel.item.availableMediaTypes.contains(.video))

            // Global spinner while handoff is in progress
            if viewModel.isStartingDownload {
                HStack(spacing: 10) {
                    ProgressView().tint(.accentColor)
                    Text("Preparing download…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .transition(.opacity)
            }

            // Status cards
            downloadStateCard(
                mediaType: "Audio",
                icon: "music.note",
                state: viewModel.audioState,
                statusMessage: viewModel.audioStatusMessage,
                errorMessage: viewModel.audioErrorMessage
            )

            downloadStateCard(
                mediaType: "Video",
                icon: "film",
                state: viewModel.videoState,
                statusMessage: viewModel.videoStatusMessage,
                errorMessage: viewModel.videoErrorMessage
            )
        }
    }

    // MARK: - Download state card

    @ViewBuilder
    private func downloadStateCard(
        mediaType: String,
        icon: String,
        state: DownloadStateSnapshot?,
        statusMessage: String?,
        errorMessage: String?
    ) -> some View {
        let hasContent = state != nil || statusMessage != nil || errorMessage != nil
        if hasContent {
            VStack(alignment: .leading, spacing: 10) {
                // Title row
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(mediaType) Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.3)
                    Spacer()
                    if let state {
                        statusBadge(for: state)
                    }
                }

                // Progress bar (downloading only)
                if let state, let progress = state.progress, state.status == .downloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.accentColor)
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Status message
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Error message
                if let errorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        errorMessage != nil
                            ? Color.red.opacity(0.2)
                            : Color(.separator).opacity(0.18),
                        lineWidth: 0.5
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: state?.status)
        }
    }

    @ViewBuilder
    private func statusBadge(for state: DownloadStateSnapshot) -> some View {
        let (label, color) = statusBadgeInfo(for: state)
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.1)))
    }

    private func statusBadgeInfo(for state: DownloadStateSnapshot) -> (String, Color) {
        switch state.status {
        case .notDownloaded: return ("Not started", Color(.tertiaryLabel))
        case .queued:        return ("Queued", .orange)
        case .downloading:   return ("Downloading", .blue)
        case .downloaded:    return ("Done", .green)
        case .failed:        return ("Failed", .red)
        }
    }

    // MARK: - Helpers (unchanged logic)

    private func formattedDuration(_ durationSeconds: Double) -> String {
        let totalSeconds = Int(durationSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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
    .modelContainer(for: [MediaItem.self, Playlist.self, PlaylistEntry.self], inMemory: true)
}