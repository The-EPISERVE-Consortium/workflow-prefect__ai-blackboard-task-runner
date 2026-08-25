import subprocess
from unittest.mock import MagicMock, patch

import pytest

from flow.agent_task_flow import agent_task_pipeline


@pytest.fixture(autouse=True)
def mock_logger():
    logger = MagicMock()
    with patch("flow.agent_task_flow.get_run_logger", return_value=logger):
        yield logger


def test_agent_task_pipeline_calls_pi_agent_task_with_args():
    with patch("flow.agent_task_flow.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(stdout="ok", returncode=0)
        agent_task_pipeline.fn(prompt="Clone X", provider="zib", model="zib/konrad-1")

    mock_run.assert_called_once_with(
        ["pi-agent-task.sh", "zib", "zib/konrad-1", "Clone X"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )


def test_agent_task_pipeline_uses_default_provider_and_model():
    with patch("flow.agent_task_flow.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(stdout="ok", returncode=0)
        agent_task_pipeline.fn(prompt="Clone X")

    args = mock_run.call_args.args[0]
    assert args[1:3] == ["zib", "zib/konrad-1"]


def test_agent_task_pipeline_logs_output(mock_logger):
    with patch("flow.agent_task_flow.subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(stdout="pi-agent-task output here", returncode=0)
        agent_task_pipeline.fn(prompt="Clone X")

    mock_logger.info.assert_called_once_with("pi-agent-task output here")


def test_agent_task_pipeline_raises_on_nonzero_exit():
    with patch("flow.agent_task_flow.subprocess.run") as mock_run:
        mock_run.return_value = subprocess.CompletedProcess(
            args=["pi-agent-task.sh"], returncode=1, stdout="boom"
        )
        with pytest.raises(subprocess.CalledProcessError):
            agent_task_pipeline.fn(prompt="Clone X")
