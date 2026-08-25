# deploy.py (at repo root) -- deploys every enabled task in deploy/tasks.yaml
# plus the 'manual' deployment. For a single task, use `python -m deploy
# <task-key>` instead; for only the 'manual' deployment, `python -m deploy
# --manual`.
import sys
from deploy.deployer import main

if __name__ == "__main__":
    sys.argv = [sys.argv[0], "--all"]
    main()
