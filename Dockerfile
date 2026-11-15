# ── Backend image (FastAPI) ──
FROM python:3.12-slim

# No .pyc files, unbuffered output (real-time logs)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Dependencies first (better layer caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Application code
COPY backend/ ./backend/
COPY frontend/ ./frontend/

# Unprivileged user (do not run as root)
RUN useradd -m appuser
USER appuser

EXPOSE 8000

# Healthcheck: hits /health (which also verifies the DB).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/health',timeout=4).status==200 else 1)"

WORKDIR /app/backend

# UVICORN_WORKERS defaults to 1 (local/dev: single process, no Redis needed for
# the rate-limit). In production it is raised via the environment variable (see
# docker-compose.prod.yml), together with RATELIMIT_STORAGE_URI pointing at Redis.
# Shell form (not exec) on purpose, to expand the environment variable.
CMD uvicorn main:app --host 0.0.0.0 --port 8000 --workers ${UVICORN_WORKERS:-1}
