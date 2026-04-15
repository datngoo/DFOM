import SwiftUI
import SwiftData

@main
struct IOSMusicAppApp: App {
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
        }
        .modelContainer(for: [MediaItem.self, Playlist.self, PlaylistEntry.self])
    }
}
	
