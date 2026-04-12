import SwiftUI
import SwiftData
import OSLog

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hasRunLaunchReconciliation = false
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "RootTabView")

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
}
