import SwiftUI
import SwiftData
import OSLog

struct RootTabView: View {
    private enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let miniPlayerGapFromTabBar: CGFloat = 55
        static let miniPlayerTopBreathingSpace: CGFloat = 3
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlaybackController: AudioPlaybackController
    @State private var hasRunLaunchReconciliation = false
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "RootTabView")

    private var isMiniPlayerVisible: Bool {
        audioPlaybackController.currentMediaItem != nil
    }

    var body: some View {
        TabView {
            URLInputView()
                .tabItem {
                    Label("Input", systemImage: "link")
                }

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack {
                if isMiniPlayerVisible {
                    VStack(spacing: 0) {
                        GlobalAudioMiniPlayer()
                            .padding(.horizontal, Layout.horizontalPadding)
                            .transition(
                                .move(edge: .bottom)
                                .combined(with: .opacity)
                            )
                        Color.clear
                            .frame(height: Layout.miniPlayerGapFromTabBar)
                    }
                    .padding(.top, Layout.miniPlayerTopBreathingSpace)
                } else {
                    Color.clear
                        .frame(height: Layout.miniPlayerTopBreathingSpace)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.88), value: isMiniPlayerVisible)
        }
        .sheet(isPresented: $audioPlaybackController.isPlayerPresented, onDismiss: {
            audioPlaybackController.dismissFullPlayer()
        }) {
            NavigationStack {
                AudioPlayerView()
            }
            .presentationDetents([.medium, .large])
        }
        .task {
            await runLaunchReconciliationIfNeeded()
        }
    }

    @MainActor
    private func runLaunchReconciliationIfNeeded() async {
        guard !hasRunLaunchReconciliation else {
            return
        }

        hasRunLaunchReconciliation = true

        let repository = SwiftDataMediaLibraryRepository(modelContext: modelContext)
        let fileStorage = ApplicationSupportFileStorage()
        let reconciler = LaunchMediaReconciler(repository: repository, fileStorage: fileStorage)

        do {
            _ = try fileStorage.createBaseDirectories()
            try reconciler.reconcileDownloadedItems()
        } catch {
            logger.error("Launch reconciliation failed: \(String(describing: error), privacy: .public)")
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(AudioPlaybackController.shared)
}
