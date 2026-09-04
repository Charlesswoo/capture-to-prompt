import Foundation

/// CLI 프로세스가 0이 아닌 상태로 끝났을 때의 오류 메시지를 만든다.
///
/// codex/claude는 stderr에 진행 로그·프롬프트 조각·hook 알림을 섞어 뱉기 때문에
/// 뒤에서 몇 백 자를 그대로 실으면 원인과 무관한 텍스트가 사용자에게 보인다
/// (실제로 "hook: PostToolUse Completed"가 오류 내용으로 표시된 적이 있다).
/// 그래서 원인으로 보이는 줄만 추리고, 신호로 죽은 경우는 실패가 아니라 중단으로 알린다.
enum CLIProcessFailure {

    static func error(status: Int32, wasSignal: Bool, stderr: String,
                      what: String) -> AnalyzerError {
        if wasSignal {
            return .apiError(
                status: Int(status),
                message: "\(what)이(가) 중단되었습니다 — 실행 중이던 프로세스가 외부에서 "
                    + "종료됐습니다(신호 \(status)). 다시 시도해 주세요.")
        }
        let detail = meaningfulLines(stderr)
        return .apiError(
            status: Int(status),
            message: detail.isEmpty
                ? "\(what)에 실패했습니다 (종료 코드 \(status))."
                : "\(what)에 실패했습니다: \(detail)")
    }

    /// stderr에서 원인이 될 만한 줄만 추린다.
    static func meaningfulLines(_ stderr: String, limit: Int = 400) -> String {
        let lines = stderr
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isNoise($0) }
        guard !lines.isEmpty else { return "" }

        let markers = ["error", "failed", "failure", "cannot", "unable",
                       "denied", "not found", "timeout", "refused"]
        let candidates = lines.filter { line in
            let lowered = line.lowercased()
            return markers.contains { lowered.contains($0) }
        }
        let picked = candidates.isEmpty ? [lines[lines.count - 1]] : candidates
        return String(picked.joined(separator: " / ").prefix(limit))
    }

    /// 원인과 무관한 진행 로그·문서 안내 줄.
    private static func isNoise(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.hasPrefix("hook:") { return true }
        if lowered.hasPrefix("more principles") || lowered.hasPrefix("copy/paste specs") {
            return true
        }
        // codex 시스템 프롬프트 조각 — 참조 문서 경로만 있는 줄
        if lowered.contains("references/") && !lowered.contains("error") { return true }
        return false
    }
}
