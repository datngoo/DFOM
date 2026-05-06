import SwiftUI
import UIKit

struct URLInputView: View {
    @StateObject private var viewModel: URLInputViewModel
    @State private var navigationPath: [ResolvedMediaItem] = []

    init(provider: any URLResolutionProvider = YouTubeURLResolutionProvider()) {
        _viewModel = StateObject(
            wrappedValue: URLInputViewModel(provider: provider)
        )
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    inputSection
                    feedbackSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Input")
            .navigationDestination(for: ResolvedMediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .onChange(of: viewModel.resolvedItem) { _, item in
                guard let item else { return }
                navigationPath = [item]
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Resolve Media URL")
                .font(.title2.weight(.bold))

            Text("Paste a YouTube video link to resolve provider metadata.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Input card

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Text field
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "link")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                TextField(
                    "https://www.youtube.com/watch?v=...",
                    text: $viewModel.urlText,
                    axis: .vertical
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .font(.subheadline)
                .onSubmit {
                    Task { await viewModel.resolve() }
                }

                if !viewModel.urlText.isEmpty {
                    Button {
                        viewModel.urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear URL")
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .animation(.easeInOut(duration: 0.15), value: viewModel.urlText.isEmpty)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        viewModel.validationMessage != nil
                            ? Color.orange.opacity(0.5)
                            : Color(.separator).opacity(0.25),
                        lineWidth: 1
                    )
            )

            // Action buttons
            HStack(spacing: 10) {
                Button {
                    pasteURL()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.medium))
                        .frame(height: 40)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)

                Button {
                    Task { await viewModel.resolve() }
                } label: {
                    Group {
                        if viewModel.isLoading {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Resolving...")
                            }
                        } else {
                            Label("Resolve URL", systemImage: "magnifyingglass")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading)
            }
        }
    }

    // MARK: - Feedback area

    @ViewBuilder
    private var feedbackSection: some View {
        if let validationMessage = viewModel.validationMessage {
            MessageCard(
                icon: "exclamationmark.triangle.fill",
                title: "Check The URL",
                message: validationMessage,
                tint: .orange
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let errorMessage = viewModel.errorMessage {
            MessageCard(
                icon: "xmark.circle.fill",
                title: "Resolution Failed",
                message: errorMessage,
                tint: .red
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }

        if let resolvedItem = viewModel.resolvedItem {
            ResolvedMediaSummaryCard(item: resolvedItem)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if viewModel.isLoading {
            loadingCard
                .transition(.opacity)
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 14) {
            ProgressView()
                .tint(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Resolving…")
                    .font(.subheadline.weight(.medium))
                Text("Fetching provider metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Logic (unchanged)

    private func pasteURL() {
        let pastedText = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        viewModel.urlText = pastedText
        viewModel.clearMessages()
        viewModel.clearResolvedItem()
    }
}

// MARK: - MessageCard

private struct MessageCard: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - ResolvedMediaSummaryCard

private struct ResolvedMediaSummaryCard: View {
    let item: ResolvedMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header label
            Text("Resolved Media")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider().padding(.horizontal, 16)

            // Thumbnail + title row
            HStack(alignment: .top, spacing: 14) {
                thumbnailView
                    .frame(width: 72, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    if let creator = item.creatorName, !creator.isEmpty {
                        Text(creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // Media type chips
                    HStack(spacing: 6) {
                        ForEach(item.availableMediaTypes, id: \.self) { type in
                            mediaTypeChip(type)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().padding(.horizontal, 16)

            // Metadata rows
            VStack(spacing: 0) {
                metaRow(label: "Provider", value: item.provider.capitalized)
                Divider().padding(.leading, 16)
                metaRow(label: "ID", value: item.providerItemId)

                if let duration = item.durationSeconds {
                    Divider().padding(.leading, 16)
                    metaRow(label: "Duration", value: formattedDuration(duration))
                }
            }

            Spacer(minLength: 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.2), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let url = item.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.secondarySystemFill), Color(.tertiarySystemFill)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "play.rectangle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }

    private func mediaTypeChip(_ type: MediaType) -> some View {
        let (label, color): (String, Color) = type == .audio
            ? ("Audio", .blue)
            : ("Video", .purple)

        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    URLInputView(provider: YouTubeProviderSpike())
}