"""Prefect flow that runs pi-report.sh inside this same image, unattended.

No Kubernetes client code, no nested Job, no polling loop -- this flow's own
container IS the container that does the work, so Prefect's own Kubernetes
worker already owns the "create the Job, wait for it, surface its logs"
lifecycle (see Appendix G in the harness notes). Delivery (report.pdf ->
Discord, report.md -> logs/a scratch URL) all happens inside the `pi`
session itself, driven by the skills baked into the image -- this flow does
not implement any of it.
"""

import subprocess

from prefect import flow
from prefect.logging import get_run_logger


@flow
def report_pipeline(prompt: str, provider: str = "zib", model: str = "zib/konrad-1") -> None:
    """Run pi against `prompt`; pi-report.sh and its skills handle delivery.

    Args:
        prompt: Full task prompt handed to `pi` (e.g. "Clone <repo>, ...").
        provider: LLM provider name, passed straight to `pi --provider`.
        model: Model id, passed straight to `pi --model`.

    Raises:
        subprocess.CalledProcessError: If pi-report.sh exits non-zero (e.g.
            the report files weren't produced, or a requested delivery step
            failed).
    """
    logger = get_run_logger()
    # Piped and logged explicitly rather than left to inherit the
    # container's stdout/stderr: inherited output still reaches
    # `kubectl logs`/the K8s API regardless, but isn't guaranteed to show up
    # in Prefect's own UI log viewer, which is driven by `logging` via
    # get_run_logger(). This guarantees the report.md block (printed by
    # pi-report.sh between ===REPORT_MD_BEGIN===/===REPORT_MD_END===
    # markers) is visible directly in the Prefect UI.
    result = subprocess.run(
        ["pi-report.sh", provider, model, prompt],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    logger.info(result.stdout)
    result.check_returncode()
