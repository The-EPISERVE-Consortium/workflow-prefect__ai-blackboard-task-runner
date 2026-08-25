"""Unit tests for deploy/deploy_registry.py."""

import pytest

from deploy.deploy_registry import _validate_task_config


DEFAULTS = {
    "work_pool_name": "kubernetes-pool",
    "provider": "zib",
    "model": "zib/konrad-1",
    "run_daily": True,
}


def test_validate_task_config_requires_deployment_name():
    with pytest.raises(ValueError, match="deployment_name"):
        _validate_task_config(
            "some-task",
            {"parameters": {"prompt": "Clone X, do Y."}},
            DEFAULTS,
        )


def test_validate_task_config_requires_parameters_mapping():
    with pytest.raises(ValueError, match="parameters"):
        _validate_task_config(
            "some-task",
            {"deployment_name": "run-ai-task-some-task"},
            DEFAULTS,
        )


def test_validate_task_config_requires_prompt():
    """A task with no prompt doesn't make sense -- must fail loudly, not default."""
    with pytest.raises(ValueError, match="prompt"):
        _validate_task_config(
            "some-task",
            {"deployment_name": "run-ai-task-some-task", "parameters": {}},
            DEFAULTS,
        )


def test_validate_task_config_merges_defaults():
    deployment_name, parameters, work_pool_name, run_daily = _validate_task_config(
        "some-task",
        {
            "deployment_name": "run-ai-task-some-task",
            "parameters": {"prompt": "Clone X, do Y."},
        },
        DEFAULTS,
    )

    assert deployment_name == "run-ai-task-some-task"
    assert parameters["prompt"] == "Clone X, do Y."
    assert parameters["provider"] == "zib"
    assert parameters["model"] == "zib/konrad-1"
    assert work_pool_name == "kubernetes-pool"
    assert run_daily is True


def test_validate_task_config_parameters_override_defaults():
    _, parameters, _, _ = _validate_task_config(
        "some-task",
        {
            "deployment_name": "run-ai-task-some-task",
            "parameters": {"prompt": "Clone X, do Y.", "model": "zib/qwen3.6-35b-a3b"},
        },
        DEFAULTS,
    )

    assert parameters["model"] == "zib/qwen3.6-35b-a3b"


def test_validate_task_config_run_daily_false_overrides_default():
    _, _, _, run_daily = _validate_task_config(
        "some-task",
        {
            "deployment_name": "run-ai-task-some-task",
            "parameters": {"prompt": "Clone X, do Y."},
            "run_daily": False,
        },
        DEFAULTS,
    )

    assert run_daily is False
