"""Trigger a run for every enabled task in deploy/tasks.yaml.

Unlike `deploy.py` (which registers deployments -- a one-time/on-release
step), this actually starts flow runs, on demand, in addition to whatever
each task's own daily schedule does on its own. Deliberately skips the
'manual' deployment (batch-running it would just fail -- it has no prompt
of its own by design, see deploy/deploy_registry.py).

    PREFECT_API_URL=https://your.prefect.server/api python run.py
"""

import os
import subprocess

from deploy.deploy_registry import _load_registry, _require_prefect_api_url

if __name__ == "__main__":
    os.environ["PREFECT_API_URL"] = _require_prefect_api_url()

    _, tasks = _load_registry()
    for key in sorted(tasks):
        config = tasks[key]
        if not config.get("enabled", True):
            continue
        deployment_name = config["deployment_name"]
        print(f"=== triggering agent-task-pipeline/{deployment_name} ===")
        subprocess.run(
            ["prefect", "deployment", "run", f"agent-task-pipeline/{deployment_name}"],
            check=True,
        )
