import subprocess
from unittest.mock import MagicMock, patch

import pytest

from flow.agent_task_flow import agent_task_pipeline


class FakeProcess:
    """Stand-in for subprocess.Popen: iterable .stdout, .wait() -> returncode."""

    def __init__(self, lines, returncode=0):
        self.stdout = iter(lines)
        self.returncode = returncode
        self.args = ["pi-agent-task.sh"]

    def wait(self):
        return self.returncode


@pytest.fixture(autouse=True)
def mock_logger():
    logger = MagicMock()
    with patch("flow.agent_task_flow.get_run_logger", return_value=logger):
        yield logger


def test_agent_task_pipeline_calls_pi_agent_task_with_args():
    with patch("flow.agent_task_flow.subprocess.Popen") as mock_popen:
        mock_popen.return_value = FakeProcess([])
        agent_task_pipeline.fn(prompt="Clone X", provider="zib", model="zib/konrad-1")

    mock_popen.assert_called_once_with(
        ["pi-agent-task.sh", "zib", "zib/konrad-1", "Clone X"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )


def test_agent_task_pipeline_uses_default_provider_and_model():
    with patch("flow.agent_task_flow.subprocess.Popen") as mock_popen:
        mock_popen.return_value = FakeProcess([])
        agent_task_pipeline.fn(prompt="Clone X")

    args = mock_popen.call_args.args[0]
    assert args[1:3] == ["zib", "zib/konrad-1"]


def test_agent_task_pipeline_streams_formatted_lines(mock_logger):
    event = '{"type": "agent_settled"}\n'
    with patch("flow.agent_task_flow.subprocess.Popen") as mock_popen:
        mock_popen.return_value = FakeProcess([event])
        agent_task_pipeline.fn(prompt="Clone X")

    mock_logger.info.assert_called_once_with("[done] agent_settled")


def test_agent_task_pipeline_skips_buffered_deltas(mock_logger):
    """A lone thinking_delta with no matching *_end shouldn't log anything."""
    delta = '{"type": "message_update", "assistantMessageEvent": {"type": "thinking_delta", "contentIndex": 0, "delta": "hi"}}\n'
    with patch("flow.agent_task_flow.subprocess.Popen") as mock_popen:
        mock_popen.return_value = FakeProcess([delta])
        agent_task_pipeline.fn(prompt="Clone X")

    mock_logger.info.assert_not_called()


def test_agent_task_pipeline_raises_on_nonzero_exit():
    with patch("flow.agent_task_flow.subprocess.Popen") as mock_popen:
        mock_popen.return_value = FakeProcess([], returncode=1)
        with pytest.raises(subprocess.CalledProcessError):
            agent_task_pipeline.fn(prompt="Clone X")
