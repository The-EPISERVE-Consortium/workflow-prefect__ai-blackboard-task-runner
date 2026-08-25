"""Shared deployment helper for YAML-backed agent-task deployments."""

import os
from pathlib import Path
from json import JSONDecodeError

from prefect.client.schemas.schedules import CronSchedule
from prefect.runner.storage import GitRepository
import yaml

from flow.agent_task_flow import agent_task_pipeline

GITHUB_REPO_URL = "https://github.com/The-EPISERVE-Consortium/workflow-prefect__run-ai-task"
DOCKER_IMAGE = "ghcr.io/the-episerve-consortium/workflow-prefect__run-ai-task:latest"
REGISTRY_PATH = Path(__file__).with_name("tasks.yaml")
REQUIRED_PARAMETERS = {"prompt"}
MANUAL_DEPLOYMENT_NAME = "manual"


def _require_prefect_api_url() -> str:
    """Return the configured Prefect API URL.

    Returns:
        Prefect API URL from the environment.

    Raises:
        EnvironmentError: If PREFECT_API_URL is not set.
    """
    prefect_api_url = os.environ.get("PREFECT_API_URL")
    if not prefect_api_url:
        raise EnvironmentError(
            "PREFECT_API_URL environment variable is not set. "
            "Export it before running this script, e.g.:\n"
            "  export PREFECT_API_URL=https://<your-prefect-server>/api"
        )
    return prefect_api_url


def _load_registry() -> tuple[dict[str, str], dict[str, dict]]:
    """Load defaults and task entries from the YAML registry.

    Returns:
        Tuple containing registry defaults and task configurations.

    Raises:
        ValueError: If the registry shape is invalid.
    """
    with REGISTRY_PATH.open(encoding="utf-8") as infile:
        data = yaml.safe_load(infile) or {}

    defaults = data.get("defaults", {})
    tasks = data.get("tasks")
    if not isinstance(defaults, dict):
        raise ValueError("deploy/tasks.yaml 'defaults' must be a mapping when present.")
    if not isinstance(tasks, dict) or not tasks:
        raise ValueError("deploy/tasks.yaml must contain a non-empty top-level 'tasks' mapping.")
    return defaults, tasks


def get_task_keys() -> list[str]:
    """Return all task keys defined in the registry.

    Returns:
        Sorted task keys from the YAML registry.
    """
    _, tasks = _load_registry()
    return sorted(tasks.keys())


def _validate_task_config(
    task_key: str,
    config: dict,
    defaults: dict[str, str],
) -> tuple[str, dict[str, str], str, bool]:
    """Validate and normalize one task registry entry.

    Args:
        task_key: Task key from the YAML registry.
        config: Task-specific registry entry.
        defaults: Shared default parameters from the YAML registry.

    Returns:
        Deployment name, merged flow parameters, work pool name, and daily
        schedule flag.

    Raises:
        ValueError: If the task configuration is invalid.
    """
    if not isinstance(config, dict):
        raise ValueError(f"Task '{task_key}' must be a mapping in deploy/tasks.yaml.")

    deployment_name = config.get("deployment_name")
    parameters = config.get("parameters")
    if not deployment_name:
        raise ValueError(f"Task '{task_key}' is missing 'deployment_name'.")
    if not isinstance(parameters, dict):
        raise ValueError(f"Task '{task_key}' must define a 'parameters' mapping.")

    merged_parameters = {
        "provider": defaults.get("provider"),
        "model": defaults.get("model"),
        **parameters,
    }
    work_pool_name = config.get("work_pool_name", defaults.get("work_pool_name", "kubernetes-pool"))
    run_daily = config.get("run_daily", defaults.get("run_daily", True))

    missing = sorted(REQUIRED_PARAMETERS.difference(
        k for k, v in merged_parameters.items() if v not in (None, "")
    ))
    if missing:
        missing_list = ", ".join(missing)
        raise ValueError(
            f"Task '{task_key}' is missing required parameter(s): {missing_list}. "
            "A task with no prompt doesn't make sense -- set it explicitly in deploy/tasks.yaml "
            "(there is deliberately no default; for one-off custom prompts use the 'manual' "
            "deployment instead, see deploy_manual())."
        )

    return deployment_name, merged_parameters, work_pool_name, bool(run_daily)


def _deploy(
    deployment_name: str,
    prefect_api_url: str,
    work_pool_name: str,
    parameters: dict[str, str] | None = None,
    run_daily: bool = False,
) -> None:
    """Deploy one agent_task_pipeline deployment.

    Args:
        deployment_name: Prefect deployment name.
        prefect_api_url: Prefect API URL used by the deployment client.
        work_pool_name: Kubernetes work pool to deploy onto.
        parameters: Default flow parameters, or None to leave every flow
            parameter (including the required `prompt`) unset -- used for
            the 'manual' deployment, where a prompt must be supplied
            explicitly at trigger time (`prefect deployment run ... -p
            prompt=...`) rather than defaulting to anything.
        run_daily: Whether to attach the default daily schedule.

    Raises:
        RuntimeError: If the configured Prefect API URL returns a non-JSON
            response.
    """
    os.environ["PREFECT_API_URL"] = prefect_api_url

    schedule_kwargs = (
        {"schedules": [CronSchedule(cron="0 1 * * *", timezone="Europe/Berlin")]}
        if run_daily
        else {}
    )
    deploy_kwargs = {
        "name": deployment_name,
        "work_pool_name": work_pool_name,
        "job_variables": {"image": DOCKER_IMAGE, "image_pull_policy": "Always"},
        **schedule_kwargs,
    }
    if parameters is not None:
        deploy_kwargs["parameters"] = parameters

    try:
        agent_task_pipeline.from_source(
            source=GitRepository(url=GITHUB_REPO_URL, branch="main"),
            entrypoint="flow/agent_task_flow.py:agent_task_pipeline",
        ).deploy(**deploy_kwargs)
    except JSONDecodeError as exc:
        raise RuntimeError(
            "PREFECT_API_URL does not appear to point to a Prefect API endpoint. "
            f"Got a non-JSON response from {prefect_api_url!r}. "
            "Use the Prefect API URL, for example: "
            "'PREFECT_API_URL=https://prefect.episerve.zib.de/api python -m deploy timesfm-code-analysis'."
        ) from exc


def deploy_manual(prefect_api_url: str | None = None) -> None:
    """Deploy the 'manual' deployment: no baked-in prompt, never scheduled.

    Every prompt-bearing flow parameter is left unset at deploy time, so
    triggering this deployment without `-p prompt=...` fails with a clear
    Prefect validation error instead of silently running anything -- a task
    with no prompt doesn't make sense (see _validate_task_config).

    Args:
        prefect_api_url: Prefect API URL, or None to read PREFECT_API_URL.
    """
    defaults, _ = _load_registry()
    _deploy(
        deployment_name=MANUAL_DEPLOYMENT_NAME,
        prefect_api_url=prefect_api_url or _require_prefect_api_url(),
        work_pool_name=defaults.get("work_pool_name", "kubernetes-pool"),
        parameters=None,
        run_daily=False,
    )


def deploy_from_registry(task_key: str | None = None) -> None:
    """Deploy one named task or all enabled tasks from deploy/tasks.yaml.

    Also deploys the 'manual' deployment whenever every enabled task is
    being deployed (task_key is None) -- it isn't part of the YAML
    registry, so a single-task deploy by name doesn't touch it.

    Args:
        task_key: Optional key for a single task deployment.

    Raises:
        EnvironmentError: If PREFECT_API_URL is not set.
        ValueError: If the requested task is unknown or invalid.
        RuntimeError: If the Prefect API URL is not a valid API endpoint.
    """
    defaults, tasks = _load_registry()
    prefect_api_url = _require_prefect_api_url()

    if task_key:
        config = tasks.get(task_key)
        if config is None:
            available = ", ".join(sorted(tasks))
            raise ValueError(f"Unknown task '{task_key}'. Available tasks: {available}")
        deployment_name, parameters, work_pool_name, run_daily = _validate_task_config(
            task_key, config, defaults
        )
        _deploy(deployment_name, prefect_api_url, work_pool_name, parameters, run_daily)
        return

    for key in sorted(tasks):
        config = tasks[key]
        if not config.get("enabled", True):
            continue
        deployment_name, parameters, work_pool_name, run_daily = _validate_task_config(
            key, config, defaults
        )
        _deploy(deployment_name, prefect_api_url, work_pool_name, parameters, run_daily)

    deploy_manual(prefect_api_url)
