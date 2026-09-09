#!/usr/bin/env python3
"""프롬프트 실행 로그 + 히스토리를 읽어 지시문의 약점을 짚어준다.

로그(prompt-log.jsonl)에는 "무엇을 보내 무엇을 받았는지"가, 히스토리(history.json)에는
"실제로 어떤 결과가 남았는지"가 있다. 둘을 함께 봐야 지시문을 고칠 근거가 나온다.

    python3 scripts/prompt_log_report.py            # 기본 위치
    python3 scripts/prompt_log_report.py --json     # 도구·LLM이 읽기 좋은 형태
"""
import argparse, json, os, statistics, sys
from collections import Counter, defaultdict

DEFAULT_DIR = os.path.expanduser("~/Library/Application Support/CaptureToPrompt")
# breakdown에서 반드시 채워져야 하는 축. pose는 인물이 없으면 비는 게 정상이다.
AXES = ["subject", "style", "medium", "composition", "lighting", "color_palette", "mood"]


def read_log(directory):
    entries = []
    for name in ("logs/prompt-log.1.jsonl", "logs/prompt-log.jsonl"):
        path = os.path.join(directory, name)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    pass   # 쓰다 만 줄은 건너뛴다
    entries.sort(key=lambda e: e.get("timestamp", ""))
    return entries


def read_history(directory):
    path = os.path.join(directory, "history.json")
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)



def parse_size(text):
    if not text or "x" not in text:
        return None
    try:
        w, h = text.split("x")
        return int(w), int(h)
    except ValueError:
        return None


def aspect_fidelity(calls):
    """원본 화면비가 생성 결과에 실제로 재현됐는지 — 산문 지시만으로는 새기 쉽다.

    analyze(입력 크기)와 generate(결과 크기)를 history_id로 짝지어 센다.
    프롬프트에 "roughly square format"이라 써도 생성기가 무시하면 여기서 드러난다.
    """
    source = {}
    for e in calls:
        if e["kind"] == "analyze" and e["outcome"] == "ok":
            size = parse_size(e.get("image_size"))
            if size:
                source[e.get("history_id")] = size

    matched = mismatched = unpaired = 0
    examples = []
    for e in calls:
        if e["kind"] != "generate" or e["outcome"] != "ok":
            continue
        out = parse_size(e.get("image_size"))
        src = source.get(e.get("history_id"))
        if not out:
            continue
        if not src:
            unpaired += 1
            continue
        want, got = src[0] / src[1], out[0] / out[1]
        if abs(want - got) / want <= 0.12:      # 12%까지는 생성기 격자 때문에 어쩔 수 없다
            matched += 1
        else:
            mismatched += 1
            examples.append({"history_id": e.get("history_id"),
                             "source": f"{src[0]}x{src[1]}", "generated": f"{out[0]}x{out[1]}",
                             "note": e.get("note")})
    return {"matched": matched, "mismatched": mismatched, "unpaired": unpaired,
            "examples": examples[:5]}


def log_report(entries):
    """호출 결과와 사용자 반응을 집계한다."""
    calls = [e for e in entries if e.get("outcome") != "signal"]
    signals = [e for e in entries if e.get("outcome") == "signal"]
    by_kind = defaultdict(Counter)
    for e in calls:
        by_kind[e["kind"]][e["outcome"]] += 1

    durations = defaultdict(list)
    for e in calls:
        if e.get("duration_ms"):
            durations[e["kind"]].append(e["duration_ms"])

    # 같은 이미지에 재추출·수정·삭제가 붙었다면 그 추출은 실패한 것이다.
    # 단, 분석하지 않은 캡처를 버린 것은 "쓸모없는 캡처"지 추출 불만이 아니다.
    unhappy = Counter()
    for e in signals:
        if e["kind"] == "item_deleted" and (e.get("note") or "") == "analyzed=false":
            continue
        if e.get("history_id"):
            unhappy[e["history_id"]] += 1

    analyzed_ids = {e.get("history_id") for e in calls
                    if e["kind"] == "analyze" and e["outcome"] == "ok"}
    analyzed_ids.discard(None)

    return {
        "aspect": aspect_fidelity(calls),
        "calls": len(calls),
        "signals": len(signals),
        "by_kind": {k: dict(v) for k, v in by_kind.items()},
        "median_ms": {k: int(statistics.median(v)) for k, v in durations.items()},
        "errors": Counter(e.get("error", "")[:120] for e in calls
                          if e["outcome"] not in ("ok",)).most_common(10),
        "signal_kinds": dict(Counter(e["kind"] for e in signals)),
        "unhappy_items": len(unhappy),
        "analyzed_items": len(analyzed_ids),
        "edits": [{"language": (e.get("note") or "").replace("language=", ""),
                   "before_len": len(e.get("prompt") or ""),
                   "after_len": len(e.get("response") or "")}
                  for e in signals if e["kind"] == "prompt_edited"],
    }


def history_report(items):
    """추출 결과 자체의 모양 — 빈 축, 길이 쏠림, 태그 다양성."""
    analyses = [i["analysis"] for i in items if i.get("analysis")]
    if not analyses:
        return {"items": len(items), "analyzed": 0}

    empty = Counter()
    lengths = defaultdict(list)
    for a in analyses:
        b = a.get("breakdown", {})
        for axis in AXES + ["pose"]:
            value = (b.get(axis) or "").strip()
            if not value:
                empty[axis] += 1
            lengths[axis].append(len(value))
        for lang in ("prompt_en", "prompt_ko", "prompt_ja"):
            lengths[lang].append(len(a.get(lang, "")))
        lengths["tags"].append(len(b.get("tags", [])))

    tag_counter = Counter(t for a in analyses for t in a.get("breakdown", {}).get("tags", []))
    return {
        "items": len(items),
        "analyzed": len(analyses),
        "missing_axis": dict(empty),
        "median_len": {k: int(statistics.median(v)) for k, v in lengths.items()},
        "spread_len": {k: [min(v), max(v)] for k, v in lengths.items()},
        "top_tags": tag_counter.most_common(12),
        "generated_counts": Counter(len(i.get("generatedImageFileNames", []))
                                    for i in items),
    }


def findings(log, hist):
    """수치에서 곧바로 읽히는 문제만 짚는다 (해석은 사람이 한다)."""
    out = []
    if log["calls"] == 0:
        out.append("로그가 비어 있다 — 앱을 한 번 쓴 뒤 다시 볼 것. "
                   "아래 히스토리 통계만으로 판단하면 표본이 결과물뿐이라 실패가 안 보인다.")
    if log["analyzed_items"] and log["unhappy_items"]:
        rate = log["unhappy_items"] / log["analyzed_items"]
        out.append(f"추출 뒤 손을 댄 비율 {rate:.0%} "
                   f"({log['unhappy_items']}/{log['analyzed_items']}) — "
                   "높으면 지시문이 사용자가 원하는 것을 못 뽑고 있다.")
    for axis, count in sorted(hist.get("missing_axis", {}).items(),
                              key=lambda kv: -kv[1]):
        if axis == "pose" or count == 0:
            continue
        out.append(f"'{axis}'가 {count}건 비어 있다 — 지시문에서 필수로 못 박혀 있는지 확인.")
    # prompt_en 길이 편차는 장면 복잡도를 따라간다 (2026-09-09 실측: 인물 3명 3905자 vs
    # 낙서 1327자). 길이만 보고 "장황하다"고 판단하면 오탐이므로 규칙에서 뺐다.
    aspect = log.get("aspect", {})
    paired = aspect.get("matched", 0) + aspect.get("mismatched", 0)
    if paired:
        rate = aspect["mismatched"] / paired
        if rate > 0.1:
            out.append(f"원본 화면비가 생성에서 어긋난 비율 {rate:.0%} "
                       f"({aspect['mismatched']}/{paired}) — 프롬프트가 비율을 산문으로만 "
                       "말하고 있어 생성기가 무시한다. examples 참고.")
    for kind, outcomes in log.get("by_kind", {}).items():
        bad = sum(v for k, v in outcomes.items() if k != "ok")
        total = sum(outcomes.values())
        if total and bad / total > 0.2:
            out.append(f"'{kind}' 실패율 {bad}/{total} — 원인은 errors 목록 참고.")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_DIR)
    ap.add_argument("--json", action="store_true", help="가공 없이 JSON으로 출력")
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        sys.exit(f"경로를 찾을 수 없습니다: {args.dir}")

    log = log_report(read_log(args.dir))
    hist = history_report(read_history(args.dir))
    report = {"log": log, "history": hist, "findings": findings(log, hist)}

    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, default=str))
        return

    print(f"# 프롬프트 실행 리포트  ({args.dir})\n")
    print(f"## 호출 {log['calls']}건 / 사용자 반응 {log['signals']}건")
    for kind, outcomes in sorted(log["by_kind"].items()):
        ms = log["median_ms"].get(kind)
        print(f"  {kind:<10} {dict(outcomes)}" + (f"  중앙값 {ms}ms" if ms else ""))
    if log["signal_kinds"]:
        print(f"  반응: {log['signal_kinds']}")
    if log["errors"]:
        print("\n## 실패 사유")
        for message, count in log["errors"]:
            if message:
                print(f"  {count:>3}x {message}")

    aspect = log.get("aspect", {})
    if aspect.get("matched", 0) + aspect.get("mismatched", 0):
        print(f"\n## 화면비 재현  일치 {aspect['matched']} / 어긋남 {aspect['mismatched']}"
              + (f" / 짝 없음 {aspect['unpaired']}" if aspect.get("unpaired") else ""))
        for ex in aspect.get("examples", []):
            print(f"    {ex['source']} → {ex['generated']}  ({ex.get('note') or ''})")

    print(f"\n## 히스토리 {hist['analyzed']}/{hist['items']}건 분석됨")
    if hist.get("median_len"):
        print("  축별 길이 중앙값(최소~최대):")
        for axis in AXES + ["pose", "prompt_en", "prompt_ko", "prompt_ja", "tags"]:
            if axis not in hist["median_len"]:
                continue
            lo, hi = hist["spread_len"][axis]
            print(f"    {axis:<14} {hist['median_len'][axis]:>5}  ({lo}~{hi})")
    if hist.get("missing_axis"):
        print(f"  빈 축: {hist['missing_axis']}")

    print("\n## 짚이는 점")
    for line in report["findings"]:
        print(f"  - {line}")
    if not report["findings"]:
        print("  - 눈에 띄는 이상 없음")


if __name__ == "__main__":
    main()
