---
name: code-analysis-report
description: Use whenever the task is to analyse a git repository's code and produce a "code analysis report" (or similar -- audit, review, assessment). Defines the exact section structure, tone, and PDF template to use, so every such report has the same shape regardless of the repository.
---

# Code analysis report

When asked to clone a repository and produce a code analysis report, follow
this exact structure and produce the PDF using the report template
(`pandoc ... -s --pdf-engine=weasyprint --css=/opt/pandoc-assets/report.css`,
per the harness-conventions skill). Base everything on code you actually
read -- never describe a file, risk, or behavior you did not verify by
reading it.

**Also copy the source `report.md` into the output directory next to
`report.pdf`.** The report is frequently handed to another LLM-based coding
agent to act on, and pandoc's multi-page PDF tables split cells across page
breaks in ways that scramble text extraction (a row's Evidence/Fix columns
can land on different pages and get read back interleaved). The Markdown
source has no such corruption and should be the version a downstream agent
actually consumes -- the PDF is for human readers.

## Frontmatter

```yaml
---
title: Code Analysis Report
subtitle: <repo name>
---
```

The lede paragraph (first paragraph after frontmatter) states: what kind of
analysis this is (e.g. "Generated static analysis"), and the date.

## Required sections, in this order

### Executive Summary
2-4 short paragraphs: what the repository does, its overall size/shape
(rough line count, main components), and a one-paragraph preview of the
biggest risks -- pitched at someone who won't read past this section.

### Potential Bug Analysis
A table, one row per suspected bug, ordered High → Medium → Low:

| Priority | Potential Bug | Evidence | Expected Failure Mode | Suggested Fix |
|---|---|---|---|---|

### Vulnerability Analysis
A table, one row per finding, ordered High → Medium → Low:

| Severity | Finding | Evidence | Impact | Recommendation |
|---|---|---|---|---|

"Evidence" must cite actual code with an exact `file:line` (or line range),
not just a quoted snippet -- a snippet alone can match more than one spot in
the file and send a downstream fixer to the wrong occurrence.

Skip either section entirely (don't pad it) if the codebase is too trivial
to have any findings -- say so in one sentence instead of a table with
invented rows.

### Overall Logic
Walk the main execution path step by step (numbered list), naming the actual
entrypoint file/function. Follow with a table:

| Step | Responsible file | Main side effect |
|---|---|---|

One row per major step in the walkthrough above.

### Component Analysis
One `###` subsection per significant file/module actually read. For each:
a one-sentence description, then **Strengths** and **Risks** as bullet
lists. Only include files that were actually opened and read.

### Maintainability Observations
Bullet list: test coverage, documentation drift (does the README match the
code?), typing/structure quality, anything that would slow down a future
contributor.

### Remediation Roadmap
A short numbered list (5-8 items) ordering the fixes above by what should
be done first. Each item must:
- Start with a `[Fix]` or `[Consider]` tag: `[Fix]` for a mechanical,
  unambiguous change with one clearly correct implementation (e.g. "add a
  `<= 0` guard"); `[Consider]` for a design tradeoff with more than one
  reasonable implementation (e.g. "make the imputation policy
  configurable"). This report is often handed to another coding agent to
  act on directly -- `[Fix]` items are safe for it to apply autonomously,
  `[Consider]` items need a human decision first.
- Name the test file that should gain a regression test covering the
  change (e.g. "extend `tests/test_run.py`"), or say "no test coverage
  exists for this path yet" if none does.

### Closing Assessment
One paragraph: overall verdict on the repository's maturity/quality, and
what fixing the top issues would materially improve.

### Appendix A: Repository Inventory
Table of the repo's area/directory structure:

| Area | Files | Purpose |
|---|---|---|

### Appendix B: Deployment and Containerization
Only include if the repo has Dockerfiles/deployment config -- describe what
they do and any packaging/versioning issues found (e.g. missing files in
the image, unpinned base images). Omit this appendix entirely if there's
nothing to deploy (e.g. a library with no container/deploy setup).

### Appendix C: Test Coverage and Verification
Describe what the tests cover. Then **actually run the test suite** (e.g.
`pytest -q`, or whatever the repo's own instructions say) and report the
real command and its real result verbatim -- including if it fails due to
missing dependencies in this container. Do not claim tests pass without
having run them.

## Ground rules (in addition to harness-conventions)

- Every claim needs a concrete anchor: a file path, function/class name, or
  quoted line -- not "the code has security issues" but "`pull.py` joins
  `filename` directly into `/work/input` without normalizing `..`".
- If a section would be empty or speculative for this particular repo, omit
  it (or say "no findings of this kind") rather than inventing content to
  fill the template.
- Keep the tone neutral and specific, like an engineering audit -- not
  marketing language, not hedging filler ("might potentially possibly").
