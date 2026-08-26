# deploy.py (at repo root) -- deploys the 'manual' Prefect deployment, the
# only deployment this repo registers. Equivalent to `python -m deploy`.
#
#   PREFECT_API_URL=https://your.prefect.server/api python deploy.py
from deploy.deployer import main

if __name__ == "__main__":
    main()
