FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        jq \
        curl \
        python3 \
        python3-pip \
        python3-venv \
        ca-certificates \
        pandoc \
        wkhtmltopdf \
        weasyprint \
        file \
        xxd \
        fonts-lato \
        ripgrep \
        fd-find \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# Debian's pip refuses bare installs outside a venv (PEP 668) by default.
# The container is fully disposable (/workspace isn't persisted, see
# run-prompt.sh), so there's no system-Python-breakage risk worth the
# friction of forcing every `pip install` through a venv first.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Lets this same image also serve as the Prefect flow-run container
# (flow/agent_task_flow.py, deploy.py) -- no separate image/repo for that,
# see Appendix G in the harness notes. Local/interactive users pay nothing
# for this beyond a few unused pip packages.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Report styling for weasyprint-rendered PDFs (running header, page-number
# chip, two-column body) -- see vendor/pandoc-assets/report.css.
COPY vendor/pandoc-assets /opt/pandoc-assets

RUN npm install -g @earendil-works/pi-coding-agent

# Vendored, patched fork of v2nic/pi-ollama-provider: talks to Ollama's native
# /api/chat (respects num_ctx, unlike the OpenAI-compat route which silently
# truncates on ollama.zib.de). Patched for the @earendil-works/* package
# rename; peerDependencies are supplied by pi itself at runtime, so no
# npm install is needed here.
COPY vendor/pi-ollama-provider /opt/pi-ollama-provider

# Vendored, patched pi-trace-extension: renders a session's events.jsonl into
# a self-contained Langfuse-style trace.html (no server/DB needed). Patched
# to translate the viewer/dashboard UI strings (originally Chinese) to
# English -- see viewer/viewer.html, dashboard.html, viewer.js; rebuild
# viewer/assets.json with viewer/build.py after editing any of those.
COPY vendor/pi-trace-extension /opt/pi-trace-extension

# Skills encoding operational conventions (verify claimed outputs, pandoc's
# PDF engine flag, don't guess paths/fabricate content), the code-analysis
# report structure (one supported task among others, not the only one),
# Discord delivery, and scratch-URL upload. The latter two are entirely the
# model's own decision -- driven by whether the prompt explicitly asks for
# them, not by which env vars happen to be set. All four are always
# force-loaded by pi-agent-task.sh (their full content is concatenated
# directly into the prompt, not left to pi's on-demand skill discovery, which
# the model doesn't reliably trigger on its own).
COPY vendor/skills/harness-conventions /opt/skills/harness-conventions
COPY vendor/skills/code-analysis-report /opt/skills/code-analysis-report
COPY vendor/skills/discord-delivery /opt/skills/discord-delivery
COPY vendor/skills/scratch-url-upload /opt/skills/scratch-url-upload

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY pi-agent-task.sh /usr/local/bin/pi-agent-task.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/pi-agent-task.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
