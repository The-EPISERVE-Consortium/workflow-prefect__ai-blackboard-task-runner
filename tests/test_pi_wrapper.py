"""pi-wrapper.sh hands the prompt to pi-agent-task.sh (a fake one records its arguments)."""

import os
import stat
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WRAPPER = ROOT / "pi-wrapper.sh"
COMMON = ROOT / "pi-common.sh"


def _run(tmp_path, *args, env=None, exit_code=0):
    fake = tmp_path / "pi-agent-task.sh"
    fake.write_text(f'#!/bin/sh\nprintf "%s|" "$@" > {tmp_path}/args\nexit {exit_code}\n')
    fake.chmod(fake.stat().st_mode | stat.S_IEXEC)
    base = {"PATH": f"{tmp_path}:{os.environ['PATH']}", "PI_COMMON": str(COMMON), "SKILLS_DIR": str(tmp_path / "skills")}
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


def _skills(tmp_path, *names):
    for name in names:
        (tmp_path / "skills" / name).mkdir(parents=True)
        (tmp_path / "skills" / name / "SKILL.md").write_text(f"# {name}")


def _real_pi(tmp_path):
    real = tmp_path / "real-pi"
    real.write_text(f'#!/bin/sh\nprintf "real:" > {tmp_path}/real; printf "%s|" "$@" >> {tmp_path}/real\n')
    real.chmod(real.stat().st_mode | stat.S_IEXEC)
    return real


def test_without_a_prompt_or_with_another_option_the_real_pi_starts_with_the_skills(tmp_path):
    _skills(tmp_path, "zeta", "harness-conventions", "alpha")
    real = _real_pi(tmp_path)
    for args, tail in (((), ""), (("--provider", "zib", "--model", "m"), "--provider|zib|--model|m|"),
                       (("--skill", "/x", "y"), "--skill|/x|y|"), (("--provider",), "--provider|")):
        (tmp_path / "real").unlink(missing_ok=True)
        _, called = _run(tmp_path, *args, env={"PI_BIN": str(real)})
        assert called is None
        got = (tmp_path / "real").read_text()
        assert got.startswith("real:") and got.endswith(tail)
        assert f"--skill|{tmp_path}/skills/alpha|--skill|{tmp_path}/skills/zeta|" in got
        assert got.index("harness-conventions") < got.index("alpha") < got.index("zeta")
    (tmp_path / "real").unlink()
    _run(tmp_path, "--no-skills", env={"PI_BIN": str(real)})
    assert (tmp_path / "real").read_text() == "real:--no-skills|"


def test_interactive_pi_gets_todays_api_token(tmp_path):
    _skills(tmp_path, "harness-conventions")
    real = tmp_path / "real-pi"
    real.write_text(f'#!/bin/sh\necho "$EPISERVE_API_KEY" > {tmp_path}/key\n')
    real.chmod(real.stat().st_mode | stat.S_IEXEC)
    curl = tmp_path / "curl"
    curl.write_text('#!/bin/sh\ncat >/dev/null\necho \'{"token":"1.20261017.abc"}\'\n')
    curl.chmod(curl.stat().st_mode | stat.S_IEXEC)
    result, _ = _run(tmp_path, env={"PI_BIN": str(real), "EPISERVE_USERNAME": "a@b", "EPISERVE_PASSWORD": "x"})
    assert (tmp_path / "key").read_text().strip() == "1.20261017.abc"
    assert "fetched today's API token for a@b" in result.stderr
    # a token that is already set is kept
    _run(tmp_path, env={"PI_BIN": str(real), "EPISERVE_API_KEY": "mine", "EPISERVE_USERNAME": "a@b", "EPISERVE_PASSWORD": "x"})
    assert (tmp_path / "key").read_text().strip() == "mine"


def test_exit_code_of_the_task_is_passed_on(tmp_path):
    result, _ = _run(tmp_path, "task", exit_code=7)
    assert result.returncode == 7
