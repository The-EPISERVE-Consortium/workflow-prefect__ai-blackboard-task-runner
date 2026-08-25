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

from pretty import PrettyFormatter


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
    # Streamed line-by-line through PrettyFormatter (the same formatting
    # run-prompt.sh uses for local console output, refactored into a class
    # for reuse) rather than buffered and logged as one block at the end --
    # so progress shows up in the Prefect UI's log view as it happens, not
    # only once the whole run (potentially several minutes) has finished.
    formatter = PrettyFormatter()
    process = subprocess.Popen(
        ["pi-agent-task.sh", provider, model, prompt],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    for line in process.stdout:
        formatted = formatter.feed(line)
        if formatted is not None:
            logger.info(formatted)

    returncode = process.wait()
    if returncode != 0:
        raise subprocess.CalledProcessError(returncode, process.args)
