# Operational context for this container

Full conventions live in `/opt/skills/*/SKILL.md`. At the start of any task,
read `/opt/skills/harness-conventions/SKILL.md` in full, and
`/opt/skills/code-analysis-report/SKILL.md` if the task produces a report.
Every other skill there is opt-in -- read one in full when its description
matches the task.

Always, regardless:
- Verify every output file (`ls -la`, `cat`) before saying it was written.
- Any chart: apply the house style and a sparse date locator from
  `harness-conventions` -- never matplotlib's default ticks / `%Y-%m-%d`.
- Investigate tool failures; never guess a path or fabricate content.
- End a fully-successful run with `===AGENT_TASKS_COMPLETE===` on its own line.
