---
name: harness-conventions
description: Operational conventions for running unattended in this Docker harness -- verifying that claimed file outputs actually exist before reporting success, ending every run with the ===AGENT_TASKS_COMPLETE=== marker only when the task truly succeeded, generating PDFs correctly with pandoc, and investigating tool failures instead of guessing paths or fabricating content. Always apply these when running headless.
---

# Harness conventions

You are running headless and unattended inside a Docker container. Nobody will
read your final message and manually double-check your work before it's
consumed downstream -- so the following must hold.

## Never claim success without verifying it

Before your final message says a file was written, run `ls -la <path>` (or
`cat` it) and confirm it actually exists with the content you intended. Do not
report "Report has been written to X" based on assuming a tool call succeeded
-- confirm it with a follow-up check every time.

If a shell command is chained with `&&` and an earlier part fails, everything
after it never ran. Prefer separate commands over long `&&` chains for any
step whose completion matters (e.g. writing an output file) so a failure
partway through is visible and doesn't silently skip the important part.

## Ending a run

An orchestrator scheduled this run and decides whether it succeeded by
looking at your output. The **last thing you print**, after every part of
the task is done and verified per the rule above, must be this exact line
on its own:

```
===AGENT_TASKS_COMPLETE===
```

Print it **only** when the whole task the prompt asked for actually
succeeded -- every file produced and checked, every requested delivery
(Discord, PR, blackboard, scratch URL) confirmed. If any part failed, could
not be completed, or you are unsure it worked, do **not** print the line;
end instead with a short plain-text explanation of what went wrong. A run
whose output does not contain `===AGENT_TASKS_COMPLETE===` is treated as
failed -- so never print it "to be safe", and never print it before the
work is finished.

## Never fabricate content

If you cannot read a file or a command fails, say so and investigate (`ls`,
`find`) rather than describing file contents or a directory structure you
never actually observed.

## Recovering from a wrong path

If a `read` or file path fails with "no such file", don't guess a second
absolute path from general knowledge of common conventions. Instead run `ls`
on the parent directory or `find / -name "<expected-name>" 2>/dev/null` to
locate the actual path, then proceed from what you find.

## Generating PDFs

`pandoc` is installed, but its default PDF engine (`pdflatex`) is **not**
installed and will fail. Always pass the engine explicitly.

`file` and `xxd` are both installed for verifying the result (e.g. `file output.pdf` should say `PDF document`).

### Whenever the task is to produce "a report" (as PDF)

Use this exact template -- do not invent your own styling, layout, or engine
choice for reports. This produces a single-column, professionally styled
document (accent-colored page-number chip, running header with the document
title, bold lede paragraph, justified body text):

```bash
pandoc report.md -s --pdf-engine=weasyprint --css=/opt/pandoc-assets/report.css -o report.pdf
```

Requirements for `report.md` to render correctly with this template:
- Start with YAML frontmatter setting `title` and (optionally) `subtitle` --
  these become the big heading and the running header text, not a `# Heading`
  in the body:
  ```markdown
  ---
  title: Your Report Title
  subtitle: One-line description of what this report covers
  ---
  ```
- The first paragraph after the frontmatter is styled as a bold lede/summary
  -- write a short, punchy 2-3 sentence overview there, not a wall of detail.
- Use `##`/`###` for section headings; don't use a top-level `#` heading in
  the body (the title from frontmatter already renders as the page title).
- This template is single-column -- do not add your own multi-column CSS or
  `column-count` styling.
- Do not pass a second `--css` or edit `report.css`. The template already
  constrains embedded images to the page width (`img { max-width: 100% }`).

**Only** use `--pdf-engine=wkhtmltopdf` (with no `--css`) for a plain,
unstyled PDF conversion when the task explicitly isn't "a report" -- e.g.
converting an arbitrary existing markdown file as-is with no styling
requirement. `wkhtmltopdf` does not support the CSS Paged Media features
(`@page` margin boxes, running headers) that `report.css` relies on, so it
must not be combined with `--css=/opt/pandoc-assets/report.css`.

### Charts in a report

`matplotlib` and `pandas` (+ `pyarrow` for parquet) are installed -- do not
`pip install` a plotting stack. Build the chart with matplotlib, size it for
the A4 content box at creation rather than relying on the CSS to shrink it
(`fig, ax = plt.subplots(figsize=(6.5, 4)); ... fig.savefig("plot.png",
dpi=150, bbox_inches="tight")`), then reference it from `report.md` as
`![caption](plot.png)`. Verify `plot.png` exists and is non-empty before
building the PDF.

**Time axis.** A date x-axis with matplotlib's default tick placement and a
long `%Y-%m-%d` format produces overlapping, unreadable labels once the
series spans more than a few weeks -- this is what made the x-labels collide
in earlier plots. Do not rely on the default. Instead set a sparse locator, a
short date format, and rotate the labels right-aligned:

```python
import matplotlib.dates as mdates
ax.xaxis.set_major_locator(mdates.WeekdayLocator(byweekday=mdates.MO, interval=2))
ax.xaxis.set_major_formatter(mdates.DateFormatter("%d %b %y"))
fig.autofmt_xdate(rotation=45, ha="right")
```

Widen the `interval` (or switch to `MonthLocator`) for longer spans -- aim
for roughly 6-12 ticks across the axis, never one per data point.

## Running a repo's own test suite

`python3` and `pip` are both installed, and `pip install <packages>` works
directly (no venv, no `--break-system-packages` needed -- the container is
fully disposable). Don't waste steps checking whether pip exists or trying
to bootstrap it (`ensurepip`, `apt-get install python3-pip`) -- it's already
there.

But install only what the tests actually need, not the full runtime
dependency set. A single `pip install -r requirements.txt` can pull in a
massive, unused stack (e.g. torch + CUDA binaries, often multiple GB) just
to run a mocked test suite.

1. First check for a dedicated test/dev requirements file
   (`requirements-test.txt`, `requirements-dev.txt`) or a `[test]`/`[dev]`
   extra in `pyproject.toml`. If one exists, install from it directly and
   proceed -- no further reasoning needed.
2. Only if no such file exists, fall back to `requirements.txt`, but first
   scan the code (`rg "import (torch|cuda)" src tests`) for whether a heavy
   package is actually imported in the paths the tests exercise. If it's
   only imported inside a `try`/`except ImportError` block or mocked out in
   the fixture, skip installing it and install the rest.

A lightweight check-up is cheap; a multi-gigabyte install of unused
CUDA/torch libraries is not, and it repeats on every run. Prefer the
smallest dependency set that still lets the suite pass.

## Writing across mount boundaries

`/workspace` and `/output` are separate mounts. When asked to write a file to
an absolute path under `/output`, write to that exact path -- do not create an
`output/` subdirectory under `/workspace` instead. If unsure whether a write
landed in the right place, `ls` the target directory afterward to confirm.
