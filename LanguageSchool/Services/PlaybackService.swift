import SwiftUI
import AVFoundation

@MainActor
protocol PlaybackServicing: AnyObject {
    var currentTrackID: String? { get }
    var isPlaying: Bool { get }
    var errorMessage: String? { get }
    
    func play(bundleResource: String, ext: String)
    func play(url: URL, id: String?)
    func toggle()
    func stop()
    func isPlaying(id: String) -> Bool
}

//TODO: - Удалить из ассетов экзампл музыки

@MainActor
@Observable
final class PlaybackService: NSObject, PlaybackServicing {
    
    // Публичное состояние
    private(set) var currentTrackID: String?
    private(set) var isPlaying: Bool = false
    private(set) var errorMessage: String?

    /// Скорость воспроизведения аудио (0.5 / 1 / 1.5 / 2). Применяется к
    /// текущему и всем последующим играм. Требует `enableRate = true` —
    /// проставляем перед установкой rate. Видео/аватара это не касается.
    var playbackRate: Float = 1.0 {
        didSet {
            guard let p = player else { return }
            p.enableRate = true
            p.rate = playbackRate
        }
    }

    // Плеер живёт только пока играет
    private var player: AVAudioPlayer?
    
    override init() {
        super.init()
        configureSession()
        observeInterruptions()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public API
    
    /// Начать проигрывание файла из bundle. Останавливает предыдущий.
    func play(bundleResource: String, ext: String = "mp3") {
        guard let url = Bundle.main.url(forResource: bundleResource, withExtension: ext) else {
            errorMessage = "File not found: \(bundleResource).\(ext)"
            return
        }
        play(url: url, id: "\(bundleResource).\(ext)")
    }
    
    /// Начать проигрывание по URL. Останавливает предыдущий.
    func play(url: URL, id: String? = nil) {
        stopInternal()
        
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            // Скорость: нужно выставить enableRate=true ДО первого play(),
            // иначе rate игнорируется на некоторых устройствах.
            newPlayer.enableRate = true
            newPlayer.rate = playbackRate
            newPlayer.prepareToPlay()
            newPlayer.play()
            
            player = newPlayer
            currentTrackID = id ?? url.lastPathComponent
            isPlaying = true
            errorMessage = nil
        } catch {
            errorMessage = "Play failed: \(error.localizedDescription)"
        }
    }
    
    /// Пауза / возобновление текущего.
    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }
    
    /// Полностью остановить и освободить плеер.
    func stop() {
        stopInternal()
        currentTrackID = nil
    }
    
    /// Играет ли конкретный трек прямо сейчас.
    func isPlaying(id: String) -> Bool {
        isPlaying && currentTrackID == id
    }
    
    // MARK: - Private
    
    private func stopInternal() {
        player?.stop()
        player = nil
        isPlaying = false
    }
    
    private func configureSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = "Session: \(error.localizedDescription)"
        }
    }
    
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    @objc nonisolated private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        
        Task { @MainActor in
            if type == .began { self.isPlaying = false }
        }
    }
}

// MARK: - Delegate

extension PlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTrackID = nil
            self.player = nil    // ← освобождаем память после окончания
        }
    }
}
