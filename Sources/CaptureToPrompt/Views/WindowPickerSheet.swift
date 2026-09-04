import SwiftUI

/// Exposé풍 창 선택기: 열린 창들을 썸네일 그리드로 보여주고 클릭으로 캡처.
struct WindowPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var windows: [PickableWindow] = []
    @State private var isLoading = true
    @State private var hoveredID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("캡처할 창을 선택하세요")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .help("창 목록 새로고침")
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            if isLoading {
                ProgressView("창 목록을 불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if windows.isEmpty {
                ContentUnavailableView(
                    "캡처할 창이 없습니다",
                    systemImage: "macwindow.badge.plus",
                    description: Text("다른 앱 창을 연 뒤 새로고침하세요"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                              spacing: 14) {
                        ForEach(windows) { window in
                            cell(window)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .frame(width: 760, height: 520)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        windows = await WindowEnumerator.pickableWindows()
        isLoading = false
    }

    private func cell(_ window: PickableWindow) -> some View {
        Button {
            dismiss()
            appState.captureKnownWindowAndAnalyze(id: window.id)
        } label: {
            VStack(spacing: 6) {
                Group {
                    if let thumb = window.thumbnail {
                        Image(decorative: thumb, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "macwindow")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 1) {
                    Text(window.appName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if !window.title.isEmpty {
                        Text(window.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(hoveredID == window.id
                          ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                          : AnyShapeStyle(.thinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(hoveredID == window.id
                                  ? Color.accentColor
                                  : Color.white.opacity(0.1),
                                  lineWidth: hoveredID == window.id ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredID = inside ? window.id : (hoveredID == window.id ? nil : hoveredID)
        }
    }
}
