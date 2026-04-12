import AVFoundation
import AVKit
import OSLog
import SwiftUI

enum PlaybackKind: String {
    case audio
    case video
}

enum PlaybackMode: CaseIterable {
    case playOnce
    case repeatAll
    case repeatOne
    case shuffle

    var title: String {
        switch self {
        case .playOnce:
            return "Play Once"
        case .repeatAll:
            return "Repeat All"
        case .repeatOne:
            return "Repeat One"
        case .shuffle:
            return "Shuffle"
        }
    }

    var symbolName: String {
        switch self {
        case .playOnce:
            return "play.circle"
        case .repeatAll:
            return "repeat"
        case .repeatOne:
            return "repeat.1"
        case .shuffle:
            return "shuffle"
        }
    }

    func next() -> PlaybackMode {
        switch self {
        case .playOnce:
            return .repeatAll
        case .repeatAll:
            return .repeatOne
        case .repeatOne:
            return .shuffle
        case .shuffle:
            return .playOnce
        }
    }
}

@MainActor
final class PlaybackAudioSessionCoordinator {
    static let shared = PlaybackAudioSessionCoordinator()

    private let session = AVAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "PlaybackAudioSession")
    private var lastKnownActiveState = false

    private init() {}

    func activateForPlayback(kind: PlaybackKind, fileURL: URL?) throws {
        let mode: AVAudioSession.Mode = kind == .video ? .moviePlayback : .default

        try session.setCategory(.playback, mode: mode)
        try session.setActive(true)
        lastKnownActiveState = true

        logSessionState(kind: kind, context: "activated", fileURL: fileURL)
    }

    func logSessionState(kind: PlaybackKind, context: String, fileURL: URL?) {
        logger.debug(
            """
            Audio session \(context, privacy: .public) kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL?.path ?? "nil", privacy: .public) \
            category=\(self.session.category.rawValue, privacy: .public) \
            mode=\(self.session.mode.rawValue, privacy: .public) \
            active=\(self.lastKnownActiveState, privacy: .public)
            """
        )
    }
}

private func playerItemStatusLabel(_ status: AVPlayerItem.Status) -> String {
    switch status {
    case .unknown:
        return "unknown"
    case .readyToPlay:
        return "readyToPlay"
    case .failed:
        return "failed"
    @unknown default:
        return "unknown-future"
    }
}

private func playerTimeControlStatusLabel(_ status: AVPlayer.TimeControlStatus) -> String {
    switch status {
    case .paused:
        return "paused"
    case .waitingToPlayAtSpecifiedRate:
        return "waiting"
    case .playing:
        return "playing"
    @unknown default:
        return "unknown-future"
    }
}

private func logAssetDiagnostics(
    kind: PlaybackKind,
    fileURL: URL,
    asset: AVURLAsset,
    player: AVPlayer,
    logger: Logger
) async {
    do {
        let isPlayable = try await asset.load(.isPlayable)
        let audibleTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
        let visualTracks = try await asset.loadTracks(withMediaCharacteristic: .visual)

        logger.debug(
            """
            Playback diagnostics kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL.path, privacy: .public) \
            playable=\(isPlayable, privacy: .public) \
            audibleTracks=\(audibleTracks.count, privacy: .public) \
            visualTracks=\(visualTracks.count, privacy: .public) \
            playerMuted=\(player.isMuted, privacy: .public)
            """
        )
    } catch {
        logger.error(
            """
            Playback diagnostics failed kind=\(kind.rawValue, privacy: .public) \
            fileURL=\(fileURL.path, privacy: .public) \
            error=\(String(describing: error), privacy: .public)
            """
        )
    }
}

@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published var title: String
    @Published var playbackStateText = "Preparing"
    @Published var errorMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var playbackMode: PlaybackMode = .playOnce

    private let playlist: [MediaItem]
    private let fileStorage: LocalFileStorage
    private var player: AVPlayer?
    private var currentMediaItem: MediaItem
    private var currentPlaylistIndex: Int
    private var currentPlayerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var didPreparePlayer = false
    private var isSeeking = false
    private var isReadyToPlay = false
    private var playWhenReady = false
    private var currentFileURL: URL?
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "AudioPlayerViewModel")

    init(item: MediaItem, playlist: [MediaItem] = [], fileStorage: LocalFileStorage) {
        let normalizedPlaylist = Self.normalizedPlaylist(for: item, from: playlist)

        self.currentMediaItem = normalizedPlaylist[0]
        self.currentPlaylistIndex = 0
        self.playlist = normalizedPlaylist
        self.fileStorage = fileStorage
        self.audioSessionCoordinator = .shared
        self.title = normalizedPlaylist[0].title
    }

    deinit {
        MainActor.assumeIsolated {
            removeObservers()
        }
    }

    func prepareIfNeeded() {
        guard !didPreparePlayer else {
            return
        }

        didPreparePlayer = true
        prepareCurrentTrack()
    }

    func play() {
        guard errorMessage == nil, let player else {
            return
        }

        playWhenReady = true

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: currentFileURL)
        } catch {
            logger.error("Audio session reactivation failed for item \(self.currentMediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        if duration > 0, currentTime >= max(duration - 0.25, 0) {
            player.seek(to: .zero)
        }

        guard isReadyToPlay else {
            playbackStateText = "Loading"
            return
        }

        logger.debug(
            """
            Audio play requested fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player?.isMuted ?? false, privacy: .public)
            """
        )
        player.play()
    }

    func pause() {
        playWhenReady = false
        player?.pause()
    }

    func seek(to time: Double) {
        guard let player else {
            return
        }

        let clampedTime = min(max(time, 0), duration)
        isSeeking = true
        currentTime = clampedTime

        player.seek(
            to: CMTime(seconds: clampedTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
            }
        }
    }

    func handleDisappear() {
        pause()
    }

    func cyclePlaybackMode() {
        playbackMode = playbackMode.next()
    }

    var canControlPlayback: Bool {
        errorMessage == nil && player != nil && duration >= 0
    }

    var displayedDuration: Double {
        duration > 0 ? duration : max(currentTime, 1)
    }

    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func prepareCurrentTrack(autoplay: Bool = false) {
        let item = currentMediaItem

        guard item.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setError("Audio file path is missing.")
            return
        }

        let fileURL: URL

        do {
            fileURL = try fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)
        } catch {
            logger.error("Audio playback open failed for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio file is missing at the saved local path.")
            return
        }

        currentFileURL = fileURL
        title = item.title
        logger.debug("Audio playback local file URL: \(fileURL.path, privacy: .public)")

        let asset = AVURLAsset(url: fileURL)
        let playerItem = AVPlayerItem(asset: asset)
        let player = player ?? AVPlayer()
        player.isMuted = false

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: fileURL)
        } catch {
            logger.error("Audio session activation failed for item \(item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        removeObservers()
        self.player = player
        isReadyToPlay = false
        playWhenReady = autoplay
        player.pause()
        player.replaceCurrentItem(with: playerItem)
        currentPlayerItem = playerItem
        errorMessage = nil
        playbackStateText = "Loading"
        currentTime = 0
        duration = 0
        installObservers(for: player, item: playerItem)
        Task {
            await logAssetDiagnostics(kind: .audio, fileURL: fileURL, asset: asset, player: player, logger: logger)
        }
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatusChange(item.status, error: item.error)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }

        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handlePeriodicTimeUpdate(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func handleItemStatusChange(_ status: AVPlayerItem.Status, error: Error?) {
        logger.debug(
            """
            Audio player item status=\(playerItemStatusLabel(status), privacy: .public) \
            fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player?.isMuted ?? false, privacy: .public)
            """
        )

        switch status {
        case .readyToPlay:
            isReadyToPlay = true
            errorMessage = nil
            duration = resolvedDuration(from: currentPlayerItem)
            playbackStateText = playWhenReady ? "Playing" : "Ready"

            if playWhenReady {
                player?.play()
            }
        case .failed:
            logger.error("Audio player item failed for item \(self.currentMediaItem.id.uuidString, privacy: .public): \(String(describing: error ?? self.currentPlayerItem?.error), privacy: .public)")
            setError(error?.localizedDescription ?? self.currentPlayerItem?.error?.localizedDescription ?? "Audio player item failed to load.")
        case .unknown:
            isReadyToPlay = false
            playbackStateText = "Loading"
        @unknown default:
            isReadyToPlay = false
            playbackStateText = "Loading"
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logger.debug("Audio time control status=\(playerTimeControlStatusLabel(status), privacy: .public)")

        switch status {
        case .paused:
            isPlaying = false
            if errorMessage == nil {
                if currentTime >= max(duration - 0.25, 0), duration > 0, !playWhenReady {
                    playbackStateText = "Finished"
                } else {
                    playbackStateText = currentTime > 0 ? "Paused" : "Ready"
                }
            }
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = false
            if errorMessage == nil {
                playbackStateText = "Buffering"
            }
        case .playing:
            isPlaying = true
            errorMessage = nil
            playbackStateText = "Playing"
        @unknown default:
            isPlaying = false
        }
    }

    private func handlePeriodicTimeUpdate(_ time: CMTime) {
        guard !isSeeking else {
            return
        }

        currentTime = max(time.seconds, 0)
        duration = max(duration, resolvedDuration(from: currentPlayerItem))
    }

    private func handlePlaybackEnded() {
        currentTime = duration

        switch playbackMode {
        case .playOnce:
            playWhenReady = false
            isPlaying = false
            playbackStateText = "Finished"
        case .repeatOne:
            restartCurrentTrack()
        case .repeatAll:
            playAdjacentTrack()
        case .shuffle:
            playShuffledTrack()
        }
    }

    private func resolvedDuration(from item: AVPlayerItem?) -> Double {
        guard let item else {
            return 0
        }

        let seconds = item.duration.seconds
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }

        return seconds
    }

    private func setError(_ message: String) {
        player?.pause()
        playWhenReady = false
        isReadyToPlay = false
        isPlaying = false
        playbackStateText = "Unavailable"
        errorMessage = message
        currentTime = 0
        duration = 0
    }

    private func removeObservers() {
        itemStatusObservation = nil
        timeControlStatusObservation = nil

        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func restartCurrentTrack() {
        guard let player else {
            return
        }

        playWhenReady = true

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .audio, fileURL: currentFileURL)
        } catch {
            logger.error("Audio session reactivation failed for repeated item \(self.currentMediaItem.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Audio session could not be activated: \(error.localizedDescription)")
            return
        }

        player.seek(
            to: .zero,
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.currentTime = 0
                self.player?.play()
            }
        }
    }

    private func playAdjacentTrack() {
        guard !playlist.isEmpty else {
            return
        }

        if playlist.count == 1 {
            restartCurrentTrack()
            return
        }

        let nextIndex = (currentPlaylistIndex + 1) % playlist.count
        currentPlaylistIndex = nextIndex
        currentMediaItem = playlist[nextIndex]
        prepareCurrentTrack(autoplay: true)
    }

    private func playShuffledTrack() {
        guard !playlist.isEmpty else {
            return
        }

        if playlist.count == 1 {
            restartCurrentTrack()
            return
        }

        let availableIndexes = playlist.indices.filter { $0 != currentPlaylistIndex }
        guard let nextIndex = availableIndexes.randomElement() else {
            restartCurrentTrack()
            return
        }

        currentPlaylistIndex = nextIndex
        currentMediaItem = playlist[nextIndex]
        prepareCurrentTrack(autoplay: true)
    }

    private static func normalizedPlaylist(for item: MediaItem, from playlist: [MediaItem]) -> [MediaItem] {
        let playableItems = playlist.filter {
            $0.mediaType == .audio &&
            $0.downloadStatus == .downloaded &&
            $0.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        if let currentIndex = playableItems.firstIndex(where: { $0.id == item.id }) {
            var reorderedItems = playableItems
            let currentItem = reorderedItems.remove(at: currentIndex)
            reorderedItems.insert(currentItem, at: 0)
            return reorderedItems
        }

        return [item] + playableItems.filter { $0.id != item.id }
    }
}

struct AudioPlayerView: View {
    @StateObject private var viewModel: AudioPlayerViewModel

    init(
        item: MediaItem,
        playlist: [MediaItem] = [],
        fileStorage: LocalFileStorage = ApplicationSupportFileStorage()
    ) {
        _viewModel = StateObject(
            wrappedValue: AudioPlayerViewModel(item: item, playlist: playlist, fileStorage: fileStorage)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.errorMessage ?? viewModel.playbackStateText)
                .font(.body)
                .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.red)

            VStack(spacing: 12) {
                Slider(
                    value: Binding(
                        get: { min(viewModel.currentTime, viewModel.displayedDuration) },
                        set: { viewModel.seek(to: $0) }
                    ),
                    in: 0...viewModel.displayedDuration
                )
                .disabled(!viewModel.canControlPlayback || viewModel.displayedDuration <= 0)

                HStack {
                    Text(viewModel.formattedTime(viewModel.currentTime))
                    Spacer()
                    Text(viewModel.formattedTime(viewModel.duration))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                viewModel.cyclePlaybackMode()
            } label: {
                Label(viewModel.playbackMode.title, systemImage: viewModel.playbackMode.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canControlPlayback)

            HStack(spacing: 12) {
                Button("Play") {
                    viewModel.play()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canControlPlayback)

                Button("Pause") {
                    viewModel.pause()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canControlPlayback || !viewModel.isPlaying)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Audio Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: viewModel.prepareIfNeeded)
        .onDisappear(perform: viewModel.handleDisappear)
    }
}

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var playbackStateText = "Preparing"
    @Published var errorMessage: String?

    private let item: MediaItem
    private let fileStorage: LocalFileStorage
    private let audioSessionCoordinator: PlaybackAudioSessionCoordinator
    private var didPreparePlayer = false
    private var currentPlayerItem: AVPlayerItem?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var currentFileURL: URL?
    private var isReadyToPlay = false
    private var playWhenReady = false
    private let logger = Logger(subsystem: "com.bo.IOSMusicApp", category: "VideoPlayerViewModel")

    let title: String
    let player = AVPlayer()

    init(item: MediaItem, fileStorage: LocalFileStorage) {
        self.item = item
        self.fileStorage = fileStorage
        self.audioSessionCoordinator = .shared
        self.title = item.title
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func prepareIfNeeded() {
        guard !didPreparePlayer else {
            return
        }

        didPreparePlayer = true
        Task {
            await preparePlayer()
        }
    }

    func play() {
        guard errorMessage == nil else {
            return
        }

        playWhenReady = true

        do {
            try audioSessionCoordinator.activateForPlayback(kind: .video, fileURL: currentFileURL)
        } catch {
            logger.error("Video session activation failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video audio session could not be activated: \(error.localizedDescription)")
            return
        }

        guard isReadyToPlay else {
            playbackStateText = "Loading"
            logger.debug("Video play deferred until ready fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public)")
            return
        }

        player.isMuted = false
        logger.debug(
            """
            Video play requested fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player.isMuted, privacy: .public)
            """
        )
        player.play()
    }

    func pause() {
        playWhenReady = false
        player.pause()
    }

    func handleDisappear() {
        pause()
    }

    private func preparePlayer() async {
        guard item.localFilePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            setError("Video file path is missing.")
            return
        }

        let fileURL: URL

        do {
            fileURL = try fileStorage.resolveExistingManagedFileURL(from: item.localFilePath)
        } catch {
            logger.error("Video playback open failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video file is missing at the saved local path.")
            return
        }

        currentFileURL = fileURL
        logger.debug("Video playback local file URL: \(fileURL.path, privacy: .public)")

        let asset = AVURLAsset(url: fileURL)

        do {
            let isPlayable = try await asset.load(.isPlayable)
            let audibleTracks = try await asset.loadTracks(withMediaCharacteristic: .audible)
            guard isPlayable else {
                logger.error("Video asset is not playable for item \(self.item.id.uuidString, privacy: .public)")
                setError("Video file is not playable.")
                return
            }

            logger.debug(
                """
                Video asset inspected fileURL=\(fileURL.path, privacy: .public) \
                audibleTracks=\(audibleTracks.count, privacy: .public)
                """
            )

            try audioSessionCoordinator.activateForPlayback(kind: .video, fileURL: fileURL)

            let playerItem = AVPlayerItem(asset: asset)
            removeObservers()
            currentPlayerItem = playerItem
            isReadyToPlay = false
            playWhenReady = false
            player.isMuted = false
            player.replaceCurrentItem(with: playerItem)
            installObservers(for: player, item: playerItem)
            errorMessage = nil
            playbackStateText = "Loading"

            Task {
                await logAssetDiagnostics(kind: .video, fileURL: fileURL, asset: asset, player: player, logger: logger)
            }
        } catch {
            logger.error("Video playback preparation failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
            setError("Video file could not be prepared: \(error.localizedDescription)")
        }
    }

    private func installObservers(for player: AVPlayer, item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatusChange(item.status, error: item.error)
            }
        }

        timeControlStatusObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(player.timeControlStatus)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnded()
            }
        }
    }

    private func removeObservers() {
        itemStatusObservation = nil
        timeControlStatusObservation = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func handleItemStatusChange(_ status: AVPlayerItem.Status, error: Error?) {
        logger.debug(
            """
            Video player item status=\(playerItemStatusLabel(status), privacy: .public) \
            fileURL=\(self.currentFileURL?.path ?? "nil", privacy: .public) \
            muted=\(self.player.isMuted, privacy: .public)
            """
        )

        switch status {
        case .readyToPlay:
            isReadyToPlay = true
            errorMessage = nil
            playbackStateText = player.timeControlStatus == .playing ? "Playing" : "Ready"

            if playWhenReady {
                play()
            }
        case .failed:
            logger.error("Video player item failed for item \(self.item.id.uuidString, privacy: .public): \(String(describing: error ?? self.currentPlayerItem?.error), privacy: .public)")
            setError(error?.localizedDescription ?? self.currentPlayerItem?.error?.localizedDescription ?? "Video player item failed to load.")
        case .unknown:
            isReadyToPlay = false
            playbackStateText = "Loading"
        @unknown default:
            isReadyToPlay = false
            playbackStateText = "Loading"
        }
    }

    private func handleTimeControlStatusChange(_ status: AVPlayer.TimeControlStatus) {
        logger.debug("Video time control status=\(playerTimeControlStatusLabel(status), privacy: .public)")

        switch status {
        case .paused:
            if errorMessage == nil {
                playbackStateText = isReadyToPlay ? "Ready" : "Loading"
            }
        case .waitingToPlayAtSpecifiedRate:
            if errorMessage == nil {
                playbackStateText = "Buffering"
            }
        case .playing:
            errorMessage = nil
            playbackStateText = "Playing"
        @unknown default:
            break
        }
    }

    private func handlePlaybackEnded() {
        playWhenReady = false
        playbackStateText = "Finished"
    }

    private func setError(_ message: String) {
        removeObservers()
        playWhenReady = false
        isReadyToPlay = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentPlayerItem = nil
        errorMessage = message
        playbackStateText = "Unavailable"
    }
}

struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel

    init(item: MediaItem, fileStorage: LocalFileStorage = ApplicationSupportFileStorage()) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(item: item, fileStorage: fileStorage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(viewModel.title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.errorMessage ?? viewModel.playbackStateText)
                .font(.body)
                .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.red)

            VideoPlayer(player: viewModel.player)
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button("Play") {
                    viewModel.play()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.errorMessage != nil)

                Button("Pause") {
                    viewModel.pause()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.errorMessage != nil)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Video Player")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: viewModel.prepareIfNeeded)
        .onDisappear(perform: viewModel.handleDisappear)
    }
}

struct PlayerView: View {
    var body: some View {
        NavigationStack {
            Text("Player placeholder")
                .navigationTitle("Player")
        }
    }
}

#Preview {
    NavigationStack {
        AudioPlayerView(
            item: MediaItem(
                providerName: "preview",
                providerItemID: "preview-item",
                title: "Preview Audio",
                creatorName: "Preview Creator",
                mediaType: .audio,
                downloadStatus: .downloaded,
                localFilePath: "/tmp/audio.m4a"
            )
        )
    }
}
