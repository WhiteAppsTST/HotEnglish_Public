import Foundation

/// Owns the hero-video плеер на HomeView: idle-луп выбранной учительницы +
/// периодические случайные «реакции» (talking, flirting, correct/wrong).
///
/// Единая точка правды — teacher, приходит из `user.settings.selectedTeacher`
/// (через `HomeViewModel.teacher`). При смене учителя контроллер
/// пересобирается: cancel loop, swap base video, restart loop.
///
/// Реакции проигрываются каждые `reactionPauseRange` секунд, случайной строго
/// из `reactionStates`. Видео все начинаются/заканчиваются на одном rest-кадре
/// с idle-лупом → переход бесшовный (см. AvatarPlayer).
@MainActor
@Observable
final class HomeAvatarController {

    let player = AvatarPlayer()

    /// Пауза между реакциями (сек). 45–60 — по продуктовому требованию, чтобы
    /// реакции не выглядели навязчиво.
    var reactionPauseRange: ClosedRange<UInt64> = 45...60

    /// Пул реакций для рандомайзера. `.idle` намеренно не входит — это база.
    /// `.listening` тоже нет — оно про активный диалог, а не про пассивный
    /// idle-фон.
    var reactionStates: [TeacherProfile.LessonState] = [
        .talking, .flirting, .correctAnswer, .wrongAnswer
    ]

    private var reactionTask: Task<Void, Never>?
    private var currentTeacher: TeacherProfile?

    /// Настроить (или переключить) под конкретного учителя. Идемпотентно —
    /// повторный вызов с тем же учителем no-op'ит.
    func configure(for teacher: TeacherProfile) {
        guard teacher != currentTeacher else { return }
        currentTeacher = teacher
        reactionTask?.cancel()
        reactionTask = nil

        if let idle = teacher.lessonVideo(.idle) {
            player.setBase(video: idle)
        }
        startReactionLoop(for: teacher)
    }

    /// Остановить всё (background/hide сценарий, если понадобится).
    func stop() {
        reactionTask?.cancel()
        reactionTask = nil
        player.stop()
        currentTeacher = nil
    }

    // MARK: - Loop

    private func startReactionLoop(for teacher: TeacherProfile) {
        let states = reactionStates
        let range = reactionPauseRange
        reactionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let pauseSec = UInt64.random(in: range)
                try? await Task.sleep(nanoseconds: pauseSec * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self else { return }
                // Учителя могли переключить пока спали — тогда loop нужного
                // teacher'а уже отменён, а мы всё равно свой отработаем: но
                // это гонка. Дополнительно проверяем.
                guard self.currentTeacher == teacher else { return }
                let state = states.randomElement() ?? .talking
                if let video = teacher.lessonVideo(state) {
                    self.player.playOnce(video: video)
                }
            }
        }
    }
}
