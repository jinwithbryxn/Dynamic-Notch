import AppKit
import SQLite3

/// macOS 알림 센터 기록 DB 읽기 (전체 디스크 접근 필요, 비공개 형식).
/// - macOS 15 이상: ~/Library/Group Containers/group.com.apple.usernoted/db2/db
/// - 그 이전: $(getconf DARWIN_USER_DIR)/com.apple.notificationcenter/db2/db
/// 실행 중인 DB를 직접 열지 않고 임시 폴더에 복사해 읽은 뒤 바로 지운다. 내용은 메모리에만 두고 로그에 남기지 않는다.
enum NMDatabase {
    enum Status: Equatable {
        case available(String)
        case noFullDiskAccess
        case notFound
    }

    struct Record: Identifiable {
        let id = UUID()
        var bundleID: String
        var title: String
        var subtitle: String
        var body: String
        var date: Date?
    }

    struct Result {
        var records: [Record] = []
        /// 앱 아이콘 배지 수 (번들 ID, 개수)
        var badges: [(String, Int)] = []
    }

    enum ReadError: Error, Equatable {
        case noAccess, notFound, copyFailed, openFailed, unknownFormat(String)
        var message: String {
            switch self {
            case .noAccess: return T("전체 디스크 접근 권한이 없음", "No Full Disk Access")
            case .notFound: return T("알림 기록 DB를 찾지 못함", "Notification database not found")
            case .copyFailed: return T("임시 복사에 실패함", "Temporary copy failed")
            case .openFailed: return T("DB를 열지 못함", "Could not open the database")
            case .unknownFormat(let tables):
                return T("이 macOS의 DB 형식을 모름 (표: \(tables))", "Unknown database format on this macOS (tables: \(tables))")
            }
        }
    }

    static func candidatePaths() -> [String] {
        var paths = [NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_DIR, &buf, buf.count) > 0 {
            paths.append(String(cString: buf) + "com.apple.notificationcenter/db2/db")
        }
        return paths
    }

    /// 파일을 열어 볼 수만 있는지 확인한다 (내용은 읽지 않음).
    static func status() -> Status {
        var blocked = false
        for path in candidatePaths() {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return .available(path) }
            if errno == EPERM || errno == EACCES { blocked = true }
            // 폴더 자체가 막혀 있는지도 본다 (파일이 없어도 EPERM이 나올 수 있음)
            let dir = (path as NSString).deletingLastPathComponent
            if access(dir, F_OK) != 0, errno == EPERM || errno == EACCES { blocked = true }
        }
        return blocked ? .noFullDiskAccess : .notFound
    }

    /// 최근 기록과 앱 배지를 읽는다. 메인 스레드가 아닌 곳에서 부른다.
    static func read(limit: Int = 60) -> Swift.Result<Result, ReadError> {
        guard case .available(let path) = status() else {
            return .failure(status() == .noFullDiskAccess ? .noAccess : .notFound)
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("dmn-nc-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }   // 임시 사본은 읽자마자 지운다
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for suffix in ["", "-wal", "-shm"] where fm.fileExists(atPath: path + suffix) {
                try fm.copyItem(atPath: path + suffix, toPath: temp.appendingPathComponent("db" + suffix).path)
            }
        } catch {
            return .failure(.copyFailed)
        }
        var db: OpaquePointer?
        let dbPath = temp.appendingPathComponent("db").path
        // 임시 사본이라 쓰기 모드로 열어도 원본은 바뀌지 않는다 (WAL을 합치려면 쓰기가 필요할 수 있음)
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return .failure(.openFailed)
        }
        defer { sqlite3_close(db) }

        let tables = Set(column(db, "SELECT name FROM sqlite_master WHERE type='table'"))
        guard tables.contains("record"), tables.contains("app") else {
            return .failure(.unknownFormat(tables.sorted().joined(separator: ",")))
        }
        let recordCols = Set(column(db, "PRAGMA table_info(record)", index: 1))
        let appCols = Set(column(db, "PRAGMA table_info(app)", index: 1))
        guard recordCols.contains("data"), recordCols.contains("app_id"), appCols.contains("identifier") else {
            return .failure(.unknownFormat("record(" + recordCols.sorted().joined(separator: ",") + ")"))
        }
        let dateCol = recordCols.contains("delivered_date") ? "r.delivered_date" : (recordCols.contains("request_date") ? "r.request_date" : "NULL")

        var result = Result()
        let sql = "SELECT a.identifier, r.data, \(dateCol) FROM record r JOIN app a ON a.app_id = r.app_id ORDER BY \(dateCol) DESC LIMIT \(max(1, min(limit, 500)))"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let bundle = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                var rec = Record(bundleID: bundle, title: "", subtitle: "", body: "", date: nil)
                if let blob = sqlite3_column_blob(stmt, 1) {
                    let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 1)))
                    parse(data, into: &rec)
                }
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL {
                    rec.date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 2))
                }
                result.records.append(rec)
            }
        }
        sqlite3_finalize(stmt)

        if appCols.contains("badge") {
            var bs: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT identifier, badge FROM app WHERE badge IS NOT NULL AND badge > 0", -1, &bs, nil) == SQLITE_OK {
                while sqlite3_step(bs) == SQLITE_ROW {
                    let bundle = sqlite3_column_text(bs, 0).map { String(cString: $0) } ?? ""
                    result.badges.append((bundle, Int(sqlite3_column_int(bs, 1))))
                }
            }
            sqlite3_finalize(bs)
        }
        return .success(result)
    }

    /// 기록 한 건의 binary plist: {"app": 번들, "req": {"titl", "subt", "body"}, "date"}
    static func parse(_ data: Data, into rec: inout Record) {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return }
        if rec.bundleID.isEmpty, let app = obj["app"] as? String { rec.bundleID = app }
        let req = obj["req"] as? [String: Any] ?? [:]
        rec.title = (req["titl"] as? String) ?? ""
        rec.subtitle = (req["subt"] as? String) ?? ""
        rec.body = (req["body"] as? String) ?? ""
        if rec.date == nil, let d = obj["date"] as? Double { rec.date = Date(timeIntervalSinceReferenceDate: d) }
    }

    private static func column(_ db: OpaquePointer, _ sql: String, index: Int32 = 0) -> [String] {
        var stmt: OpaquePointer?
        var out: [String] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return out }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let t = sqlite3_column_text(stmt, index) { out.append(String(cString: t)) }
        }
        sqlite3_finalize(stmt)
        return out
    }

    /// 번들 ID → 앱 이름
    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
