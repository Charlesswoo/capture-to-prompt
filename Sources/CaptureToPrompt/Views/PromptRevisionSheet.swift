import SwiftUI
import AppKit

/// 정책 거부 진단 결과 — 어떤 구절이 문제였고, 어떻게 고치면 되는지.
struct PromptRevisionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let revision = appState.currentRevision {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard(revision.summary)
                        if revision.issues.isEmpty {
                            Text("문제 구절을 특정하지 못했습니다. 아래 수정본을 사용해 보세요.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            issuesSection(revision.issues)
                        }
                        revisedSection(revision.revisedPrompt)
                    }
                    .padding(20)
                }
            } else {
                ContentUnavailableView("개선안이 없습니다", systemImage: "text.badge.xmark")
                    .frame(maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.sparkles")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("프롬프트 개선 제안")
                    .font(.headline)
                Text("생성 정책에 걸린 부분과 고쳐 쓴 프롬프트입니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func summaryCard(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(summary)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 12))
    }

    private func issuesSection(_ issues: [PromptRevision.Issue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("걸린 부분 \(issues.count)곳")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(issues) { issue in
                VStack(alignment: .leading, spacing: 6) {
                    // 문제가 된 구절은 원문 그대로 — 어디를 고칠지 바로 보이게
                    Text(issue.phrase)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.14), in: .rect(cornerRadius: 6))
                        .textSelection(.enabled)
                    Text(issue.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(issue.suggestion)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        }
    }

    private func revisedSection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("고쳐 쓴 프롬프트")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt, forType: .string)
                } label: {
                    Label("복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(prompt)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassEffect(.regular.tint(.green.opacity(0.10)), in: .rect(cornerRadius: 12))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            // 시트가 자동으로 뜨므로 Return에는 아무 동작도 걸지 않는다.
            // (기본 버튼이 "교체하고 다시 생성"이면 무심코 누른 Return이 프롬프트를 갈아치운다)
            Button("프롬프트 교체") {
                appState.applyCurrentRevision()
                dismiss()
            }
            .disabled(appState.currentRevision == nil)
            Button("교체하고 다시 생성") {
                appState.applyCurrentRevisionAndRegenerate()
                dismiss()
            }
            .disabled(appState.currentRevision == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
