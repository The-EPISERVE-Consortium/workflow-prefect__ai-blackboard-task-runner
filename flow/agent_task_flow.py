"""Prefect flow that runs pi-agent-task.sh inside this same image, unattended.

No Kubernetes client code, no nested Job, no polling loop -- this flow's own
container IS the container that does the work, so Prefect's own Kubernetes
worker already owns the "create the Job, wait for it, surface its logs"
lifecycle (see Appendix G in the harness notes). Delivery (e.g. a file ->
Discord, a scratch URL) all happens inside the `pi` session itself, driven
by the skills baked into the image -- this flow does not implement any of
it, and makes no assumption about what kind of task `prompt` describes (a
code analysis report is one supported task, not the only one).
"""

import subprocess

from prefect import flow
from prefect.logging import get_run_logger


@flow
def agent_task_pipeline(prompt: str, provider: str = "zib", model: str = "zib/konrad-1") -> None:
    """Run pi against `prompt`; pi-agent-task.sh and its skills handle delivery.

    Args:
        prompt: Full task prompt handed to `pi` (e.g. "Clone <repo>, ...").
        provider: LLM provider name, passed straight to `pi --provider`.
        model: Model id, passed straight to `pi --model`.

    Raises:
        subprocess.CalledProcessError: If pi-agent-task.sh exits non-zero
            (e.g. a requested delivery step failed).
    """
    logger = get_run_logger()
    # Piped and logged explicitly rather than left to inherit the
    # container's stdout/stderr: inherited output still reaches
    # `kubectl logs`/the K8s API regardless, but isn't guaranteed to show up
    # in Prefect's own UI log viewer, which is driven by `logging` via
    # get_run_logger(). This guarantees any report.md block (printed by
    # pi-agent-task.sh between ===OUTPUT_MD_BEGIN===/===OUTPUT_MD_END===
    # markers, when the task produced one) is visible directly in the
    # Prefect UI.
    result = subprocess.run(
        ["pi-agent-task.sh", provider, model, prompt],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    logger.info(result.stdout)
    result.check_returncode()
