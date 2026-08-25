"""Argument parsing and command dispatch for YAML-backed task deployments."""

import argparse

from deploy.deploy_registry import deploy_from_registry, deploy_manual, get_task_keys


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Deploy agent-task Prefect deployments from YAML.")
    parser.add_argument(
        "task",
        nargs="?",
        help="Task key from deploy/tasks.yaml, for example 'timesfm-code-analysis'.",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        dest="deploy_all",
        help="Deploy all enabled tasks from deploy/tasks.yaml, plus the 'manual' deployment.",
    )
    parser.add_argument(
        "--manual",
        action="store_true",
        dest="deploy_manual_only",
        help="Deploy only the 'manual' deployment (no baked-in prompt, never scheduled).",
    )
    return parser


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.deploy_manual_only:
        deploy_manual()
        return

    if args.deploy_all:
        deploy_from_registry()
        return

    if args.task:
        deploy_from_registry(args.task)
        return

    available = ", ".join(get_task_keys())
    parser.error(f"Provide a task key, --all, or --manual. Available tasks: {available}")
