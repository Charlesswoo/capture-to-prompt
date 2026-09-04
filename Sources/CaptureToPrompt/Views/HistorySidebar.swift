import SwiftUI
import AppKit

struct HistorySidebar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var history: HistoryStore
    @State private var hoveredID: UUID?

    var body: some View {
        List {
            if history.items.isEmpty {
                ContentUnavailableView(
                    "히스토리 없음",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("분석한 이미지가 여기에 쌓입니다"))
            } else {
                Section {
                    ForEach(history.items) { item in
                        rowView(item)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    Text("히스토리 · \(history.items.count)")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("히스토리")
    }

    private func rowView(_ item: HistoryItem) -> some View {
        Button {
            appState.show(item)
        } label: {
            HStack(spacing: 10) {
                thumbnail(for: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.analysis.breakdown.subject)
                        .lineLimit(2)
                        .font(.callout)
                    HStack(spacing: 5) {
                        Text(item.createdAt, format: .relative(presentation: .named))
                        // 이 항목에 생성 이미지가 보관돼 있음을 표시 (다시 눌러 열면 복원)
                        if !item.generatedImageFileNames.isEmpty {
                            Label("\(item.generatedImageFileNames.count)",
                                  systemImage: "photo.stack")
                                .labelStyle(.titleAndIcon)
                        }
                        // 다른 항목을 보고 있어도 이 항목의 생성 상태를 알 수 있게
                        if appState.isGenerating(for: item.id) {
                            ProgressView()
                                .controlSize(.mini)
                                .help("이 항목에서 이미지 생성 중")
                        } else if appState.isAnalyzing(for: item.id) {
                            ProgressView()
                                .controlSize(.mini)
                                .help("이 원본으로 다시 분석 중 — 끝나면 새 항목이 추가됩니다")
                        } else if appState.hasGenerationError(for: item.id) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .help("이 항목의 이미지 생성이 실패했습니다 — 눌러서 내용 확인")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if hoveredID == item.id {
                    Button {
                        appState.deleteHistoryItem(item)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("삭제")
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .contextMenu {
            Button("원본으로 다시 분석") {
                appState.reanalyze(item)
            }
            .help("이 항목의 원본 캡처 이미지로 프롬프트를 새로 뽑습니다 (결과는 새 항목)")
            Divider()
            Button("프롬프트 복사 (한국어)") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.analysis.promptKo, forType: .string)
            }
            // 보고 있지 않은 항목의 생성본도 여기서 정리할 수 있다
            if !item.generatedImageFileNames.isEmpty {
                Button("생성 이미지 \(item.generatedImageFileNames.count)장 삭제",
                       role: .destructive) {
                    appState.deleteAllGeneratedImages(for: item.id)
                }
            }
            Button("항목 삭제", role: .destructive) {
                appState.deleteHistoryItem(item)
            }
        }
    }

    private func thumbnail(for item: HistoryItem) -> some View {
        Group {
            if let image = NSImage(contentsOf: history.imageURL(for: item)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
    }
}
