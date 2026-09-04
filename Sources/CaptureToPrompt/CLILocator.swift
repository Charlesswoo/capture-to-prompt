import Foundation

/// GUI 앱은 셸 PATH를 물려받지 못하므로, CLI 바이너리를 알려진 설치 위치에서 직접 찾는다.
/// claude·codex 등 npm/homebrew/네이티브로 설치되는 CLI 공용.
enum CLILocator {
    /// 고정 후보 + 패키지 매니저 위치 + nvm 버전별 bin (숫자 기준 최신 우선).
    static func candidatePaths(binary: String, home: String, nvmVersions: [String]) -> [String] {
        var candidates = [
            "\(home)/.local/bin/\(binary)",
            "/usr/local/bin/\(binary)",
            "/opt/homebrew/bin/\(binary)",
            "\(home)/.volta/bin/\(binary)",
            "\(home)/.bun/bin/\(binary)",
            "\(home)/Library/pnpm/\(binary)",
            "\(home)/.npm-global/bin/\(binary)",
            "\(home)/.asdf/shims/\(binary)",
            "\(home)/.local/share/mise/shims/\(binary)",
        ]
        let latestFirst = nvmVersions.sorted {
            versionKey($1).lexicographicallyPrecedes(versionKey($0))
        }
        candidates += latestFirst.map { "\(home)/.nvm/versions/node/\($0)/bin/\(binary)" }
        return candidates
    }

    static func locate(binary: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return candidatePaths(binary: binary, home: home, nvmVersions: nvmVersionDirs(home: home))
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// npm 설치형 CLI(`#!/usr/bin/env node` 셔뱅)가 GUI 최소 PATH에서 node를 못 찾아
    /// 127로 죽는 문제 방지 — 알려진 node 위치를 PATH 뒤에 보강한다.
    static func augmentedPATH(base: String, home: String, nvmVersions: [String]) -> String {
        var parts = base.split(separator: ":").map(String.init)
        var extras = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "\(home)/.asdf/shims",
            "\(home)/.local/share/mise/shims",
        ]
        if let latest = nvmVersions.max(by: { versionKey($0).lexicographicallyPrecedes(versionKey($1)) }) {
            extras.append("\(home)/.nvm/versions/node/\(latest)/bin")
        }
        for dir in extras where !parts.contains(dir) { parts.append(dir) }
        return parts.joined(separator: ":")
    }

    /// 실행 시점의 실제 환경으로 PATH를 보강한 환경변수 셋.
    static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = augmentedPATH(base: env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
                                    home: home, nvmVersions: nvmVersionDirs(home: home))
        return env
    }

    static func nvmVersionDirs(home: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(
            atPath: "\(home)/.nvm/versions/node")) ?? []
    }

    /// "v24.15.0" → [24, 15, 0] (사전순 비교는 v9 > v24라 틀림)
    static func versionKey(_ v: String) -> [Int] {
        v.dropFirst(v.hasPrefix("v") ? 1 : 0).split(separator: ".").map { Int($0) ?? 0 }
    }
}
