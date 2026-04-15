import SwiftUI
import SwiftData

@main
struct IOSMusicAppApp: App {
    @StateObject private var audioPlaybackController = AudioPlaybackController.shared

    init() {
        #if DEBUG
        if ProviderSpikeDebugRunner.isEnabledForCurrentLaunch {
            ProviderSpikeDebugRunner.runOnLaunchIfEnabled()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(audioPlaybackController)
        }
        .modelContainer(for: [MediaItem.self, Playlist.self, PlaylistEntry.self])
    }
}
	
