import AppKit
import EventKit
import Intents
import SwiftUI

/// 카드 한 장에 그릴 값
struct LCContent: Identifiable {
    var id: String
    var symbol: String
    var tint: Color
    var label: String
    var value: String
    var detail: String?
    var available: Bool
}

enum LCContentBuilder {
    static func dateText(_ d: Date, _ template: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: d)
    }

    private static func unavailable(_ card: LCCard, _ symbol: String, _ reason: String) -> LCContent {
        LCContent(id: card.rawValue, symbol: symbol, tint: .gray, label: card.label, value: reason, detail: nil, available: false)
    }

    private static func accessReason(_ a: LCAccess, _ what: String) -> String {
        switch a {
        case .granted: return ""
        case .notDetermined: return T("\(what) 권한 필요 (설정에서 허용)", "\(what) access needed (allow in Settings)")
        case .denied: return T("\(what) 권한 거부됨 (시스템 설정에서 허용)", "\(what) access denied (allow in System Settings)")
        case .unavailable(let why): return why
        }
    }

    /// 카드 내용. `showTitles`가 꺼져 있으면 일정·미리 알림 제목 대신 시간만 쓴다.
    static func content(_ card: LCCard, _ s: LCSnapshot, timers: [LCTimer], showTitles: Bool, now: Date) -> LCContent {
        switch card {
        case .clock:
            return LCContent(id: card.rawValue, symbol: "clock", tint: .white, label: dateText(now, "MMMdEEEE"),
                             value: dateText(now, "jmm"), detail: nil, available: true)
        case .weather:
            guard let w = s.weather else {
                return unavailable(card, "cloud.sun", T("날씨 모듈이 연결되지 않음", "Weather module not connected"))
            }
            return LCContent(id: card.rawValue, symbol: w.symbol, tint: .yellow, label: w.place ?? card.label,
                             value: "\(Int(w.temperature.rounded()))\(w.unit)", detail: w.summary, available: true)
        case .battery:
            guard let b = s.battery else { return unavailable(card, "battery.0percent", T("이 Mac에는 배터리가 없음", "This Mac has no battery")) }
            let symbol = b.isCharging || b.onAC ? "battery.100percent.bolt" : BatteryMonitor.symbol(for: b.percent)
            var detail: String? = nil
            if b.isCharged { detail = T("충전 완료", "Charged") }
            else if b.isCharging {
                detail = T("충전 중", "Charging") + (b.minutesToFull.map { " · " + T("완충까지 \($0 / 60):\(String(format: "%02d", $0 % 60))", "full in \($0 / 60):\(String(format: "%02d", $0 % 60))") } ?? "")
            } else if b.onAC { detail = T("전원 연결됨", "On power adapter") }
            let tint: Color = b.percent < 20 && !b.onAC ? .red : (b.isCharging ? .green : .white)
            return LCContent(id: card.rawValue, symbol: symbol, tint: tint, label: card.label, value: "\(b.percent)%", detail: detail, available: true)
        case .devices:
            guard let first = s.devices.first else {
                return unavailable(card, "headphones", T("배터리를 알려 주는 연결된 기기가 없음", "No connected device reports a battery"))
            }
            let many = s.devices.count > 1
            let value = s.devices.prefix(3).map { "\($0.level)%" }.joined(separator: " · ")
            let label = many ? T("주변기기 \(s.devices.count)대", "\(s.devices.count) devices") : first.name
            let detail = many ? s.devices.prefix(3).map(\.name).joined(separator: " · ") : first.detail
            let low = s.devices.contains { $0.level < 20 }
            return LCContent(id: card.rawValue, symbol: first.symbol, tint: low ? .red : .green, label: label,
                             value: value, detail: detail, available: true)
        case .timer:
            guard let t = timers.first else { return unavailable(card, "timer", T("실행 중인 타이머 없음", "No running timer")) }
            return LCContent(id: card.rawValue, symbol: t.symbol, tint: .orange, label: t.title, value: t.text,
                             detail: timers.count > 1 ? timers.dropFirst().map { "\($0.title) \($0.text)" }.joined(separator: " · ") : nil,
                             available: true)
        case .event:
            guard s.calendarAccess == .granted else { return unavailable(card, "calendar", accessReason(s.calendarAccess, T("캘린더", "Calendar"))) }
            guard let e = s.event else {
                return LCContent(id: card.rawValue, symbol: "calendar", tint: .red, label: card.label,
                                 value: T("24시간 안에 일정 없음", "Nothing in 24 hours"), detail: nil, available: true)
            }
            let time: String
            if e.allDay { time = T("종일", "All day") }
            else if e.start <= now { time = T("진행 중 · ", "Now · ") + dateText(e.end, "jmm") + T("까지", "") }
            else { time = dateText(e.start, "jmm") + "–" + dateText(e.end, "jmm") }
            return LCContent(id: card.rawValue, symbol: "calendar", tint: .red, label: card.label,
                             value: showTitles && !e.title.isEmpty ? e.title : time,
                             detail: showTitles ? time : T("제목 숨김", "Title hidden"), available: true)
        case .reminders:
            guard s.remindersAccess == .granted else {
                return unavailable(card, "checklist", accessReason(s.remindersAccess, T("미리 알림", "Reminders")))
            }
            guard let first = s.reminders.first else {
                return LCContent(id: card.rawValue, symbol: "checklist", tint: .orange, label: card.label,
                                 value: T("오늘 할 일 없음", "Nothing due"), detail: nil, available: true)
            }
            let due = first.due.map { dateText($0, "jmm") }
            return LCContent(id: card.rawValue, symbol: "checklist", tint: .orange, label: card.label,
                             value: T("\(s.reminders.count)개", "\(s.reminders.count) due"),
                             detail: showTitles ? first.title : (due.map { T("다음 ", "Next ") + $0 } ?? T("제목 숨김", "Title hidden")),
                             available: true)
        case .focus:
            guard s.focusAccess == .granted else {
                return unavailable(card, "moon", accessReason(s.focusAccess, T("집중 모드 상태", "Focus status")))
            }
            guard let f = s.focus else {
                return LCContent(id: card.rawValue, symbol: "moon", tint: .white.opacity(0.7), label: card.label,
                                 value: T("꺼짐", "Off"), detail: nil, available: true)
            }
            return LCContent(id: card.rawValue, symbol: f.symbol, tint: f.tint, label: card.label, value: f.name, detail: nil, available: true)
        }
    }
}

/// 카드 한 장 (잠금 화면에서는 유리 배경, 노치 탭 미리보기에서는 옅은 배경)
struct LCCardView: View {
    let content: LCContent
    var glass: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(content.tint.opacity(0.22))
                Image(systemName: content.symbol).font(.island(.callout, .semibold)).foregroundStyle(content.tint)
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.label).font(.island(.footnote)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                if content.available {
                    Text(content.value)
                        .font(.island(.title3, .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let d = content.detail {
                        Text(d).font(.island(.caption)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                } else {
                    Text(content.value).font(.island(.caption)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: LCLayout.cardSize.width, height: LCLayout.cardSize.height)
        .foregroundStyle(.white)
        .background(background)
        .opacity(content.available ? 1 : 0.6)
        .help(content.available ? content.label : content.value)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if glass {
            VisualEffectBlur().clipShape(shape).overlay(shape.strokeBorder(Color.white.opacity(0.12)))
        } else {
            shape.fill(Color.white.opacity(0.08))
        }
    }
}

/// 한 줄 모양
struct LCStripView: View {
    let contents: [LCContent]
    var glass: Bool

    var body: some View {
        HStack(spacing: 14) {
            ForEach(contents) { c in
                HStack(spacing: 5) {
                    Image(systemName: c.symbol).foregroundStyle(c.tint).accessibilityHidden(true)
                    Text(c.value).font(.island(.subhead, .semibold)).monospacedDigit().lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(c.label + " " + c.value)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: LCLayout.stripHeight)
        .foregroundStyle(.white)
        .background {
            if glass {
                VisualEffectBlur().clipShape(Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
            } else {
                Capsule().fill(Color.white.opacity(0.08))
            }
        }
    }
}

/// 잠금 화면에 올리는 카드 묶음. 값이 있는 카드만 보이고, 자리에 맞게 정한 수까지만 그린다.
struct LCStackView: View {
    @ObservedObject var data: LCDataModel
    @ObservedObject var center: ActivityCenter
    let cards: [LCCard]
    let style: LCStyle
    let showTitles: Bool
    let maxCount: Int
    let bottomAligned: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let timers = LCDataModel.timers(center)
            let contents = cards.map { LCContentBuilder.content($0, data.snapshot, timers: timers, showTitles: showTitles, now: ctx.date) }
                .filter(\.available).prefix(maxCount)
            Group {
                if style == .strip {
                    LCStripView(contents: Array(contents), glass: true)
                } else {
                    VStack(spacing: LCLayout.spacing) {
                        ForEach(Array(contents)) { LCCardView(content: $0, glass: true) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bottomAligned ? .bottomLeading : .topLeading)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 탭 상태
final class LCStatus: ObservableObject {
    @Published var message: String?
    @Published var previewing = false
}

// MARK: - 노치 탭

struct LCTab: View {
    let module: LockCardsModule
    @ObservedObject var data: LCDataModel
    @ObservedObject var status: LCStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: module.stateSymbol).foregroundStyle(module.stateTint)
                Text(module.stateText).font(.island(.footnote)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                Spacer()
                button(status.previewing ? T("미리보는 중", "Previewing") : T("배치 미리보기", "Preview layout"), symbol: "rectangle.dashed") {
                    module.previewOnDesktop()
                }
                .disabled(status.previewing)
                button(T("진단 복사", "Copy diagnostics"), symbol: "doc.on.doc") { module.copyDiagnostics() }
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let timers = LCDataModel.timers(module.context?.center)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.fixed(LCLayout.cardSize.width), spacing: 10),
                                        GridItem(.fixed(LCLayout.cardSize.width))], spacing: 8) {
                        ForEach(module.cards) { card in
                            LCCardView(content: LCContentBuilder.content(card, data.snapshot, timers: timers,
                                                                         showTitles: module.showTitles, now: ctx.date), glass: false)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                if let m = status.message {
                    Text(m).foregroundStyle(.orange)
                } else {
                    Text(T("얼굴 인식 잠금 해제: 지원 안 함 (설정에 이유)", "Face Unlock: not supported (reason in Settings)"))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .font(.island(.caption)).lineLimit(1)
        }
        .foregroundStyle(.white)
        .onAppear { module.refreshData() }
    }

    private func button(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.island(.footnote, .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - 설정 (설정 도우미 프로세스)

struct LCSettings: View {
    let module: LockCardsModule
    @State private var onLock = false
    @State private var placement = LCPlacement.leftMiddle.rawValue
    @State private var style = LCStyle.cards.rawValue
    @State private var cards: Set<String> = []
    @State private var showTitles = false
    @State private var calendar = LCDataModel.access(EKEventStore.authorizationStatus(for: .event))
    @State private var focus = INFocusStatusCenter.default.authorizationStatus

    private var d: ModuleDefaults { ModuleDefaults(module: module.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(T("잠금 화면에 카드 표시", "Show cards on the lock screen"), isOn: $onLock)
                .onChange(of: onLock) { _, v in d.set(v, "onLockScreen") }
                .disabled(!SkyLight.available)
            Text(SkyLight.available
                 ? T("이미 로그인한 세션의 잠금 화면(화면 잠금·화면 보호기·잠자기 복귀)에만 보인다. 로그인 창, 재시동 뒤 첫 로그인, FileVault 화면에는 보이지 않는다. 카드는 클릭을 받지 않아 눌러도 암호 칸에 그대로 입력할 수 있고, 사진·이름·암호 칸·Touch ID 안내와 겹치는 자리에는 놓지 않는다.",
                     "Shown only on the lock screen of a session you are logged into (screen lock, screen saver, wake). Never on the login window, the first login after restart or the FileVault screen. Cards ignore clicks so you can type your password right away, and they are never placed over the picture, name, password field or Touch ID hint.")
                 : T("지원 안 됨: 잠금 화면 위에 창을 올리는 비공개 SkyLight 기능을 이 macOS에서 찾지 못함. 대안: 노치의 잠금 표시와 음악 카드.",
                     "Not supported: the private SkyLight calls that place windows above the lock screen were not found on this macOS. Instead: the notch lock indicator and media card."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(T("위치", "Position"), selection: $placement) {
                ForEach(LCPlacement.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: placement) { _, v in d.set(v, "placement") }
            Picker(T("모양", "Layout"), selection: $style) {
                ForEach(LCStyle.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: style) { _, v in d.set(v, "style") }

            VStack(alignment: .leading, spacing: 4) {
                Text(T("카드", "Cards")).font(.subheadline)
                ForEach(LCCard.allCases) { card in
                    Toggle(card.label, isOn: Binding(
                        get: { cards.contains(card.rawValue) },
                        set: { on in
                            if on { cards.insert(card.rawValue) } else { cards.remove(card.rawValue) }
                            d.set(LCCard.allCases.map(\.rawValue).filter { cards.contains($0) }, "cards")
                        }))
                }
                Text(T("잠금 화면에는 값이 있는 카드만 보인다. 화면이 좁아 다 못 놓으면 아래 카드부터 뺀다.",
                       "Only cards with data appear on the lock screen. If the screen is too small, cards are dropped from the bottom."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle(T("일정·미리 알림 제목 보이기", "Show event and reminder titles"), isOn: $showTitles)
                .onChange(of: showTitles) { _, v in d.set(v, "showTitles") }
            Text(T("기본은 숨김: 잠금 화면에는 시간만 보인다.", "Hidden by default: only times appear on the lock screen."))
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            Text(T("데이터 연결", "Data")).font(.headline)
            HStack {
                Text(T("캘린더: ", "Calendar: ") + accessLabel(calendar))
                Spacer()
                if calendar == .notDetermined {
                    Button(T("캘린더 허용", "Allow Calendar")) {
                        LCDataModel.requestCalendar { calendar = LCDataModel.access(EKEventStore.authorizationStatus(for: .event)) }
                    }
                }
            }
            Text(T("미리 알림: ", "Reminders: ") + accessLabel(LCDataModel.remindersAccess()))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(T("집중 모드 상태: ", "Focus status: ")
                     + (PermissionsManager.hasFullDiskAccess() ? T("전체 디스크 접근으로 모드 이름까지", "Mode name via Full Disk Access")
                        : (focus == .authorized ? T("켜짐·꺼짐만", "On/off only") : T("권한 필요", "Needs access"))))
                Spacer()
                if focus == .notDetermined, !PermissionsManager.hasFullDiskAccess() {
                    Button(T("허용", "Allow")) {
                        INFocusStatusCenter.default.requestAuthorization { s in DispatchQueue.main.async { focus = s } }
                    }
                }
            }
            Text(T("날씨: ", "Weather: ") + (LockCardHooks.weather == nil ? T("날씨 모듈과 연결되면 보인다 (아직 연결 안 됨)", "Shown once the weather module is connected (not connected yet)") : T("연결됨", "Connected")))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("타이머: 노치에서 실행 중인 타이머·스톱워치·뽀모도로를 그대로 보여 준다.", "Timer: mirrors the timer, stopwatch or pomodoro running in the notch."))
                .font(.caption).foregroundStyle(.secondary)

            Divider()
            faceUnlock
        }
        .onAppear {
            onLock = d.bool("onLockScreen", default: false)
            placement = d.string("placement", default: LCPlacement.leftMiddle.rawValue)
            style = d.string("style", default: LCStyle.cards.rawValue)
            cards = Set(d.strings("cards", default: LCCard.defaults.map(\.rawValue)))
            showTitles = d.bool("showTitles", default: false)
        }
    }

    private func accessLabel(_ a: LCAccess) -> String {
        switch a {
        case .granted: return T("허용됨", "Allowed")
        case .notDetermined: return T("아직 묻지 않음", "Not requested")
        case .denied: return T("거부됨 (시스템 설정 › 개인정보 보호 및 보안에서 허용)", "Denied (allow in System Settings › Privacy & Security)")
        case .unavailable(let why): return T("지원 안 됨 — ", "Not supported — ") + why
        }
    }

    /// 얼굴 인식 잠금 해제 (M-J-030–032): 보류 이유와 대안
    private var faceUnlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(T("얼굴 인식 잠금 해제 — 지원 안 함", "Face Unlock — not supported")).font(.headline)
            Text(T("이유: macOS의 Vision은 얼굴 위치·윤곽만 찾고, 이 얼굴이 등록한 사람인지 가리는 기기 내 인식 기능을 주지 않는다. 얼굴 '감지'만으로 풀면 아무 얼굴(사진 포함)에나 풀린다. 또 로그인 암호를 저장했다가 잠금 화면에 대신 입력하는 방식은 암호 유출·오입력 위험이 커서 만들지 않았다.",
                   "Why: Vision on macOS finds faces and landmarks but offers no on-device check that a face belongs to the enrolled person. Unlocking on detection alone would unlock for any face, photos included. Storing the login password and typing it into the lock screen was also left out because of the leak and mistyping risk."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("어떤 방식이든 FileVault 사전 부팅 화면, 재시동 뒤 첫 로그인, 로그아웃 상태의 로그인 창에서는 앱이 실행되지 않거나 다른 세션이라 동작할 수 없다.",
                   "In any design, the FileVault pre-boot screen, the first login after restart and the logged-out login window cannot work, because the app is not running there or it is a different session."))
                .font(.caption).foregroundStyle(.secondary)
            Text(T("대안: Touch ID, Apple Watch로 잠금 해제(시스템 설정 › Touch ID 및 암호).",
                   "Instead: Touch ID or unlock with Apple Watch (System Settings › Touch ID & Password)."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
