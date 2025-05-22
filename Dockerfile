# syntax=docker/dockerfile:1.6      ← enables heredocs in RUN
FROM debian:bookworm

ENV LANG=C.UTF-8

# ── 0. Core tooling ────────────────────────────────────────────────────
RUN pip install --no-cache-dir "poetry>=1.8,<1.9"

# ── 1. Fetch code while we still have the Internet ─────────────────────
RUN git clone https://github.com/microsoft/graphrag.git /root/graphrag && \
    cd /root/graphrag && \
    git checkout 56a865bff0cac9fbbc24f343cf52d0a1850abba6

WORKDIR /root/graphrag

# ── 2. Warm-up a wheelhouse with EVERYTHING the build will need ────────
RUN mkdir -p /root/wheelhouse && \
    python3 -m pip download --only-binary=:all: \
    --dest /root/wheelhouse \
    "poetry-core>=1.8" \
    "poetry-dynamic-versioning[plugin]>=1.0,<2.0" \
    nltk>=3.8 \
    pathlib \
    dunamai \
    build \
    packaging tomlkit


# ── 3. Install build-system deps from the local wheelhouse ─────────────
RUN pip install --no-index --find-links=/root/wheelhouse \
    "poetry-dynamic-versioning[plugin]" \
    dunamai \
    build

# ── 2b. Cache runtime data needed by tests ─────────────────────────────
# WordNet corpus for NLTK ------------------------------------------------
# ── 2b. Cache runtime data needed by tests ─────────────────────────────
# WordNet corpus for NLTK ------------------------------------------------
# syntax=docker/dockerfile:1.6      ← enables heredocs in RUN

# still online here
RUN pip install --no-cache-dir "nltk>=3.8"
# already have the cl100k_base download in /root/.cache/tiktoken
# already have the cl100k_base download in /root/.cache/tiktoken
ENV TIKTOKEN_CACHE_DIR=/root/.cache/tiktoken

RUN python - <<'PY'
import nltk, pathlib, requests, shutil, importlib.metadata as m
data = pathlib.Path("/usr/local/nltk_data")
data.mkdir(parents=True, exist_ok=True)
nltk.download("wordnet", download_dir=data)
nltk.download("omw-1.4", download_dir=data)
PY

ENV NLTK_DATA=/usr/local/nltk_data

RUN mkdir -p /root/.cache/tiktoken && \
    curl -fsSL \
    https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken \
    -o /root/.cache/tiktoken/cl100k_base.tiktoken

# ── 4. Switch the image to air-gapped mode ──────────────────────────────
ENV PIP_NO_INDEX=1 \
    PIP_FIND_LINKS=/root/wheelhouse \
    POETRY_HTTP_OFFLINE=true \
    NLTK_DATA=/usr/local/nltk_data \
    TIKTOKEN_CACHE_DIR=/root/.cache/tiktoken \
    POETRY_VIRTUALENVS_CREATE=false


# ── 5. Install project + dev deps, then run checks/tests ───────────────
RUN poetry install --with dev --no-interaction
RUN poetry build --no-interaction
RUN poetry run poe check
# Uncomment these if you want unit tests in the image build
#RUN poetry run poe test_unit
#RUN poetry run poe test_verbs

# ── 6. Build wheel/sdist *without* network isolation ───────────────────
RUN python -m build --no-isolation
ENV OPENAI_API_KEY=dummy \
    AZURE_OPENAI_API_KEY=dummy \
    OPENAI_API_TYPE=azure \
    AZURE_OPENAI_ENDPOINT=http://localhost \
    AZURE_OPENAI_API_VERSION=2024-02-15-preview \
    AZURE_SEARCH_ADMIN_KEY=dummy \
    AZURE_SEARCH_ENDPOINT=http://localhost
CMD ["bash"]
