#!/usr/bin/env python3
"""Pretty-print pi's --mode json event stream from stdin.

Merges streaming thinking_delta/text_delta chunks (keyed by contentIndex)
into a single line each, printed once the corresponding *_end event fires.
Tool calls and results are printed compactly. Meant purely for readable
console output -- the full, unfiltered JSONL is what should be saved to
disk (e.g. via `tee run.jsonl` upstream of this filter in a pipeline).

Usage:
    pi --mode json -p "..." | tee run.jsonl | python3 pretty.py
"""
import json
import sys

buffers = {}  # contentIndex -> accumulated text


def emit(label, text):
    text = text.strip()
    if not text:
        return
    print(f"[{label}] {text}", flush=True)


for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        # Not a pi event -- e.g. pi-agent-task.sh's delivery status/errors and
        # the report.md dump it prints after pi's own JSON stream ends. Pass
        # it through as-is rather than silently dropping it.
        print(line, flush=True)
        continue

    t = d.get("type")

    if t == "message_update":
        ev = d.get("assistantMessageEvent", {})
        et = ev.get("type")
        idx = ev.get("contentIndex")
        if et in ("thinking_delta", "text_delta"):
            buffers[idx] = buffers.get(idx, "") + ev.get("delta", "")
        elif et in ("thinking_end", "text_end"):
            label = "thinking" if et == "thinking_end" else "text"
            emit(label, buffers.pop(idx, ev.get("content", "")))
        elif et == "toolcall_end":
            tc = ev.get("toolCall", {})
            args = json.dumps(tc.get("arguments", {}))
            emit("tool_call", f"{tc.get('name')}({args})")

    elif t == "tool_execution_end":
        res = d.get("result", {})
        content = res.get("content", [{}])
        text = content[0].get("text", "") if content else ""
        if d.get("isError"):
            # errors are rare and worth seeing in full (truncated defensively)
            emit("tool_result:ERROR", text[:2000])
        else:
            # success: just confirm it happened, don't dump the payload
            # (e.g. a full file's contents from a `read` call)
            n = len(text)
            print(f"[tool_result:ok] ({n} chars)", flush=True)

    elif t == "auto_retry_start":
        emit("retry", f"attempt {d.get('attempt')}/{d.get('maxAttempts')}: {d.get('errorMessage')}")

    elif t == "agent_settled":
        emit("done", "agent_settled")
