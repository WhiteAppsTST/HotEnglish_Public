import AVFoundation
import QuartzCore
import SwiftUI

/// Плеер для видео учительниц + опциональной параллельной аудио-дорожки.
///
/// Замысел (по продуктовому требованию):
/// - Все видео у нас **немые** (звук отдельными mp3-файлами).
/// - Все видео учительницы **начинаются и заканчиваются одним и тем же
///   кадром** — «rest position». Это позволяет **бесшовно** переключаться
///   между разными видео-состояниями: старое видео заканчивается в rest,
///   новое начинается с rest → визуально нет прыжка.
///
/// Реализация:
/// - `AVPlayer` + `replaceCurrentItem` вместо `AVQueuePlayer + AVPlayerLooper`
///   потому что `AVPlayerLooper` при re-build'е с новым template'ом сбрасывает
///   layer и на границе виден чёрный кадр. `replaceCurrentItem` в связке с
///   preloaded `AVPlayerItem` и seek(.zero) держит `AVPlayerLayer` живым и
///   свопы происходят без мигания.
/// - Base item кэшируется как AVAsset+AVPlayerItem: при возврате из
///   override'а не пересоздаём с диска.
/// - Все swap'ы обёрнуты в `CATransaction.setDisableActions(true)` чтобы Core
///   Animation не пыталась делать implicit-fade.
///
/// API:
/// - `setBase(video:)` — задаёт фоновый idle-луп.
/// - `playOnce(video:audio:)` — один раз (+audio) → возврат к base-loop.
/// - `playLoop(video:audio:pauseBetween:)` — вечный луп с опциональной паузой.
/// - `stop()` — вернуться к base-loop (или очистить, если base не задан).
///
/// TODO: аудио-сессия `.playback` — если параллельно активен
/// `SpeechDictationService` (recording), возможен конфликт.
@MainActor
@Observable
final class AvatarPlayer {

    // MARK: - Public

    /// AVPlayer для рендера. Прикладывается к `AVPlayerLayer` во вьюхе.
    let videoPlayer = AVPlayer()

    /// URL текущего base-loop видео. Может быть `nil` до `setBase()`.
    private(set) var baseVideoURL: URL?

    /// Играется ли сейчас override (one-shot или custom loop), или base-loop.
    private(set) var isPlayingOverride: Bool = false

    // MARK: - Private

    /// Кэш base asset'а — чтобы возвращаться к нему без файлового IO.
    private var baseAsset: AVAsset?

    /// Текущий item в плеере. Используется для сравнения в end-observer'е,
    /// чтобы понимать base ли это (→ seek zero + loop) или override
    /// (→ finishOverride).
    private var currentItem: AVPlayerItem?

    /// Флаг «текущий item — base»; на end либо loop'им, либо возвращаемся.
    private var isCurrentBase: Bool = false

    private var audioPlayer: AVAudioPlayer?
    private var endObserver: NSObjectProtocol?
    private var pauseLoopTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        videoPlayer.isMuted = true
        videoPlayer.actionAtItemEnd = .none
        // Уменьшает вероятность паузы на буферизации локальных файлов.
        videoPlayer.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: - Base loop

    func setBase(video: URL) {
        baseVideoURL = video
        baseAsset = AVURLAsset(url: video)
        if !isPlayingOverride {
            startBaseLoop()
        }
    }

    // MARK: - Playback

    func playOnce(video: URL, audio: URL? = nil) {
        cancelPending()
        stopAudio()
        isPlayingOverride = true
        let item = AVPlayerItem(url: video)
        swap(to: item, isBase: false)
        if let audio { playAudio(audio, loop: false) }
    }

    func playLoop(video: URL, audio: URL? = nil, pauseBetween: TimeInterval = 0) {
        cancelPending()
        stopAudio()
        isPlayingOverride = true

        if pauseBetween <= 0 {
            // Вечный луп через seek(.zero) на end. Хендлится в endObserver
            // как «base»-режим — но baseVideoURL мы не трогаем чтобы stop()
            // мог вернуть к настоящему base.
            let item = AVPlayerItem(url: video)
            swap(to: item, isBase: true)
            if let audio { playAudio(audio, loop: true) }
        } else {
            startLoopWithPause(video: video, audio: audio, pauseBetween: pauseBetween)
        }
    }

    func stop() {
        cancelPending()
        stopAudio()
        isPlayingOverride = false
        if baseVideoURL != nil {
            startBaseLoop()
        } else {
            videoPlayer.pause()
        }
    }

    // MARK: - Loop mechanics

    private func startBaseLoop() {
        guard let asset = baseAsset ?? baseVideoURL.map({ AVURLAsset(url: $0) }) else { return }
        baseAsset = asset
        let item = AVPlayerItem(asset: asset)
        swap(to: item, isBase: true)
    }

    /// Заменить текущий item плавно: без CA-анимации, с seek(.zero) чтобы item
    /// стартовал с первого кадра моментально.
    private func swap(to item: AVPlayerItem, isBase: Bool) {
        // Снять старый observer.
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setAnimationDuration(0)
        videoPlayer.replaceCurrentItem(with: item)
        item.seek(to: .zero, completionHandler: nil)
        videoPlayer.play()
        CATransaction.commit()

        currentItem = item
        isCurrentBase = isBase

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleEnd(of: item) }
        }
    }

    private func handleEnd(of item: AVPlayerItem) {
        guard item === currentItem else { return }
        if isCurrentBase {
            // Луп — seek к нулю и продолжаем без re-load'а. AVPlayerLayer не
            // разрушается → чёрного кадра нет.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            item.seek(to: .zero, completionHandler: nil)
            videoPlayer.play()
            CATransaction.commit()
        } else {
            finishOverride()
        }
    }

    /// Луп с ручной паузой между итерациями через async Task.
    private func startLoopWithPause(video: URL, audio: URL?, pauseBetween: TimeInterval) {
        pauseLoopTask?.cancel()
        pauseLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.playOneCycle(video: video, audio: audio)
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: UInt64(pauseBetween * 1_000_000_000))
            }
        }
    }

    private func playOneCycle(video: URL, audio: URL?) async {
        let item = AVPlayerItem(url: video)
        // Не помечаем как base — чтобы end не self-loop'нулся.
        swap(to: item, isBase: false)
        if let audio { playAudio(audio, loop: false) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let obs = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in cont.resume() }
            endObserver = obs
        }
    }

    // MARK: - One-shot completion

    private func finishOverride() {
        cancelPending()
        stopAudio()
        isPlayingOverride = false
        if baseVideoURL != nil {
            startBaseLoop()
        }
    }

    // MARK: - Cleanup

    private func cancelPending() {
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        endObserver = nil
        pauseLoopTask?.cancel()
        pauseLoopTask = nil
    }

    // MARK: - Audio

    private func playAudio(_ url: URL, loop: Bool) {
        stopAudio()
        activateAudioSession()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loop ? -1 : 0
            player.play()
            audioPlayer = player
        } catch {
            // TODO: залогировать в общий error-log.
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func activateAudioSession() {
        // .playback + .mixWithOthers — играет и в silent-mode, не рушит STT.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // TODO: log
        }
    }
}
