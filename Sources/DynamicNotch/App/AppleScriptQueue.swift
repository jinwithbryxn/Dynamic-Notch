import Foundation

/// AppleScript는 이 직렬 큐 한 줄에서만 실행한다.
/// NSAppleScript는 여러 스레드에서 동시에 쓰면 안전하지 않고, 주 스레드에서 부르면
/// 대상 앱(Music·Spotify·메모)이 늦게 답하는 동안 노치가 멈춘다. 주 스레드에서는 부르지 않는다.
enum AppleScriptQueue {
    private static let key = DispatchSpecificKey<Bool>()
    static let queue: DispatchQueue = {
        let q = DispatchQueue(label: "dmn.applescript", qos: .userInitiated)
        q.setSpecific(key: key, value: true)
        return q
    }()

    /// 실행하고 끝날 때까지 기다린다 (백그라운드 스레드에서 부른다). 실패하면 오류 번호·문구.
    static func run(_ source: String) -> (result: NSAppleEventDescriptor?, error: (Int, String)?) {
        let work = { () -> (result: NSAppleEventDescriptor?, error: (Int, String)?) in
            var err: NSDictionary?
            let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let err {
                return (nil, ((err[NSAppleScript.errorNumber] as? Int) ?? 0, (err[NSAppleScript.errorMessage] as? String) ?? ""))
            }
            return (r, nil)
        }
        // 이미 이 큐 안이면 그대로 (sync로 다시 들어가면 멈춘다)
        return DispatchQueue.getSpecific(key: key) == true ? work() : queue.sync(execute: work)
    }
}
