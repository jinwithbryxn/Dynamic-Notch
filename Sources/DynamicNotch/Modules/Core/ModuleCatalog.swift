/// 앱에 들어 있는 확장 기능 목록. 새 기능은 여기에 한 줄 더한다.
enum ModuleCatalog {
    static func makeAll() -> [NotchModule] {
        [
            WorldClockModule(),
            NotifyMirrorModule(),
            LockCardsModule(),
            AudioDevicesModule(),
            SoundMixerModule(),
            AudioSpectrumModule(),
            MusicToolsModule(),
            ListeningHistoryModule(),
            MiniPlayerModule(),
            DesktopLyricsModule(),
            YouTubeMusicModule(),
            BluetoothBatteryModule(),
            ClipboardModule(),
            SnippetsModule(),
            ColorToolsModule(),
            // 실행·검색·입력
            CalculatorModule(),
            QuickSearchModule(),
            EmojiModule(),
            TranslateModule(),
            LauncherModule(),
            LauncherWheelModule(),
            WindowSnapModule(),
            NaturalCommandsModule(),
            ShortcutsModule(),
            HomeShortcutsModule(),
            SavedLinksModule(),
            VideoSaverModule(),
            InputTriggersModule(),
            TextSelectionModule(),
            DictationModule(),
            SpacesModule(),
            CalendarModule(),
            RemindersModule(),
            TodoModule(),
            AppleNotesModule(),
            WeatherModule(),
        ]
    }
}
