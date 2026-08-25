import json

from pretty import PrettyFormatter


def test_non_json_line_passed_through():
    f = PrettyFormatter()
    assert f.feed("pi-report: DISCORD_WEBHOOK_URL not set - skipping") == \
        "pi-report: DISCORD_WEBHOOK_URL not set - skipping"


def test_blank_line_yields_nothing():
    f = PrettyFormatter()
    assert f.feed("   \n") is None


def test_thinking_delta_buffers_until_end():
    f = PrettyFormatter()
    delta = {
        "type": "message_update",
        "assistantMessageEvent": {"type": "thinking_delta", "contentIndex": 0, "delta": "Hello "},
    }
    assert f.feed(json.dumps(delta)) is None

    delta2 = {
        "type": "message_update",
        "assistantMessageEvent": {"type": "thinking_delta", "contentIndex": 0, "delta": "world"},
    }
    assert f.feed(json.dumps(delta2)) is None

    end = {
        "type": "message_update",
        "assistantMessageEvent": {"type": "thinking_end", "contentIndex": 0},
    }
    assert f.feed(json.dumps(end)) == "[thinking] Hello world"


def test_toolcall_end_formats_name_and_args():
    f = PrettyFormatter()
    ev = {
        "type": "message_update",
        "assistantMessageEvent": {
            "type": "toolcall_end",
            "toolCall": {"name": "bash", "arguments": {"command": "ls"}},
        },
    }
    assert f.feed(json.dumps(ev)) == '[tool_call] bash({"command": "ls"})'


def test_tool_execution_end_ok_reports_char_count():
    f = PrettyFormatter()
    ev = {
        "type": "tool_execution_end",
        "isError": False,
        "result": {"content": [{"text": "hello"}]},
    }
    assert f.feed(json.dumps(ev)) == "[tool_result:ok] (5 chars)"


def test_tool_execution_end_error_shown_in_full():
    f = PrettyFormatter()
    ev = {
        "type": "tool_execution_end",
        "isError": True,
        "result": {"content": [{"text": "boom"}]},
    }
    assert f.feed(json.dumps(ev)) == "[tool_result:ERROR] boom"


def test_agent_settled():
    f = PrettyFormatter()
    assert f.feed(json.dumps({"type": "agent_settled"})) == "[done] agent_settled"
