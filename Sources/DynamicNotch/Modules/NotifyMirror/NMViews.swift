import AppKit
import SwiftUI

/// 시스템 설정 화면 주소
enum NMSystemSettings {
    static let accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    static let fullDisk = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    static func open(_ s: String) { if let url = URL(string: s) { NSWorkspace.shared.open(url) } }

    /// 배너 구조를 실제로 확인한 macOS 버전 (아직 없음 → 이 버전에서 확인되지 않음 표시)
    static let verifiedVersions: [Int] = []
    static var versionNote: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let name = "\(v.majorVersion).\(v.minorVersion)"
        return verifiedVersions.contains(v.majorVersion)
            ? T("macOS \(name)에서 배너 구조 확인됨", "Banner layout verified on macOS \(name)")
            : T("macOS \(name)에서 배너 구조가 실제 배너로 확인되지 않음", "Banner layout not verified on macOS \(name)")
    }

    static func time(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(Calendar.current.isDateInToday(d) ? "jmm" : "MMMdjmm")
        return f.string(from: d)
    }
}

struct NMTab: View {
    let module: NotifyMirrorModule
    @ObservedObject var state: NMState
    @State private var page = 0
    @State private var replyingTo: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if page == 0 { recent } else { centerHistory }
        }
        .foregroundStyle(.white)
        .onAppear {
            state.trusted = AXIsProcessTrusted()
            module.markRead()
        }
    }

    // MARK: 머리

    private var header: some View {
        HStack(spacing: 6) {
            pill(T("최근", "Recent") + (state.unread > 0 ? " \(state.unread)" : ""), selected: page == 0) { page = 0 }
            pill(T("알림 센터 기록", "Notification Center"), selected: page == 1) { page = 1; state.dbStatus = NMDatabase.status() }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: state.trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(state.trusted ? T("손쉬운 사용 켜짐", "Accessibility on") : T("손쉬운 사용 필요", "Accessibility needed"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(state.trusted ? Color.green.opacity(0.9) : Color.orange)
            .accessibilityElement(children: .combine)
        }
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: 최근 (미러링한 알림)

    @ViewBuilder private var recent: some View {
        if state.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(state.items) { item in row(item) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: state.trusted ? "bell" : "bell.slash")
                .font(.system(size: 26)).foregroundStyle(.white.opacity(0.6))
            Text(T("아직 미러링한 알림이 없음", "No mirrored notifications yet"))
                .font(.system(size: 14, weight: .semibold))
            Text(state.trusted
                 ? T("다른 앱의 알림 배너가 뜨면 여기에 모인다.", "Banners from other apps will collect here.")
                 : T("배너를 읽으려면 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 이 앱을 켜야 한다.",
                     "To read banners, turn this app on in System Settings › Privacy & Security › Accessibility."))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            if !state.trusted {
                smallButton(T("손쉬운 사용 설정 열기", "Open Accessibility Settings"), symbol: "gearshape") {
                    NMSystemSettings.open(NMSystemSettings.accessibility)
                }
            }
            Spacer(minLength: 0)
            Text(NMSystemSettings.versionNote)
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ item: NMItem) -> some View {
        let lines = item.lines(module.privacy)
        let isUnread = item.date > Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: "module.\(module.id).lastOpened"))
        return HStack(alignment: .top, spacing: 10) {
            appIcon(item.app)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(lines.0).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(NMSystemSettings.time(item.date))
                        .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                }
                if let second = lines.1 {
                    Text(second).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                }
                if module.canReply(item.id) { replyControls(item) }
                if let status = state.replyStatus[item.id] {
                    Text(status).font(.system(size: 11)).foregroundStyle(status.hasPrefix(T("보냄", "Sent")) ? .green : .orange)
                }
            }
            if isUnread {
                Circle().fill(Color.blue).frame(width: 7, height: 7).padding(.top, 5)
                    .accessibilityLabel(T("읽지 않음", "Unread"))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { module.open(item.id) }
        .help(T("눌러서 열기", "Click to open"))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func replyControls(_ item: NMItem) -> some View {
        if replyingTo == item.id {
            HStack(spacing: 6) {
                TextField(T("답장 입력", "Type a reply"), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .focused($focused)
                    .onSubmit { send(item.id) }
                smallButton(T("보내기", "Send"), symbol: "paperplane.fill") { send(item.id) }
            }
            .padding(.top, 2)
        } else {
            smallButton(T("답장", "Reply"), symbol: "arrowshape.turn.up.left") {
                replyingTo = item.id
                draft = ""
                module.context?.focusInput()
                DispatchQueue.main.async { focused = true }
            }
            .padding(.top, 2)
        }
    }

    private func send(_ id: UUID) {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        module.reply(id, text: text)
        draft = ""
        replyingTo = nil
    }

    private func appIcon(_ name: String) -> some View {
        Group {
            if let icon = NMAppIcons.icon(for: name) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.badge").resizable().scaledToFit().padding(4).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: 알림 센터 기록 (전체 디스크 접근)

    @ViewBuilder private var centerHistory: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(dbStatusText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                Spacer()
                if state.dbStatus == .noFullDiskAccess {
                    smallButton(T("설정 열기", "Open Settings"), symbol: "gearshape") { NMSystemSettings.open(NMSystemSettings.fullDisk) }
                }
                smallButton(state.dbLoading ? T("읽는 중…", "Reading…") : T("불러오기", "Load"), symbol: "arrow.clockwise") {
                    module.loadDatabase()
                }
                .disabled(state.dbLoading)
            }
            if !state.dbBadges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(state.dbBadges.enumerated()), id: \.offset) { _, badge in
                            HStack(spacing: 4) {
                                Text(NMDatabase.appName(badge.0)).lineLimit(1)
                                Text("\(badge.1)").monospacedDigit().padding(.horizontal, 5)
                                    .background(Capsule().fill(Color.red.opacity(0.85)))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                }
            }
            if let message = state.dbMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(state.dbRecords) { rec in
                        let name = NMDatabase.appName(rec.bundleID)
                        let item = NMItem.make(app: name, title: rec.title, subtitle: rec.subtitle, body: rec.body,
                                               date: rec.date ?? Date.distantPast, privacy: module.privacy)
                        let lines = item.lines(module.privacy)
                        HStack(alignment: .top, spacing: 10) {
                            appIcon(name)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(lines.0).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    if let d = rec.date {
                                        Text(NMSystemSettings.time(d)).font(.system(size: 11)).monospacedDigit()
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                                if let s = lines.1 { Text(s).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65)).lineLimit(2) }
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if state.dbRecords.isEmpty, state.dbMessage == nil {
                Spacer(minLength: 0)
                Text(T("알림 센터에 남아 있는 기록과 앱 배지 수를 이 Mac의 알림 DB에서 읽는다. 누를 때만 읽고, 임시 사본은 바로 지운다.",
                       "Reads remaining Notification Center records and app badge counts from this Mac's notification database, only when you press Load. The temporary copy is deleted right away."))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center).multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
        }
    }

    private var dbStatusText: String {
        switch state.dbStatus {
        case .available: return T("알림 DB 읽기 가능 (전체 디스크 접근 있음)", "Notification database readable (Full Disk Access on)")
        case .noFullDiskAccess: return T("전체 디스크 접근이 필요함 (설정 › 개인정보 보호 및 보안 › 전체 디스크 접근)",
                                          "Needs Full Disk Access (Settings › Privacy & Security › Full Disk Access)")
        case .notFound: return T("이 macOS에서 알림 DB를 찾지 못함", "Notification database not found on this macOS")
        }
    }
}

// MARK: - 설정 (설정 도우미 프로세스)

struct NMSettings: View {
    let module: NotifyMirrorModule
    @State private var privacy = 1
    @State private var delivery = "alongside"
    @State private var style = "card"
    @State private var saveHistory = true
    @State private var retention = 7
    @State private var badge = false
    @State private var muted: [String] = []
    @State private var newMute = ""
    @State private var trusted = AXIsProcessTrusted()
    @State private var fullDisk = PermissionsManager.hasFullDiskAccess()

    private var d: ModuleDefaults { ModuleDefaults(module: module.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            permissionRow(T("손쉬운 사용", "Accessibility"), granted: trusted,
                          why: T("배너 읽기·닫기·답장에 필수. 켠 뒤 이 기능을 껐다 켜면 반영된다.",
                                 "Required to read, dismiss and reply to banners. Toggle this feature after granting."),
                          url: NMSystemSettings.accessibility)
            permissionRow(T("전체 디스크 접근", "Full Disk Access"), granted: fullDisk,
                          why: T("'알림 센터 기록' 보기에만 필요. 없으면 이 앱이 직접 미러링한 알림만 보인다. 켠 뒤 앱을 다시 시작해야 할 수 있다.",
                                 "Only for the Notification Center history view. Without it, only banners mirrored by this app are shown. A relaunch may be needed after granting."),
                          url: NMSystemSettings.fullDisk)
            Text(NMSystemSettings.versionNote + T(" — 동작하지 않으면 기능을 끄고 macOS 기본 배너를 쓰세요.", " — if it misbehaves, turn it off and use macOS banners."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(T("공개 범위", "Privacy"), selection: $privacy) {
                ForEach(NMPrivacy.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .onChange(of: privacy) { _, v in d.set(v, "privacy") }
            Text(T("고른 범위를 넘는 글자는 노치에 띄우지도 저장하지도 않는다. 잠금 화면에서는 노치에 띄우지 않는다.",
                   "Text beyond this level is neither shown nor stored. Nothing is shown in the notch while the screen is locked."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(T("전달 방식", "Delivery"), selection: $delivery) {
                Text(T("macOS 배너와 함께", "Alongside macOS banners")).tag("alongside")
                Text(T("노치에만 (macOS 배너 닫기)", "Notch only (dismiss macOS banner)")).tag("notchOnly")
            }
            .onChange(of: delivery) { _, v in d.set(v, "delivery") }
            Text(T("노치에만: 노치에 띄운 뒤에만 배너를 닫고, 닫기 실패나 표시 실패 때는 배너를 그대로 둔다. 답장할 수 있는 배너는 답장할 수 있도록 닫지 않는다.",
                   "Notch only: the banner is dismissed only after the notch shows it; on failure the banner stays. Banners you can reply to stay open so replies still work."))
                .font(.caption).foregroundStyle(.secondary)

            Picker(T("노치 표시", "Notch style"), selection: $style) {
                Text(T("카드 (펼침)", "Card (expanded)")).tag("card")
                Text(T("작게 (앱 이름)", "Compact (app name)")).tag("compact")
            }
            .onChange(of: style) { _, v in d.set(v, "style") }

            Toggle(T("기록 저장 (암호화)", "Save history (encrypted)"), isOn: $saveHistory)
                .onChange(of: saveHistory) { _, v in d.set(v, "saveHistory") }
            Picker(T("보관 기간", "Keep for"), selection: $retention) {
                Text(T("1일", "1 day")).tag(1)
                Text(T("7일", "7 days")).tag(7)
                Text(T("30일", "30 days")).tag(30)
            }
            .onChange(of: retention) { _, v in d.set(v, "retentionDays") }
            Text(T("사본은 AES-GCM으로 암호화하고 키는 이 기기 전용 키체인 항목에 둔다. 기능을 끄면 사본은 휴지통으로, 키는 지운다.",
                   "Copies are encrypted with AES-GCM; the key lives in a this-device-only keychain item. Turning the feature off moves copies to the Trash and deletes the key."))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(T("노치 옆 읽지 않은 개수", "Unread count beside the notch"), isOn: $badge)
                .onChange(of: badge) { _, v in d.set(v, "unreadBadge") }

            VStack(alignment: .leading, spacing: 6) {
                Text(T("음소거한 앱 (노치에 띄우지 않음)", "Muted apps (not shown in the notch)")).font(.subheadline)
                ForEach(muted, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(T("빼기", "Remove")) { muted.removeAll { $0 == name }; d.set(muted, "muted") }
                    }
                }
                HStack {
                    TextField(T("앱 이름 (예: Slack)", "App name (e.g. Slack)"), text: $newMute)
                    Button(T("더하기", "Add")) {
                        let n = newMute.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, !muted.contains(n) else { return }
                        muted.append(n); d.set(muted, "muted"); newMute = ""
                    }
                }
            }

            Button(T("기록 지우기 (휴지통으로)", "Clear history (to Trash)")) {
                d.set(Date().timeIntervalSince1970, "clearRequest")
            }

            Divider()
            Text(T("지원 안 됨", "Not supported")).font(.headline)
            unsupported(T("macOS 배너 위치 바꾸기", "Move macOS banners"),
                        why: T("배너 창 위치를 바꾸는 공개 API가 없다. 손쉬운 사용으로 알림 센터 창을 옮기는 방식은 배너마다 시스템 애니메이션과 다투고, 이 빌드에서 실제로 확인하지 못했다.",
                               "There is no public API to move banner windows. Moving Notification Center windows via Accessibility fights the system animation on every banner and could not be verified in this build."),
                        alternative: T("'노치에만' 방식으로 배너를 닫고 노치에서 보기", "Use 'Notch only' to dismiss banners and read them in the notch"))
            unsupported(T("거는 전화의 카메라 버튼", "Camera button for outgoing calls"),
                        why: T("통화 표시는 기본 '통화' 기능이 그리며, 확장 기능은 그 카드에 버튼을 더할 수 없다.",
                               "The call island is drawn by the built-in Calls feature; modules cannot add buttons to it."),
                        alternative: T("끊기·음소거는 기본 통화 표시에서, 카메라는 FaceTime 창에서", "End and mute from the built-in call island; camera from the FaceTime window"))
            unsupported(T("수신 전화의 연락처 사진", "Contact photo for incoming calls"),
                        why: T("앱 정보(Info.plist)에 연락처 사용 설명이 없어 연락처 권한을 요청할 수 없다. 받기·거절은 기본 '통화' 기능이 맡는다.",
                               "The app's Info.plist has no Contacts usage description, so Contacts access cannot be requested. Answer/decline is handled by the built-in Calls feature."),
                        alternative: T("기본 통화 표시의 이름·번호", "Name or number in the built-in call island"))
        }
        .onAppear {
            privacy = d.int("privacy", default: 1)
            delivery = d.string("delivery", default: "alongside")
            style = d.string("style", default: "card")
            saveHistory = d.bool("saveHistory", default: true)
            retention = d.int("retentionDays", default: 7)
            badge = d.bool("unreadBadge", default: false)
            muted = d.strings("muted", default: [])
            trusted = AXIsProcessTrusted()
            fullDisk = PermissionsManager.hasFullDiskAccess()
        }
    }

    private func permissionRow(_ name: String, granted: Bool, why: String, url: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(name + " — " + (granted ? T("허용됨", "Allowed") : T("필요", "Needed")))
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button(T("설정 열기", "Open Settings")) { NMSystemSettings.open(url) } }
        }
    }

    private func unsupported(_ name: String, why: String, alternative: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.subheadline.weight(.semibold))
            Text(T("이유: ", "Why: ") + why).font(.caption).foregroundStyle(.secondary)
            Text(T("대안: ", "Instead: ") + alternative).font(.caption).foregroundStyle(.secondary)
        }
    }
}
