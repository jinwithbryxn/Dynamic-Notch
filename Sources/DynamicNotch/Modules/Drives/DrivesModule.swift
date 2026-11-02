import AppKit
import DiskArbitration
import SwiftUI

/// 외장 드라이브·USB와 디스크 이미지: 연결 알림, 꺼낼 수 있는 볼륨 목록, 안전한 꺼내기,
/// 디스크 이미지(.dmg) 안 앱을 사용자가 누르면 응용 프로그램 폴더로 복사.
/// 연결 감시(백그라운드)를 하므로 기본은 꺼짐. 꺼내기·복사는 사용자가 누를 때만 한다.
final class DrivesModule: NotchModule {
    let id = "drives"
    var title: String { T("드라이브", "Drives") }
    let symbol = "externaldrive"
    let enabledByDefault = false

    let store = DRVStore(module: "drives")

    func start(context: ModuleContext) { store.start(context) }
    func stop() { store.stop() }

    func tabView() -> AnyView? { AnyView(DRVTab(store: store)) }
    var tabContentSize: CGSize {
        let n = CGFloat(max(1, store.listed.count))
        return CGSize(width: 460, height: min(280, max(150, 46 + n * 52)))
    }

    func paletteActions() -> [PaletteAction] {
        store.refresh()
        let list = store.listed
        guard !list.isEmpty else { return [] }
        let keywords = ["eject", "꺼내기", "usb", "드라이브", "drive", "unmount", "dmg", "disk"]
        var actions = [PaletteAction(id: "drives.ejectAll", title: T("모두 꺼내기", "Eject all"),
                                     subtitle: T("외장 드라이브·디스크 이미지 \(list.count)개", "\(list.count) drives and disk images"),
                                     symbol: "eject.fill", keywords: keywords, run: { [weak self] in self?.store.ejectAll() })]
        for v in list {
            actions.append(PaletteAction(id: "drives.eject.\(v.id)", title: T("\(v.name) 꺼내기", "Eject \(v.name)"),
                                         subtitle: v.kind.label, symbol: "eject", keywords: keywords + [v.name],
                                         run: { [weak self] in self?.store.eject(v) }))
        }
        return actions
    }

    func settingsView() -> AnyView? { AnyView(DRVSettings(defaults: ModuleDefaults(module: id))) }

    func selfTest() -> [String] {
        var lines: [String] = []
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        lines.append("DiskArbitration session: \(DASessionCreate(kCFAllocatorDefault) != nil ? "ok" : "unavailable")")
        for u in urls {
            let c = DRVClassifier.classify(u)
            let da = DRVClassifier.diskInfo(u)
            lines.append("\(u.path): \(c.kind?.rawValue ?? "excluded") (\(c.reason)) model=\(da.model ?? "-") protocol=\(da.proto ?? "-")")
        }
        let listed = DRVClassifier.volumes(includeImages: true)
        lines.append("listed ejectable volumes: \(listed.count) \(listed.map(\.name))")
        lines.append("no eject or copy performed")
        return lines
    }
}

// MARK: - 볼륨 분류

struct DRVVolume: Identifiable, Equatable {
    enum Kind: String {
        case external, diskImage
        var label: String { self == .external ? T("외장 드라이브", "External drive") : T("디스크 이미지", "Disk image") }
    }
    let url: URL
    let name: String
    let kind: Kind
    let total: Int64?
    let free: Int64?
    /// 디스크 이미지 맨 위의 앱·설치 프로그램
    let apps: [URL]
    let installers: [URL]
    var id: String { url.path }
}

enum DRVClassifier {
    private static let keys: Set<URLResourceKey> = [
        .volumeLocalizedNameKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
        .volumeIsBrowsableKey, .volumeIsRootFileSystemKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    ]

    /// DiskArbitration 설명의 기기 모델·프로토콜 ("Disk Image"면 디스크 이미지)
    static func diskInfo(_ url: URL) -> (model: String?, proto: String?) {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let desc = DADiskCopyDescription(disk) as? [CFString: Any] else { return (nil, nil) }
        let model = (desc[kDADiskDescriptionDeviceModelKey] as? String)?.trimmingCharacters(in: .whitespaces)
        let proto = desc[kDADiskDescriptionDeviceProtocolKey] as? String
        return (model, proto)
    }

    /// 목록에 넣을 종류와 이유. 내장·네트워크·숨김·Time Machine 스냅샷·시동 디스크는 뺀다.
    static func classify(_ url: URL) -> (kind: DRVVolume.Kind?, reason: String) {
        guard let v = try? url.resourceValues(forKeys: keys) else { return (nil, "no info") }
        let path = url.path
        if v.volumeIsRootFileSystem == true { return (nil, "startup disk") }
        if path.contains("/.timemachine") || path.contains("com.apple.TimeMachine") { return (nil, "Time Machine") }
        if v.volumeIsLocal == false { return (nil, "network share") }
        if v.volumeIsBrowsable == false { return (nil, "hidden") }
        if !path.hasPrefix("/Volumes/") { return (nil, "system volume") }
        let da = diskInfo(url)
        if da.model == "Disk Image" || da.proto == "Disk Image" || da.proto == "Virtual Interface" { return (.diskImage, "disk image") }
        let ejectable = v.volumeIsEjectable == true || v.volumeIsRemovable == true
        if v.volumeIsInternal == true && !ejectable { return (nil, "internal") }
        if ejectable || v.volumeIsInternal == false { return (.external, "ejectable") }
        return (nil, "not ejectable")
    }

    static func volume(_ url: URL) -> DRVVolume? {
        guard let kind = classify(url).kind, let v = try? url.resourceValues(forKeys: keys) else { return nil }
        var apps: [URL] = [], installers: [URL] = []
        if kind == .diskImage {
            // 맨 위 단계만 본다 (깊이 뒤지지 않음)
            let top = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            apps = top.filter { $0.pathExtension.lowercased() == "app" }
            installers = top.filter { ["pkg", "mpkg"].contains($0.pathExtension.lowercased()) }
        }
        return DRVVolume(url: url, name: v.volumeLocalizedName ?? url.lastPathComponent, kind: kind,
                         total: v.volumeTotalCapacity.map(Int64.init), free: v.volumeAvailableCapacity.map(Int64.init),
                         apps: apps, installers: installers)
    }

    static func volumes(includeImages: Bool) -> [DRVVolume] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap(volume).filter { includeImages || $0.kind == .external }
    }
}

// MARK: - 상태

final class DRVStore: ObservableObject {
    @Published private(set) var listed: [DRVVolume] = []
    @Published private(set) var busy: Set<String> = []      // 꺼내는 중인 볼륨·복사 중인 앱 경로
    @Published private(set) var message: String?

    private let moduleID: String
    private var context: ModuleContext?
    private var observers: [NSObjectProtocol] = []
    private let queue = DispatchQueue(label: "dmn.drives", qos: .userInitiated)

    init(module: String) { moduleID = module }

    private var defaults: ModuleDefaults { ModuleDefaults(module: moduleID) }
    var notifyMount: Bool { defaults.bool("notifyMount", default: true) }
    var offerInstall: Bool { defaults.bool("offerInstall", default: true) }
    var showImages: Bool { defaults.bool("showImages", default: true) }

    func start(_ context: ModuleContext) {
        self.context = context
        guard observers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            self?.mounted(note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)
        })
        for name in [NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.forEach { nc.removeObserver($0) }
        observers.removeAll()
        context = nil
    }

    func refresh() {
        let list = DRVClassifier.volumes(includeImages: showImages)
        if list != listed { listed = list }
    }

    private func mounted(_ url: URL?) {
        refresh()
        guard let url, let vol = DRVClassifier.volume(url) else { return }
        switch vol.kind {
        case .external:
            guard notifyMount else { return }
            post(T("\(vol.name) 연결됨", "\(vol.name) connected"), capacityText(vol), symbol: "externaldrive.fill", duration: 6,
                 actions: [ActivityAction(id: "drv.eject", title: T("꺼내기", "Eject"), run: { [weak self] in self?.eject(vol) })])
        case .diskImage:
            guard offerInstall else { return }
            if let app = vol.apps.first {
                let name = app.deletingPathExtension().lastPathComponent
                post(T("\(name) 설치할까요?", "Install \(name)?"), T("응용 프로그램 폴더로 복사", "Copy to Applications"),
                     symbol: "square.and.arrow.down", duration: 10,
                     actions: [ActivityAction(id: "drv.install", title: T("복사", "Copy"), role: .primary, run: { [weak self] in self?.install(app, from: vol) }),
                               ActivityAction(id: "drv.eject", title: T("꺼내기", "Eject"), run: { [weak self] in self?.eject(vol) })])
            } else if let pkg = vol.installers.first {
                post(T("설치 프로그램이 들어 있음", "Installer found"), pkg.lastPathComponent, symbol: "shippingbox", duration: 8,
                     actions: [ActivityAction(id: "drv.pkg", title: T("열기", "Open"), run: { NSWorkspace.shared.open(pkg) })])
            }
        }
    }

    // MARK: 꺼내기

    func eject(_ vol: DRVVolume) {
        guard !busy.contains(vol.id) else { return }
        busy.insert(vol.id)
        message = nil
        queue.async { [weak self] in
            var failure: Error?
            do { try NSWorkspace.shared.unmountAndEjectDevice(at: vol.url) } catch { failure = error }
            DispatchQueue.main.async { self?.ejected(vol, failure) }
        }
    }

    func ejectAll() {
        refresh()
        listed.forEach(eject)
    }

    private func ejected(_ vol: DRVVolume, _ failure: Error?) {
        busy.remove(vol.id)
        refresh()
        if let failure {
            let reason = (failure as NSError).localizedFailureReason ?? failure.localizedDescription
            message = T("\(vol.name): 꺼낼 수 없음 · \(reason)", "\(vol.name): couldn't eject · \(reason)")
            post(T("\(vol.name) 꺼낼 수 없음", "Couldn't eject \(vol.name)"), reason, symbol: "exclamationmark.triangle.fill", tint: .orange, duration: 6)
        } else {
            // 언마운트·꺼내기가 실제로 끝난 뒤에만 알린다
            message = nil
            let title = vol.kind == .external ? T("분리해도 됨", "Safe to disconnect") : T("꺼냄", "Ejected")
            post(title, vol.name, symbol: "checkmark.circle.fill", tint: .green, duration: 4)
        }
    }

    // MARK: 디스크 이미지 앱 복사 (사용자가 누를 때만, 덮어쓰지 않음)

    func install(_ app: URL, from vol: DRVVolume) {
        let dest = URL(fileURLWithPath: "/Applications", isDirectory: true).appendingPathComponent(app.lastPathComponent)
        let name = app.deletingPathExtension().lastPathComponent
        if FAKit.exists(dest) {
            post(T("이미 응용 프로그램 폴더에 있음", "Already in Applications"), name, symbol: "info.circle", duration: 6,
                 actions: [ActivityAction(id: "drv.show", title: T("Finder에서 보기", "Show in Finder"), run: { FAKit.reveal([dest]) })])
            return
        }
        guard !busy.contains(app.path) else { return }
        busy.insert(app.path)
        post(T("\(name) 복사 중", "Copying \(name)"), T("응용 프로그램 폴더로", "To Applications"), symbol: "square.and.arrow.down",
             value: .spinner, duration: 600)
        queue.async { [weak self] in
            var failure: Error?
            do { try FileManager.default.copyItem(at: app, to: dest) } catch { failure = error }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy.remove(app.path)
                if let failure {
                    self.post(T("복사하지 못함", "Couldn't copy"), failure.localizedDescription, symbol: "exclamationmark.triangle.fill",
                              tint: .orange, duration: 8,
                              actions: [ActivityAction(id: "drv.show", title: T("직접 옮기기", "Move it yourself"), run: { FAKit.reveal([app]) })])
                } else {
                    self.post(T("\(name) 설치됨", "\(name) installed"), T("응용 프로그램 폴더", "Applications"), symbol: "checkmark.circle.fill",
                              tint: .green, duration: 8,
                              actions: [ActivityAction(id: "drv.open", title: T("열기", "Open"), role: .primary,
                                                       run: { NSWorkspace.shared.openApplication(at: dest, configuration: .init()) }),
                                        ActivityAction(id: "drv.eject", title: T("이미지 꺼내기", "Eject image"), run: { [weak self] in self?.eject(vol) })])
                }
            }
        }
    }

    func capacityText(_ v: DRVVolume) -> String {
        guard let total = v.total else { return v.kind.label }
        if let free = v.free { return T("\(FAKit.bytes(total)) 중 \(FAKit.bytes(free)) 남음", "\(FAKit.bytes(free)) free of \(FAKit.bytes(total))") }
        return FAKit.bytes(total)
    }

    private func post(_ title: String, _ subtitle: String?, symbol: String, tint: Color = .white, value: ActivityValue = .none,
                      duration: TimeInterval, actions: [ActivityAction] = []) {
        context?.center.post(NotchActivity(kind: .notice, priority: ActivityPriority.info, presentation: .detail, duration: duration,
                                           symbol: symbol, tint: tint, value: value, title: title, subtitle: subtitle,
                                           moduleTab: moduleID, actions: actions))
    }
}

// MARK: - 탭 화면

private struct DRVTab: View {
    @ObservedObject var store: DRVStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(T("외장 드라이브·디스크 이미지", "Drives & disk images")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(FAPillStyle()).help(T("새로 고침", "Refresh")).accessibilityLabel(T("새로 고침", "Refresh"))
                Button { store.ejectAll() } label: { Label(T("모두 꺼내기", "Eject all"), systemImage: "eject.fill") }
                    .buttonStyle(FAPillStyle()).disabled(store.listed.isEmpty)
                    .help(T("목록의 모든 볼륨을 꺼냄", "Eject every listed volume"))
            }
            if store.listed.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "externaldrive").font(.system(size: 24, weight: .light))
                    Text(T("연결된 외장 드라이브가 없음", "No external drives connected")).font(.system(size: 12, weight: .medium))
                    Text(T("USB·SD 카드·디스크 이미지를 연결하면 여기에 보임", "USB drives, SD cards and disk images show up here"))
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) { ForEach(store.listed) { row($0) } }
                }
            }
            if let m = store.message {
                Text(m).font(.system(size: 10.5)).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .onAppear { store.refresh() }
    }

    private func row(_ v: DRVVolume) -> some View {
        HStack(spacing: 8) {
            FAFileIcon(url: v.url, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(v.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text(v.kind.label).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5))
                }
                if let total = v.total, total > 0, let free = v.free {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(Color.white.opacity(0.7))
                                .frame(width: g.size.width * CGFloat(Double(total - free) / Double(total)))
                        }
                    }
                    .frame(height: 4)
                }
                Text(store.capacityText(v)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
            }
            Spacer(minLength: 4)
            if let app = v.apps.first {
                let copying = store.busy.contains(app.path)
                Button { store.install(app, from: v) } label: {
                    Label(copying ? T("복사 중", "Copying") : T("앱 설치", "Install app"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(FAPillStyle(tone: .primary)).disabled(copying)
                .help(T("\(app.lastPathComponent)을 응용 프로그램 폴더로 복사 (이미 있으면 덮어쓰지 않음)",
                        "Copy \(app.lastPathComponent) to Applications (never replaces an existing app)"))
            }
            if store.busy.contains(v.id) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 22)
            } else {
                Button { store.eject(v) } label: { Image(systemName: "eject.fill") }
                    .buttonStyle(FAPillStyle())
                    .help(T("안전하게 꺼내기", "Eject safely"))
                    .accessibilityLabel(T("\(v.name) 꺼내기", "Eject \(v.name)"))
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}

// MARK: - 설정 화면

private struct DRVSettings: View {
    let defaults: ModuleDefaults
    @State private var notify = true
    @State private var offer = true
    @State private var images = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(T("외장 드라이브를 연결하면 알림 (꺼내기 버튼)", "Notify when a drive is connected (with Eject)"), isOn: $notify)
                .onChange(of: notify) { _, v in defaults.set(v, "notifyMount") }
            Toggle(T("디스크 이미지를 열면 앱 설치 제안", "Offer to install apps from opened disk images"), isOn: $offer)
                .onChange(of: offer) { _, v in defaults.set(v, "offerInstall") }
            Toggle(T("목록에 디스크 이미지도 표시", "Show disk images in the list"), isOn: $images)
                .onChange(of: images) { _, v in defaults.set(v, "showImages") }
            Text(T("네트워크 공유, Time Machine 스냅샷, 내장 디스크는 목록에서 뺀다. 설치는 누를 때만 복사하고, 같은 이름의 앱이 있으면 덮어쓰지 않는다.",
                   "Network shares, Time Machine snapshots and internal disks are left out. Install copies only when you click and never replaces an existing app."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            notify = defaults.bool("notifyMount", default: true)
            offer = defaults.bool("offerInstall", default: true)
            images = defaults.bool("showImages", default: true)
        }
    }
}
