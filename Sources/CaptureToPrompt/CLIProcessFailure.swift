import Foundation

/// CLI 프로세스가 0이 아닌 상태로 끝났을 때의 오류 메시지를 만든다.
///
/// codex/claude는 stderr에 진행 로그·프롬프트 조각·hook 알림을 섞어 뱉기 때문에
/// 뒤에서 몇 백 자를 그대로 실으면 원인과 무관한 텍스트가 사용자에게 보인다
/// (실제로 "hook: PostToolUse Completed"가 오류 내용으로 표시된 적이 있다).
/// 그래서 원인으로 보이는 줄만 추리고, 신호로 죽은 경우는 실패가 아니라 중단으로 알린다.
enum CLIProcessFailure {

    /// stderr가 비면 stdout을 본다 — claude/codex는 `--output-format json`에서
    /// 오류도 stdout에 JSON으로 내기 때문에, stderr만 보면 원인이 통째로 사라진다
    /// (2026-09-16: 다른 Mac에서 "종료 코드 1"만 표시된 건 이 때문이었다).
    static func detail(stderr: String, stdout: String) -> String {
        let fromStderr = meaningfulLines(stderr)
        if !fromStderr.isEmpty { return fromStderr }
        return envelopeResult(stdout) ?? meaningfulLines(stdout)
    }

    /// `--output-format json` 봉투에서 `result`만 꺼낸다.
    /// 봉투는 usage·cache_creation 같은 잡동사니가 앞을 채우고 원인은 1KB쯤 뒤에
    /// 있어서, 그냥 앞을 자르면 쓸모없는 텍스트만 보인다.
    private static func envelopeResult(_ stdout: String) -> String? {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(400))
    }

    static func error(status: Int32, wasSignal: Bool, stderr: String,
                      stdout: String = "", what: String) -> AnalyzerError {
        if wasSignal {
            return .apiError(
                status: Int(status),
                message: "\(what)이(가) 중단되었습니다 — 실행 중이던 프로세스가 외부에서 "
                    + "종료됐습니다(신호 \(status)). 다시 시도해 주세요.")
        }
        let detail = detail(stderr: stderr, stdout: stdout)
        return .apiError(
            status: Int(status),
            message: detail.isEmpty
                ? "\(what)에 실패했습니다 (종료 코드 \(status))."
                : "\(what)에 실패했습니다: \(detail)"
                    + loginHint(detail) + usageLimitHint(detail))
    }

    /// 로그인 만료는 앱을 받은 사람이 가장 흔히 겪는데 영어 원문만 보면
    /// 무엇을 해야 할지 알 수 없다 (2026-09-16: OAuth session expired).
    static func loginHint(_ detail: String) -> String {
        let lowered = detail.lowercased()
        // MCP 서버 인증 실패는 CLI 로그인과 무관하다 — 여기 걸리면 엉뚱한 안내가 된다
        let unrelated = ["authrequired", "rmcp::", "mcp.", "www_authenticate_header",
                         "resource_metadata"]
        guard !unrelated.contains(where: { lowered.contains($0) }) else { return "" }
        // 광범위한 "authenticate"·"login" 대신 CLI가 실제로 쓰는 문구만 본다
        let signs = ["session expired", "failed to authenticate", "please run /login",
                     "not logged in", "please log in", "run `claude login`",
                     "codex login", "unauthorized"]
        guard signs.contains(where: { lowered.contains($0) }) else { return "" }
        return "\n→ 로그인 세션이 만료되었습니다. 터미널에서 쓰고 계신 CLI"
            + "(`claude` 또는 `codex`)를 한 번 실행해 로그인한 뒤 다시 시도하세요."
    }

    /// 구독 한도는 기다리거나 결제하는 수밖에 없지만, **다른 백엔드로 계속 쓸 수 있다는
    /// 것은 앱만 안다** (2026-09-17: codex 한도 초과로 이미지 생성이 막혔다).
    static func usageLimitHint(_ detail: String) -> String {
        let lowered = detail.lowercased()
        let signs = ["usage limit", "rate limit", "quota", "purchase more credits",
                     "insufficient_quota"]
        guard signs.contains(where: { lowered.contains($0) }) else { return "" }
        return "\n→ 구독 한도에 걸렸습니다. 기다리거나 크레딧을 채우는 대신, "
            + "설정에서 API 키 백엔드로 바꾸면 지금 바로 계속할 수 있습니다."
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
        // codex는 같은 오류를 여러 번 뱉는다 — 그대로 이으면 메시지가 배로 길어진다
        var seen = Set<String>()
        let unique = picked.filter { seen.insert($0).inserted }
        return String(unique.joined(separator: " / ").prefix(limit))
    }

    /// 원인과 무관한 진행 로그·문서 안내 줄.
    private static func isNoise(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.hasPrefix("hook:") { return true }
        // codex가 자기 MCP 서버·hook을 띄우며 뱉는 줄 — 우리 작업의 실패 원인이 아니다
        // (2026-09-17: Railway MCP의 AuthRequired가 이미지 생성 실패 원인으로 표시됐다)
        if lowered.contains("rmcp::") || lowered.contains("mcp::transport") { return true }
        if lowered.contains("worker quit with fatal") { return true }
        if lowered.hasPrefix("warning: clamping") || lowered.contains("hooks.json") {
            return true
        }
        if lowered.contains("authrequired") || lowered.contains("www_authenticate_header") {
            return true
        }
        if lowered.hasPrefix("more principles") || lowered.hasPrefix("copy/paste specs") {
            return true
        }
        // codex 시스템 프롬프트 조각 — 참조 문서 경로만 있는 줄
        if lowered.contains("references/") && !lowered.contains("error") { return true }
        return false
    }
}
