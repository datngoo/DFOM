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
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resolve Media URL")
                            .font(.title2.weight(.semibold))

                        Text("Paste a direct YouTube video link to resolve provider metadata before download flow is added.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 8) {
                            TextField("https://www.youtube.com/watch?v=...", text: $viewModel.urlText, axis: .vertical)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .onSubmit {
                                    Task {
                                        await viewModel.resolve()
                                    }
                                }

                            if !viewModel.urlText.isEmpty {
                                Button {
                                    viewModel.urlText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                        .opacity(0.75)
                                        .padding(2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear URL")
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.separator), lineWidth: 1)
                        )

                        HStack(spacing: 12) {
                            Button("Paste") {
                                pasteURL()
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isLoading)

                            Button {
                                Task {
                                    await viewModel.resolve()
                                }
                            } label: {
                                if viewModel.isLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Resolving...")
                                    }
                                } else {
                                    Text("Resolve URL")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isLoading)
                        }
                    }

                    if let validationMessage = viewModel.validationMessage {
                        MessageCard(
                            title: "Check The URL",
                            message: validationMessage,
                            tint: .orange
                        )
                    }

                    if let errorMessage = viewModel.errorMessage {
                        MessageCard(
                            title: "Resolution Failed",
                            message: errorMessage,
                            tint: .red
                        )
                    }

                    if let resolvedItem = viewModel.resolvedItem {
                        ResolvedMediaSummaryCard(item: resolvedItem)
                    } else if viewModel.isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Resolving provider metadata...")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 6)
                .padding(.bottom)
            }
            .navigationTitle("Input")
            .navigationDestination(for: ResolvedMediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .onChange(of: viewModel.resolvedItem) { _, item in
                guard let item else {
                    return
                }

                navigationPath = [item]
            }
        }
    }

    private func pasteURL() {
        let pastedText = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        viewModel.urlText = pastedText
        viewModel.clearMessages()
        viewModel.clearResolvedItem()
    }
}

private struct MessageCard: View {
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(tint)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(0.08))
        )
    }
}

private struct ResolvedMediaSummaryCard: View {
    let item: ResolvedMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resolved Media")
                .font(.headline)

            Text(item.title)
                .font(.title3.weight(.semibold))

            if let creatorName = item.creatorName, !creatorName.isEmpty {
                LabeledValueRow(label: "Creator", value: creatorName)
            }

            LabeledValueRow(label: "Provider", value: item.provider)
            LabeledValueRow(label: "Provider Item ID", value: item.providerItemId)
            LabeledValueRow(
                label: "Available Types",
                value: item.availableMediaTypes.map { $0.rawValue.capitalized }.joined(separator: ", ")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct LabeledValueRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    URLInputView(provider: YouTubeProviderSpike())
}
