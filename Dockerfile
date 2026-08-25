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
# PDF engine flag, don't guess paths/fabricate content) and the code-analysis
# report structure. Both are always force-loaded by run-prompt.sh (their full
# content is concatenated directly into the prompt, not left to pi's on-demand
# skill discovery, which the model doesn't reliably trigger on its own).
COPY vendor/skills/harness-conventions /opt/skills/harness-conventions
COPY vendor/skills/code-analysis-report /opt/skills/code-analysis-report

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
