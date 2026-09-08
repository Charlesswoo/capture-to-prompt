import SwiftUI
import AppKit

struct HistorySidebar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var history: HistoryStore
    @State private var hoveredID: UUID?
    /// 삭제는 되돌릴 수 없으므로 한 번 확인한다 (원본·프롬프트·생성본이 함께 사라진다).
    @State private var itemToDelete: HistoryItem?

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
        .confirmationDialog(
            "이 항목을 삭제할까요?",
            isPresented: Binding(get: { itemToDelete != nil },
                                 set: { if !$0 { itemToDelete = nil } }),
            titleVisibility: .visible,
            presenting: itemToDelete
        ) { item in
            Button("삭제", role: .destructive) {
                appState.deleteHistoryItem(item)
                itemToDelete = nil
            }
            Button("취소", role: .cancel) { itemToDelete = nil }
        } message: { item in
            Text(deletionSummary(item))
        }
    }

    /// 삭제하면 무엇이 사라지는지 — 원본·프롬프트는 항상, 생성본은 있을 때만.
    private func deletionSummary(_ item: HistoryItem) -> String {
        let subject = item.analysis?.breakdown.subject ?? "분석 전 캡처"
        let title = subject.count > 40 ? String(subject.prefix(40)) + "…" : subject
        var lines = ["\(title)\n"]
        let generated = item.generatedImageFileNames.count
        if generated > 0 {
            let size = ByteCountFormatter.string(
                fromByteCount: history.generatedImagesByteSize(id: item.id), countStyle: .file)
            lines.append("원본 캡처와 프롬프트, 생성 이미지 \(generated)장(\(size))이 함께 지워집니다.")
        } else {
            lines.append("원본 캡처와 프롬프트가 지워집니다.")
        }
        lines.append("되돌릴 수 없습니다.")
        return lines.joined(separator: "\n")
    }

    private func rowView(_ item: HistoryItem) -> some View {
        Button {
            appState.show(item)
        } label: {
            HStack(spacing: 10) {
                thumbnail(for: item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.analysis?.breakdown.subject ?? "분석 대기 중")
                        .lineLimit(2)
                        .font(.callout)
                        .foregroundStyle(item.analysis == nil ? .secondary : .primary)
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
                                .help("분석 중")
                        } else if item.analysis == nil {
                            Image(systemName: "hourglass")
                                .foregroundStyle(.orange)
                                .help("아직 분석하지 않은 캡처 — 눌러서 열고 분석할 수 있습니다")
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
                        itemToDelete = item
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
            if let analysis = item.analysis {
                Button("프롬프트 복사 (한국어)") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(analysis.promptKo, forType: .string)
                }
            } else {
                Button("분석 시작") { appState.analyzeItem(item) }
            }
            // 보고 있지 않은 항목의 생성본도 여기서 정리할 수 있다
            if !item.generatedImageFileNames.isEmpty {
                Button("생성 이미지 \(item.generatedImageFileNames.count)장 삭제",
                       role: .destructive) {
                    appState.deleteAllGeneratedImages(for: item.id)
                }
            }
            Button("항목 삭제", role: .destructive) {
                itemToDelete = item
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
