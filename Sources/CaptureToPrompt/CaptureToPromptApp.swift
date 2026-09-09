import SwiftUI

@main
struct CaptureToPromptApp: App {
    @StateObject private var appState: AppState
    @StateObject private var history: HistoryStore
    @AppStorage("hotKeyPreset") private var hotKeyPreset = HotKeyManager.defaultPreset.rawValue

    init() {
        let store = HistoryStore()
        let state = AppState(history: store)
        _history = StateObject(wrappedValue: store)
        _appState = StateObject(wrappedValue: state)

        // 전역 단축키: 앱이 비활성 상태여도 마우스 아래 창을 캡처해 분석한다.
        HotKeyManager.shared.onHotKey = { [weak state] in
            Task { @MainActor in state?.captureWindowUnderMouseAndAnalyze() }
        }
        let preset = HotKeyManager.Preset(
            rawValue: UserDefaults.standard.string(forKey: "hotKeyPreset") ?? "")
            ?? HotKeyManager.defaultPreset
        HotKeyManager.shared.apply(preset: preset)
    }

    private var currentHotKeyLabel: String {
        (HotKeyManager.Preset(rawValue: hotKeyPreset) ?? HotKeyManager.defaultPreset).label
    }

    var body: some Scene {
        WindowGroup("CaptureToPrompt") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(history)
        }
        // 콘텐츠 최소 크기(800×480) 아래로 창 축소 금지
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("업데이트 확인…") { appState.checkForUpdatesNow() }
            }
            // `replacing:` 이어야 한다. WindowGroup은 File 메뉴에 "New Window"(⌘N)를
            // 자동으로 넣는데, `after:`로 붙이면 ⌘N이 둘이 되어 시스템 것이 이기고
            // 새 창이 열린다 (2026-09-09 사용자 보고). 이 앱은 창이 하나뿐이라
            // "New Window" 자체가 필요 없다.
            CommandGroup(replacing: .newItem) {
                Button("새 화면") { appState.startNewCapture() }
                    .keyboardShortcut("n")
                Button("원본으로 다시 분석") { appState.reanalyzeCurrent() }
                    .keyboardShortcut("r")
                    .disabled(appState.currentHistoryItem == nil)
                Button("이미지 파일 열기…") { appState.showFileImporter = true }
                    .keyboardShortcut("o")
                Button("클립보드 이미지 분석") { appState.analyzeFromClipboard() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandMenu("캡처") {
                Button("마우스 아래 창 캡처") { appState.captureWindowUnderMouseAndAnalyze() }
                    .keyboardShortcut("1")
                Button("창 선택 캡처") { appState.captureSelectedWindowAndAnalyze() }
                    .keyboardShortcut("2")
                Button("영역 선택 캡처") { appState.captureAndAnalyze() }
                    .keyboardShortcut("3")
                Divider()
                Text("전역 단축키: \(currentHotKeyLabel) — 어느 앱에서든 동작")
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        MenuBarExtra("CaptureToPrompt", systemImage: "camera.viewfinder") {
            Button("마우스 아래 창 캡처 → 프롬프트  (\(currentHotKeyLabel))") {
                appState.captureWindowUnderMouseAndAnalyze()
            }
            Button("창 선택 캡처 → 프롬프트") {
                appState.captureSelectedWindowAndAnalyze()
            }
            Button("영역 선택 캡처 → 프롬프트") {
                NSApp.activate(ignoringOtherApps: true)
                appState.captureAndAnalyze()
            }
            Button("클립보드 이미지 분석") {
                appState.bringToFront()
                appState.analyzeFromClipboard()
            }
            Divider()
            Button("창 열기") {
                appState.bringToFront()
            }
            Button("종료") { NSApp.terminate(nil) }
        }
    }
}
