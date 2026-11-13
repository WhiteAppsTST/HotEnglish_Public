import SwiftUI

/// Данные для sheet-а «Message from teacher», который открывается когда юзер
/// заходит в приложение по пушу об уходе (см. Figma 373:3287).
///
/// TODO: заменить на реальные данные с бэка/пуш-payload.
nonisolated
struct AwayMessageData: Identifiable, Hashable {
    let id: String
    let teacher: TeacherProfile
    /// Прямая речь учительницы (в кавычках оригинал в Figma).
    let quote: String
    /// Сколько сердец у неё сейчас (после потери, если она была).
    let hearts: Int
    /// Текущий уровень отношений (LV N).
    let level: Int
    /// Текст-фидбек под сердцами (что случится дальше).
    let advice: String
}

extension AwayMessageData {
    /// Мок под Figma 373:3287.
    static let mock = AwayMessageData(
        id: "mock",
        teacher: .emma,
        quote: "“I got used to you being around. Then you weren't.”",
        hearts: 3,
        level: 3,
        advice: "One lesson today and she warms back up. Two more quiet days and she drops another level."
    )

    /// Собрать `AwayMessageData` из apsInfo (userInfo пуш-нотификации от
    /// Apphud). Ждём кастомные ключи, заданные в Apphud Rule → Custom
    /// attributes (см. `AppDelegate.userNotificationCenter`):
    ///   type   = "away"                       ← обязательно, иначе nil
    ///   quote  = "«прямая речь учительницы»"
    ///   hearts = 0…5           (число или строка)
    ///   level  = 1…5           (число или строка)
    ///   advice = "текст под сердцами"
    ///   teacher = "emma" | "yuki" | "sofia"
    ///   rule_id = "..."        ← Apphud подставляет сам
    /// Значения отсутствующие/битые заменяются мягкими дефолтами, чтобы
    /// sheet всё равно открылся — юзер лучше увидит слегка обобщённый
    /// текст, чем ничего.
    static func fromApsInfo(_ userInfo: [AnyHashable: Any]) -> AwayMessageData? {
        // Поддерживаем оба варианта: атрибуты в корне userInfo (стандарт
        // Apphud) или в вложенном "custom_data"/"payload" (некоторые
        // маркетинговые кампании прикладывают их именно так).
        let root = flattenApsUserInfo(userInfo)
        guard readString(root["type"])?.lowercased() == "away" else { return nil }

        let teacherRaw = readString(root["teacher"])?.lowercased() ?? ""
        let teacher = TeacherProfile(rawValue: teacherRaw) ?? .emma

        let quote = readString(root["quote"])
            ?? "“I keep thinking about what you said yesterday.”"
        let advice = readString(root["advice"])
            ?? "One lesson today and she warms back up. Two more quiet days and she drops another level."

        let hearts = clamp(readInt(root["hearts"]) ?? 3, min: 0, max: 5)
        let level  = clamp(readInt(root["level"])  ?? 1, min: 1, max: 5)

        // id даёт идемпотентность: если Apphud кинул пуш повторно (то же
        // rule_id), sheet не переоткроется — SwiftUI `.sheet(item:)`
        // сравнивает Identifiable по id.
        let id = readString(root["rule_id"])
            ?? readString(root["id"])
            ?? "away_\(Int(Date().timeIntervalSince1970))"

        return AwayMessageData(
            id: id, teacher: teacher, quote: quote,
            hearts: hearts, level: level, advice: advice
        )
    }

    /// Разворачивает Apphud/маркетинговые payload-вложенности в плоский
    /// [String: Any], проверяя корень + `payload` + `custom_data`.
    private static func flattenApsUserInfo(_ info: [AnyHashable: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in info { if let s = k as? String { out[s] = v } }
        for nested in ["payload", "custom_data", "data"] {
            if let dict = out[nested] as? [String: Any] {
                for (k, v) in dict where out[k] == nil { out[k] = v }
            }
        }
        return out
    }

    private static func readString(_ v: Any?) -> String? {
        if let s = v as? String, !s.isEmpty { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    private static func readInt(_ v: Any?) -> Int? {
        if let n = v as? Int    { return n }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) }
        return nil
    }

    private static func clamp(_ v: Int, min lo: Int, max hi: Int) -> Int {
        Swift.min(hi, Swift.max(lo, v))
    }
}

/// Имя канала NotificationCenter: `AppDelegate` публикует туда
/// декодированный `AwayMessageData`, а `HomeView.onReceive` подписывается
/// и вызывает `homeVM.presentAwayMessage(_:)`. Через object передаём
/// саму модель — SwiftUI-мир не имеет прямого доступа к AppDelegate.
extension Notification.Name {
    static let awayMessageReceived = Notification.Name("app.awayMessageReceived")
}

/// Sheet «Message from Emma» (Figma 373:3287). Открывается когда юзер входит в
/// приложение по пушу об отсутствии. Пиксель-перфект по REST-tree.
struct AwayMessageSheet: View {
    let data: AwayMessageData
    let onWinBack: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            grabber
                .padding(.top, 8)
                .padding(.bottom, 20)

            avatar
                .padding(.bottom, 14)

            kicker
                .padding(.bottom, 10)

            quoteText
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            affinityCard
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            winBackButton
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            notNowButton
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#19191D"))
        .presentationBackground(Color(hex: "#19191D"))
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Subviews
private extension AwayMessageSheet {

    /// Figma «Grabber» 40×5 cr=3 #9A9AA3.
    var grabber: some View {
        Capsule()
            .fill(Color(hex: "#9A9AA3"))
            .frame(width: 40, height: 5)
    }

    /// Figma «Avatar» 52×52 cr=26.
    var avatar: some View {
        Image(data.teacher.avatarImageName)
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(Circle())
    }

    /// Figma «MESSAGE FROM EMMA» 13pt semibold #8C99B2, tracked.
    var kicker: some View {
        Text("MESSAGE FROM \(data.teacher.name.uppercased())")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(hex: "#8C99B2"))
            .tracking(1.5)
    }

    /// Figma quote 22pt bold white multiline center.
    var quoteText: some View {
        Text(data.quote)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Figma «Affinity» card 353×97 bg #0B0B0D cr=16.
    var affinityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                heartsRow
                Spacer(minLength: 0)
                levelPill
            }

            Text(data.advice)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#0B0B0D")))
    }

    /// 5 сердец 13pt: заполненные pink до `hearts`, остальные пустые (lost).
    var heartsRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < data.hearts ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(i < data.hearts ? Color.lsPink : Color.white.opacity(0.35))
            }
        }
    }

    /// Figma «Loss» pill 42×22 cr=10 bg #8C99B2@35%, "LV N" 13/semibold white.
    var levelPill: some View {
        Text("LV \(data.level)")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#8C99B2").opacity(0.35))
            )
    }

    /// Figma primary button 353×54 pink cr=27, text 17/semibold white.
    var winBackButton: some View {
        Button {
            onWinBack()
        } label: {
            Text("Win her back — 5 min")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Capsule().fill(Color.lsPink))
        }
        .buttonStyle(.plain)
    }

    /// Figma «Not now» 14pt regular #9A9AA3.
    var notNowButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Not now")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(hex: "#9A9AA3"))
                .frame(maxWidth: .infinity)
                .frame(height: 20)
        }
        .buttonStyle(.plain)
    }
}
