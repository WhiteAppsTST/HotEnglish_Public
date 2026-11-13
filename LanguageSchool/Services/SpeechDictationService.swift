import Foundation
import AVFoundation
import Speech

// MARK: - Public API

nonisolated
enum SpeechAuthorizationStatus: Sendable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

nonisolated
enum SpeechDictationError: Error, LocalizedError, Sendable {
    case notAuthorized
    case micNotAuthorized
    case recognizerUnavailable(LanguageCode)
    case audioEngineFailed(String)
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:           "Speech recognition permission denied"
        case .micNotAuthorized:        "Microphone permission denied"
        case .recognizerUnavailable(let l): "Recognizer for \(l.displayTitle) unavailable"
        case .audioEngineFailed(let s):    "Audio engine: \(s)"
        case .recognitionFailed(let s):    "Recognition: \(s)"
        }
    }
}

@MainActor
protocol SpeechDictating: AnyObject {
    var isRecording: Bool { get }
    /// Текущий текст распознавания. Обновляется потоково по мере того, как юзер говорит.
    var transcript: String { get }
    /// true если получен финальный результат (recognition завершилось само).
    var isFinal: Bool { get }
    var error: SpeechDictationError? { get }
    /// URL WAV-файла последней завершённой записи (16 kHz mono int16). Стабильно
    /// доступен после `stopRecording()`. Файл живёт до следующего `startRecording`
    /// или пока не будет очищен вручную. `nil` — если запись ещё не запускалась
    /// или запись оборвалась до появления буферов.
    var recordedAudioURL: URL? { get }

    func requestAuthorization() async -> SpeechAuthorizationStatus
    func startRecording(language: LanguageCode) async throws
    func stopRecording()
}

// MARK: - Implementation

@MainActor
@Observable
final class SpeechDictationService: NSObject, SpeechDictating {

    // Observable state
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var isFinal = false
    private(set) var error: SpeechDictationError?
    private(set) var recordedAudioURL: URL?

    // Internals
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // Audio capture (для отправки в мультимодальный GPT). Пишем параллельно
    // с распознаванием, конвертим float PCM микрофона в int16 mono 16kHz —
    // OpenAI Chat Completions принимает WAV именно в этом формате.
    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var audioFileURL: URL?
    private static let audioOutputFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    // MARK: - Authorization

    func requestAuthorization() async -> SpeechAuthorizationStatus {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: Self.map(status))
            }
        }
    }

    /// Отдельный запрос mic-разрешения. iOS показывает системный алерт если
    /// статус `.undetermined`, иначе сразу возвращает текущий результат.
    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    // MARK: - Start / stop
    func startRecording(language: LanguageCode) async throws {
        stopRecording()

        // 1. Speech permission
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechDictationError.notAuthorized
        }

        // 2. Mic permission
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw SpeechDictationError.micNotAuthorized
        }

        // 3. Recognizer for target locale
        let locale = Self.locale(for: language)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechDictationError.recognizerUnavailable(language)
        }
        self.recognizer = recognizer

        // 4. Audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechDictationError.audioEngineFailed("Session: \(error.localizedDescription)")
        }

        // 5. Streaming request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        // 6. Tap the input node + параллельная запись в WAV (для GPT-мультимодала).
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        prepareAudioCapture(inputFormat: format)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.appendBufferToFile(buffer)
        }

        // 7. Prepare + start
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.request = nil
            audioFile = nil
            audioConverter = nil
            audioFileURL = nil
            throw SpeechDictationError.audioEngineFailed("Start: \(error.localizedDescription)")
        }

        // 8. Reset state
        transcript = ""
        isFinal = false
        error = nil
        isRecording = true

        // 9. Kick off recognition
        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: err)
            }
        }
    }

    func stopRecording() {
        guard isRecording || audioEngine.isRunning else {
            // Всё равно вычистим ресурсы, если что-то висит
            audioEngine.inputNode.removeTap(onBus: 0)
            request = nil
            task = nil
            finalizeAudioCapture()
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        finalizeAudioCapture()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Handler

    private func handleRecognition(result: SFSpeechRecognitionResult?, error err: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString
            isFinal = result.isFinal
            if result.isFinal {
                stopRecording()
                return
            }
        }
        if let err = err as NSError? {
            // 216 — «no speech detected / cancelled by user» в kAFAssistantErrorDomain, не полезно показывать
            let benign = err.domain == "kAFAssistantErrorDomain" && (err.code == 216 || err.code == 203)
            if !benign {
                self.error = .recognitionFailed(err.localizedDescription)
            }
            stopRecording()
        }
    }

    // MARK: - Audio capture (WAV для GPT-мультимодала)

    /// Готовит фоновую запись микрофона в WAV. Создаёт временный файл в
    /// tmp/, чистит предыдущий (чтобы не копить мусор), собирает конвертер
    /// из native input-format в 16 kHz mono int16.
    private func prepareAudioCapture(inputFormat: AVAudioFormat) {
        // Убираем предыдущий файл — держим только запись последнего turn'a.
        if let prev = audioFileURL {
            try? FileManager.default.removeItem(at: prev)
        }
        audioFile = nil
        audioConverter = nil
        audioFileURL = nil
        recordedAudioURL = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation_\(UUID().uuidString).wav")
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: Self.audioOutputFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
            audioFile = file
            audioFileURL = url
            audioConverter = AVAudioConverter(from: inputFormat, to: Self.audioOutputFormat)
        } catch {
            // Не критично: даже если файл не открылся — распознавание всё
            // равно продолжит работать, мультимодал просто получит nil-аудио
            // и упадёт в текстовый fallback.
            audioFile = nil
            audioConverter = nil
            audioFileURL = nil
        }
    }

    /// Конвертирует пришедший из tap буфер (native float PCM) в int16 16k mono
    /// и пишет в открытый WAV. Ошибки не пробрасываем — распознаванию они не
    /// мешают, максимум мультимодал не получит аудио.
    private func appendBufferToFile(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile, let converter = audioConverter else { return }
        let ratio = Self.audioOutputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: Self.audioOutputFormat,
            frameCapacity: capacity
        ) else { return }
        // Флаг «буфер уже выдан конвертеру» — держим через ссылочный box,
        // чтобы Swift 6 concurrency-checker не ругался на мутацию captured var
        // в @escaping блоке.
        final class ConsumedFlag { var value = false }
        let consumed = ConsumedFlag()
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed.value {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed.value = true
            outStatus.pointee = .haveData
            return buffer
        }
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
        guard convError == nil, status != .error, outBuffer.frameLength > 0 else { return }
        try? file.write(from: outBuffer)
    }

    /// Закрывает WAV-файл и коммитит URL как `recordedAudioURL`. Если запись
    /// была пустой (например, юзер сразу отменил) — файл удаляем и URL
    /// остаётся `nil`.
    private func finalizeAudioCapture() {
        audioConverter = nil
        guard let file = audioFile, let url = audioFileURL else {
            audioFile = nil
            audioFileURL = nil
            return
        }
        // AVAudioFile закрывается автоматически при деаллоке; сбрасываем ссылку.
        audioFile = nil
        let hasFrames = file.length > 0
        audioFileURL = nil
        if hasFrames {
            recordedAudioURL = url
        } else {
            try? FileManager.default.removeItem(at: url)
            recordedAudioURL = nil
        }
    }

    // MARK: - Helpers

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechAuthorizationStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .denied:        .denied
        case .restricted:    .restricted
        case .authorized:    .authorized
        @unknown default:    .notDetermined
        }
    }

    private static func locale(for language: LanguageCode) -> Locale {
        // TODO: если нужен латиноамериканский испанский — переключить на "es-MX" / "es-419".
        switch language {
        case .en: Locale(identifier: "en-US")
        case .es: Locale(identifier: "es-ES")
        }
    }
}
