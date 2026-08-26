"""Entrypoint for deploying the 'manual' Prefect deployment."""

from deploy.deploy_registry import deploy_manual


def main() -> None:
    deploy_manual()
