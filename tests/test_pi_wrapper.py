"""pi-wrapper.sh hands the prompt to pi-agent-task.sh (a fake one records its arguments)."""

import os
import stat
import subprocess
from pathlib import Path

WRAPPER = Path(__file__).resolve().parent.parent / "pi-wrapper.sh"


def _run(tmp_path, *args, env=None, exit_code=0):
    fake = tmp_path / "pi-agent-task.sh"
    fake.write_text(f'#!/bin/sh\nprintf "%s|" "$@" > {tmp_path}/args\nexit {exit_code}\n')
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    base = {"PATH": f"{tmp_path}:{os.environ['PATH']}"}
    result = subprocess.run(["bash", str(WRAPPER), *args], env={**base, **(env or {})}, capture_output=True, text=True)
    called = (tmp_path / "args").read_text() if (tmp_path / "args").exists() else None
    return result, called


def test_prompt_goes_to_pi_agent_task_with_the_default_provider_and_model(tmp_path):
    result, called = _run(tmp_path, "Say", "hello")
    assert result.returncode == 0
    assert called == "zib|zib/konrad-1|Say hello|"


def test_environment_and_flags_choose_provider_and_model(tmp_path):
    _, called = _run(tmp_path, "task", env={"LLM_PROVIDER_NAME": "ollama", "LLM_MODEL": "a,b"})
    assert called == "ollama|a|task|"
    _, called = _run(tmp_path, "--provider", "openrouter", "--model", "m", "task",
                     env={"LLM_PROVIDER_NAME": "ollama", "LLM_MODEL": "a"})
    assert called == "openrouter|m|task|"


def test_without_a_prompt_or_with_another_option_the_real_pi_starts(tmp_path):
    real = tmp_path / "real-pi"
    real.write_text(f'#!/bin/sh\nprintf "real:%s|" "$@" > {tmp_path}/real\n')
    real.chmod(real.stat().st_mode | stat.S_IEXEC)
    for args, expected in (((), "real:|"), (("--provider", "zib", "--model", "m"), "real:--provider|zib|--model|m|"),
                           (("--skill", "/opt/skills", "x"), "real:--skill|/opt/skills|x|"),
                           (("--provider",), "real:--provider|")):
        (tmp_path / "real").unlink(missing_ok=True)
        _, called = _run(tmp_path, *args, env={"PI_BIN": str(real)})
        assert called is None
        assert (tmp_path / "real").read_text() == expected


def test_exit_code_of_the_task_is_passed_on(tmp_path):
    result, _ = _run(tmp_path, "task", exit_code=7)
    assert result.returncode == 7
