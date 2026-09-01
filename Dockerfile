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
        mariadb-client \
        gnupg \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# GitHub CLI -- needed by the github-pr skill (open a PR as the episerve-ai-bot
# identity). Not in Debian's default apt repos, so add GitHub's own per their
# documented install method.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# EPISERVE platform + DOIP CLIs -- used by the episerve-platform-access and
# doip-fdo-access skills to reach the running platform / DOIP server. Each
# repo publishes a static linux-amd64 PyInstaller binary per GitHub release
# (public repos, no auth needed). Pinned by tag; bump the ARG to move. The
# `--help` calls are a build-time smoke test that the binary actually runs on
# this base image (catches a glibc mismatch here rather than mid-run).
ARG EPISERVE_CLIENT_VERSION=v0.1.12
ARG EPISERVE_DOIP_CLI_VERSION=v0.0.5
RUN curl -fsSL -o /usr/local/bin/episerve \
        "https://github.com/The-EPISERVE-Consortium/episerve_client/releases/download/${EPISERVE_CLIENT_VERSION}/episerve-client-linux" \
    && curl -fsSL -o /usr/local/bin/episerve-doip-cli \
        "https://github.com/The-EPISERVE-Consortium/episerve_doip_server/releases/download/${EPISERVE_DOIP_CLI_VERSION}/episerve-doip-cli-linux" \
    && chmod +x /usr/local/bin/episerve /usr/local/bin/episerve-doip-cli \
    && /usr/local/bin/episerve --help >/dev/null \
    && /usr/local/bin/episerve-doip-cli --help >/dev/null

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

# Intentionally unpinned -- always take the latest pi harness at build time.
# The cache-bust ARG forces this layer (and only this layer onward) to rebuild
# even when nothing else changed: `docker build --build-arg PI_BUILD_EPOCH=$(date +%s)`.
ARG PI_BUILD_EPOCH=0
RUN npm install -g @earendil-works/pi-coding-agent@latest \
    && pi --help >/dev/null

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
# Discord delivery, scratch-URL upload, blackboard publication, opening a PR,
# and reaching the live EPISERVE platform / DOIP server. Everything except
# harness-conventions and code-analysis-report is entirely the model's own
# decision -- driven by whether the prompt explicitly asks for it, not by
# which env vars happen to be set. All eight are always force-loaded by
# pi-agent-task.sh (their full content is concatenated directly into the
# prompt, not left to pi's on-demand skill discovery, which the model doesn't
# reliably trigger on its own). The episerve-platform-access and
# doip-fdo-access skills shell out to the `episerve` / `episerve-doip-cli`
# binaries installed above.
COPY vendor/skills/harness-conventions /opt/skills/harness-conventions
COPY vendor/skills/code-analysis-report /opt/skills/code-analysis-report
COPY vendor/skills/discord-delivery /opt/skills/discord-delivery
COPY vendor/skills/scratch-url-upload /opt/skills/scratch-url-upload
COPY vendor/skills/blackboard-communication /opt/skills/blackboard-communication
COPY vendor/skills/github-pr /opt/skills/github-pr
COPY vendor/skills/episerve-platform-access /opt/skills/episerve-platform-access
COPY vendor/skills/doip-fdo-access /opt/skills/doip-fdo-access

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY pi-agent-task.sh /usr/local/bin/pi-agent-task.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/pi-agent-task.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
