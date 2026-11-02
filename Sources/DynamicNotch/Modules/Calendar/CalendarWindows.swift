import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - 전체 화면 회의 알림 (M-D-004)

/// 모든 화면을 덮는 회의 알림. Return = 참가, Esc = 닫기, 1분 다시 알림.
final class CalAlertWindows {
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var onJoin: (() -> Void)?
    private var onSnooze: (() -> Void)?
    private var onDismiss: (() -> Void)?

    var isShowing: Bool { !windows.isEmpty }

    func show(_ item: CalItem, preview: Bool, onJoin: (() -> Void)?, onSnooze: (() -> Void)?, onDismiss: @escaping () -> Void) {
        close()
        self.onJoin = onJoin
        self.onSnooze = onSnooze
        self.onDismiss = onDismiss
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for (index, screen) in NSScreen.screens.enumerated() {
            let w = CalAlertWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            let view = CalAlertView(item: item, preview: preview, main: index == 0,
                                    join: onJoin == nil ? nil : { [weak self] in self?.finish(.join) },
                                    snooze: onSnooze == nil ? nil : { [weak self] in self?.finish(.snooze) },
                                    dismiss: { [weak self] in self?.finish(.dismiss) })
            w.contentView = NSHostingView(rootView: view)
            w.setFrame(screen.frame, display: true)
            w.alphaValue = 0
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = reduceMotion ? 0.15 : 0.3
                w.animator().alphaValue = 1
            }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isShowing else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape: self.finish(.dismiss); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if self.onJoin != nil { self.finish(.join) } else { self.finish(.dismiss) }
                return nil
            default: return event
            }
        }
    }

    private enum Outcome { case join, snooze, dismiss }

    private func finish(_ outcome: Outcome) {
        let join = onJoin, snooze = onSnooze, dismiss = onDismiss
        close()
        switch outcome {
        case .join: join?()
        case .snooze: snooze?()
        case .dismiss: dismiss?()
        }
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for w in windows { w.orderOut(nil); w.close() }
        windows.removeAll()
        onJoin = nil
        onSnooze = nil
        onDismiss = nil
    }
}

private final class CalAlertWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct CalAlertView: View {
    let item: CalItem
    let preview: Bool
    /// 버튼은 주 화면에만 크게, 나머지 화면에는 제목만
    let main: Bool
    let join: (() -> Void)?
    let snooze: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 18) {
                if preview {
                    Text(T("미리 보기 · 실제 일정 아님", "Preview · not a real event"))
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Color.yellow))
                }
                HStack(spacing: 10) {
                    Circle().fill(item.color).frame(width: 12, height: 12)
                    Text(item.calendarName).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                }
                Text(item.title)
                    .font(.system(size: main ? 54 : 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 60)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.whenText(item, now: ctx.date))
                        .font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(item.color.opacity(0.95))
                }
                Text(item.timeText).font(.system(size: 17)).foregroundStyle(.white.opacity(0.6))
                if main {
                    HStack(spacing: 14) {
                        if let join {
                            Button(action: join) {
                                Label(T("참가", "Join") + "  ↩", systemImage: "video.fill").frame(minWidth: 140)
                            }
                            .buttonStyle(CalAlertButton(prominent: true, tint: item.color))
                            .help(T("회의 링크 열기 (Return)", "Open the meeting link (Return)"))
                        }
                        if let snooze {
                            Button(action: snooze) { Label(T("1분 뒤 다시", "Snooze 1 min"), systemImage: "clock.arrow.circlepath") }
                                .buttonStyle(CalAlertButton(prominent: false, tint: .white))
                        }
                        Button(action: dismiss) { Text(T("닫기", "Dismiss") + "  esc") }
                            .buttonStyle(CalAlertButton(prominent: false, tint: .white))
                            .help(T("알림 닫기 (Esc)", "Close the alert (Esc)"))
                    }
                    .padding(.top, 10)
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    static func whenText(_ item: CalItem, now: Date) -> String {
        let secs = item.start.timeIntervalSince(now)
        if secs > 0 {
            let m = Int(secs) / 60, s = Int(secs) % 60
            return T("\(m)분 \(s)초 후 시작", "Starts in \(m):\(String(format: "%02d", s))")
        }
        let ago = Int(-secs / 60)
        return ago == 0 ? T("지금 시작", "Starting now") : T("시작 후 \(ago)분 지남", "Started \(ago) min ago")
    }
}

private struct CalAlertButton: ButtonStyle {
    var prominent: Bool
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(prominent ? .white : .white.opacity(0.9))
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(prominent ? tint.opacity(configuration.isPressed ? 0.7 : 1) : Color.white.opacity(configuration.isPressed ? 0.25 : 0.14)))
            .contentShape(Capsule())
    }
}

// MARK: - 메뉴 막대 항목 (M-D-003)

/// "Standup · 12분 후" 메뉴 막대 항목. 누르면 오늘 일정과 캘린더 메뉴가 열린다.
final class CalStatusItem: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let makeMenu: () -> NSMenu
    private var lastTitle: String?
    private var lastDay = -1
    private var lastDateIcon: Bool?

    init(menu: @escaping () -> NSMenu) {
        makeMenu = menu
        super.init()
        let s = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        s.button?.imagePosition = .imageLeading
        s.button?.toolTip = T("다음 일정", "Next event")
        let m = NSMenu()
        m.delegate = self
        s.menu = m
        item = s
        update(title: nil, dateIcon: false)
    }

    func update(title: String?, dateIcon: Bool) {
        guard let button = item?.button else { return }
        let day = Calendar.current.component(.day, from: Date())
        if dateIcon != lastDateIcon || (dateIcon && day != lastDay) {
            button.image = dateIcon ? Self.dateIcon(day) : NSImage(systemSymbolName: "calendar", accessibilityDescription: T("캘린더", "Calendar"))
            lastDay = day
            lastDateIcon = dateIcon
        }
        if title != lastTitle {
            button.title = title.map { " " + $0 } ?? ""
            lastTitle = title
        }
    }

    func remove() {
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for i in makeMenu().items {
            i.menu?.removeItem(i)
            menu.addItem(i)
        }
    }

    /// 오늘 날짜가 들어간 달력 모양 아이콘 (템플릿)
    static func dateIcon(_ day: Int) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1), xRadius: 3, yRadius: 3)
            NSColor.black.setStroke()
            body.lineWidth = 1.3
            body.stroke()
            NSBezierPath(rect: NSRect(x: 1.5, y: rect.height - 4.5, width: rect.width - 3, height: 3.5)).fill()
            let text = "\(day)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5, weight: .bold), .foregroundColor: NSColor.black]
            let ts = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (rect.width - ts.width) / 2, y: 1.6), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = T("캘린더 \(day)일", "Calendar, day \(day)")
        return img
    }
}
