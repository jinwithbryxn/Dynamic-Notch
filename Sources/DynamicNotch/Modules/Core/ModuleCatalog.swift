/// 앱에 들어 있는 확장 기능 목록. 새 기능은 여기에 한 줄 더한다.
enum ModuleCatalog {
    static func makeAll() -> [NotchModule] {
        [
            WorldClockModule(),
            // 타이머·집중·웰빙·데스크톱 위젯
            PomodoroModule(),
            StopwatchModule(),
            FocusSoundsModule(),
            KeepAwakeModule(),
            ActivityRingModule(),
            ScreenTimeModule(),
            BreakReminderModule(),
            FocusSwitchModule(),
            TypingSoundsModule(),
        ]
    }
}
