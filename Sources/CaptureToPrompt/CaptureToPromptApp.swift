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
            CommandGroup(after: .newItem) {
                Button("새 캡처") { appState.startNewCapture() }
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
