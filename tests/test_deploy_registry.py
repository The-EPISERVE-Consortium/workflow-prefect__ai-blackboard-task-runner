"""Unit tests for deploy/deploy_registry.py."""

import os
from unittest.mock import MagicMock, patch

import pytest

from deploy.deploy_registry import (
    DOCKER_IMAGE,
    MANUAL_DEPLOYMENT_NAME,
    WORK_POOL_NAME,
    _require_prefect_api_url,
    deploy_manual,
)


def test_require_prefect_api_url_raises_when_unset(monkeypatch):
    monkeypatch.delenv("PREFECT_API_URL", raising=False)
    with pytest.raises(EnvironmentError, match="PREFECT_API_URL"):
        _require_prefect_api_url()


def test_require_prefect_api_url_returns_env_value(monkeypatch):
    monkeypatch.setenv("PREFECT_API_URL", "https://prefect.example.com/api")
    assert _require_prefect_api_url() == "https://prefect.example.com/api"


def test_deploy_manual_deploys_with_no_prompt_and_never_scheduled():
    mock_pipeline = MagicMock()
    with patch("deploy.deploy_registry.agent_task_pipeline") as mock_flow:
        mock_flow.from_source.return_value = mock_pipeline
        deploy_manual(prefect_api_url="https://prefect.example.com/api")

    assert os.environ["PREFECT_API_URL"] == "https://prefect.example.com/api"
    mock_pipeline.deploy.assert_called_once()
    _, kwargs = mock_pipeline.deploy.call_args
    assert kwargs["name"] == MANUAL_DEPLOYMENT_NAME
    assert kwargs["work_pool_name"] == WORK_POOL_NAME
    assert kwargs["job_variables"] == {"image": DOCKER_IMAGE, "image_pull_policy": "Always"}
    assert "parameters" not in kwargs
    assert "schedules" not in kwargs
