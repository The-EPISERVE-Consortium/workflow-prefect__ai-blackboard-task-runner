#!/usr/bin/env python3
"""Pretty-print pi's --mode json event stream from stdin.

Merges streaming thinking_delta/text_delta chunks (keyed by contentIndex)
into a single line each, printed once the corresponding *_end event fires.
Tool calls and results are printed compactly. Meant purely for readable
console output -- the full, unfiltered JSONL is what should be saved to
disk (e.g. via `tee run.jsonl` upstream of this filter in a pipeline).

Also importable as a module (`from pretty import PrettyFormatter`) so the
same formatting can be reused for streaming, line-by-line logging --
flow/agent_task_flow.py does this to surface live progress in the Prefect
UI instead of buffering the whole run and logging it as one block at the
end.

Usage:
    pi --mode json -p "..." | tee run.jsonl | python3 pretty.py
"""
import json
import sys


class PrettyFormatter:
    """Feed it one line at a time; get back a formatted string to emit, or
    None if the line was buffered (e.g. a delta chunk still accumulating)."""

    def __init__(self):
        self.buffers = {}  # contentIndex -> accumulated text

    def feed(self, line: str) -> str | None:
        line = line.strip()
        if not line:
            return None
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            # Not a pi event -- e.g. pi-agent-task.sh's delivery status/errors
            # and the report.md dump it prints after pi's own JSON stream
            # ends. Pass it through as-is rather than silently dropping it.
            return line

        t = d.get("type")

        if t == "message_update":
            ev = d.get("assistantMessageEvent", {})
            et = ev.get("type")
            idx = ev.get("contentIndex")
            if et in ("thinking_delta", "text_delta"):
                self.buffers[idx] = self.buffers.get(idx, "") + ev.get("delta", "")
                return None
            elif et in ("thinking_end", "text_end"):
                label = "thinking" if et == "thinking_end" else "text"
                return self._format(label, self.buffers.pop(idx, ev.get("content", "")))
            elif et == "toolcall_end":
                tc = ev.get("toolCall", {})
                args = json.dumps(tc.get("arguments", {}))
                return self._format("tool_call", f"{tc.get('name')}({args})")

        elif t == "tool_execution_end":
            res = d.get("result", {})
            content = res.get("content", [{}])
            text = content[0].get("text", "") if content else ""
            if d.get("isError"):
                # errors are rare and worth seeing in full (truncated defensively)
                return self._format("tool_result:ERROR", text[:2000])
            else:
                # success: just confirm it happened, don't dump the payload
                # (e.g. a full file's contents from a `read` call)
                return f"[tool_result:ok] ({len(text)} chars)"

        elif t == "auto_retry_start":
            return self._format("retry", f"attempt {d.get('attempt')}/{d.get('maxAttempts')}: {d.get('errorMessage')}")

        elif t == "agent_settled":
            return self._format("done", "agent_settled")

        return None

    @staticmethod
    def _format(label: str, text: str) -> str | None:
        text = text.strip()
        if not text:
            return None
        return f"[{label}] {text}"


if __name__ == "__main__":
    formatter = PrettyFormatter()
    for line in sys.stdin:
        out = formatter.feed(line)
        if out is not None:
            print(out, flush=True)
