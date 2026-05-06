import SwiftUI
import SwiftData
import OSLog

struct RootTabView: View {
    private enum AppTab: Hashable {
        case service
        case library
    }

    private enum Layout {
        static let floatingMiniPlayerHorizontalMargin: CGFloat = 16
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlaybackController: AudioPlaybackController
    @State private var hasRunLaunchReconciliation = false
    @State private var selectedTab: AppTab = .service
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "RootTabView")

    private var isMiniPlayerVisible: Bool {
        selectedTab == .library && audioPlaybackController.currentMediaItem != nil
    }

    var body: some View {
        GeometryReader { proxy in
            TabView(selection: $selectedTab) {
                URLInputView()
                    .tag(AppTab.service)
                    .tabItem {
                        Label("Service", systemImage: "square.stack.3d.up")
                    }

                LibraryView()
                    .tag(AppTab.library)
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
            }
            // Phase 1: slightly more refined entry/exit for the mini player
            .overlay(alignment: .topLeading) {
                if isMiniPlayerVisible {
                    FloatingMiniPlayerOverlay(
                        containerSize: proxy.size,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.88, anchor: .bottomTrailing)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.88, anchor: .bottomTrailing)
                                .combined(with: .opacity)
                        )
                    )
                    .padding(.horizontal, Layout.floatingMiniPlayerHorizontalMargin)
                    .padding(.top, 4)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: isMiniPlayerVisible)
                }
            }
        }
        .sheet(isPresented: $audioPlaybackController.isPlayerPresented, onDismiss: {
            audioPlaybackController.dismissFullPlayer()
        }) {
            NavigationStack {
                AudioPlayerView()
            }
            .presentationDetents([.large])
        }
        .task {
            await runLaunchReconciliationIfNeeded()
        }
        // Phase 1: configure tab bar appearance once on launch
        .onAppear {
            configureTabBarAppearance()
        }
    }

    // MARK: - Private helpers (logic unchanged)

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

    // MARK: - Phase 1: Tab bar visual configuration

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()

        // Thin frosted base instead of a hard opaque white/dark fill
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.72)

        // Hairline separator instead of the default heavy shadow
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.45)

        // Selected item: accent color at full opacity
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
        ]
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttrs
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor(Color.accentColor)

        // Unselected item: secondary label, slightly lighter weight
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .regular)
        ]
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttrs
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Floating mini player overlay (geometry + logic 100% unchanged)

private struct FloatingMiniPlayerOverlay: View {
    private enum Layout {
        static let minWidth: CGFloat = 200
        static let maxWidth: CGFloat = 270
        static let height: CGFloat = 72
        static let horizontalPadding: CGFloat = 16
        static let topPadding: CGFloat = 18
        static let bottomClearance: CGFloat = 94
    }

    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var restingPosition: CGPoint?

    var body: some View {
        let miniPlayerSize = CGSize(width: miniPlayerWidth, height: Layout.height)

        GlobalAudioMiniPlayer()
            .frame(width: miniPlayerWidth)
            .position(currentPosition(for: miniPlayerSize))
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let start = restingPosition ?? defaultPosition(for: miniPlayerSize)
                        let target = CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        )
                        restingPosition = snappedPosition(for: clamp(target, size: miniPlayerSize), size: miniPlayerSize)
                    }
            )
            .onAppear {
                if restingPosition == nil {
                    restingPosition = defaultPosition(for: miniPlayerSize)
                }
            }
            .onChange(of: containerSize) { _, _ in
                guard let restingPosition else {
                    return
                }

                self.restingPosition = clamp(restingPosition, size: miniPlayerSize)
            }
    }

    private var miniPlayerWidth: CGFloat {
        min(max(containerSize.width * 0.52, Layout.minWidth), Layout.maxWidth)
    }

    private func currentPosition(for size: CGSize) -> CGPoint {
        let base = restingPosition ?? defaultPosition(for: size)
        let translated = CGPoint(
            x: base.x + dragTranslation.width,
            y: base.y + dragTranslation.height
        )

        return clamp(translated, size: size)
    }

    private func defaultPosition(for size: CGSize) -> CGPoint {
        CGPoint(
            x: containerSize.width - (size.width / 2) - Layout.horizontalPadding,
            y: containerSize.height - safeAreaInsets.bottom - Layout.bottomClearance - (size.height / 2)
        )
    }

    private func clamp(_ point: CGPoint, size: CGSize) -> CGPoint {
        let minX = size.width / 2 + Layout.horizontalPadding
        let maxX = containerSize.width - size.width / 2 - Layout.horizontalPadding
        let minY = safeAreaInsets.top + size.height / 2 + Layout.topPadding
        let maxY = containerSize.height - safeAreaInsets.bottom - Layout.bottomClearance - (size.height / 2)

        return CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }

    private func snappedPosition(for point: CGPoint, size: CGSize) -> CGPoint {
        let minX = size.width / 2 + Layout.horizontalPadding
        let maxX = containerSize.width - size.width / 2 - Layout.horizontalPadding
        let targetX = point.x < containerSize.width / 2 ? minX : maxX

        return CGPoint(x: targetX, y: point.y)
    }
}

#Preview {
    RootTabView()
        .environmentObject(AudioPlaybackController.shared)
}