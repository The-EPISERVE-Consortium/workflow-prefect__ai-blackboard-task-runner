"""Deploys the 'manual' Prefect deployment -- the only deployment this repo
registers.

Prompts are never pre-registered here. Every run supplies its own prompt at
trigger time: a human via `prefect deployment run ... -p prompt=...`, or
`workflow-prefect__generate-ai-task-from-blackboard`'s orchestrator acting on
a `post_type='run_me'` row in the shared blackboard table (`agent_blackboard.
task_runs`) -- including recurring prompts, which now live as periodic
blackboard rows rather than as scheduled deployments in this repo.
"""

import os
from json import JSONDecodeError

from prefect.runner.storage import GitRepository

from flow.agent_task_flow import agent_task_pipeline

GITHUB_REPO_URL = "https://github.com/The-EPISERVE-Consortium/workflow-prefect__run-ai-task"
# publish.yml tags by branch ref (docker/metadata-action's type=ref,event=branch),
# not "latest" -- matches workflow-prefect__model-runner's own convention.
DOCKER_IMAGE = "ghcr.io/the-episerve-consortium/workflow-prefect__run-ai-task:main"
MANUAL_DEPLOYMENT_NAME = "manual"
WORK_POOL_NAME = "kubernetes-pool"


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


def deploy_manual(prefect_api_url: str | None = None) -> None:
    """Deploy the 'manual' deployment: no baked-in prompt, never scheduled.

    Every prompt-bearing flow parameter is left unset at deploy time, so
    triggering this deployment without `-p prompt=...` fails with a clear
    Prefect validation error instead of silently running anything -- a task
    with no prompt doesn't make sense.

    Args:
        prefect_api_url: Prefect API URL, or None to read PREFECT_API_URL.

    Raises:
        EnvironmentError: If PREFECT_API_URL is not set.
        RuntimeError: If the Prefect API URL is not a valid API endpoint.
    """
    prefect_api_url = prefect_api_url or _require_prefect_api_url()
    os.environ["PREFECT_API_URL"] = prefect_api_url

    try:
        agent_task_pipeline.from_source(
            source=GitRepository(url=GITHUB_REPO_URL, branch="main"),
            entrypoint="flow/agent_task_flow.py:agent_task_pipeline",
        ).deploy(
            name=MANUAL_DEPLOYMENT_NAME,
            work_pool_name=WORK_POOL_NAME,
            job_variables={"image": DOCKER_IMAGE, "image_pull_policy": "Always"},
        )
    except JSONDecodeError as exc:
        raise RuntimeError(
            "PREFECT_API_URL does not appear to point to a Prefect API endpoint. "
            f"Got a non-JSON response from {prefect_api_url!r}. "
            "Use the Prefect API URL, for example: "
            "'PREFECT_API_URL=https://prefect.episerve.zib.de/api python deploy.py'."
        ) from exc
