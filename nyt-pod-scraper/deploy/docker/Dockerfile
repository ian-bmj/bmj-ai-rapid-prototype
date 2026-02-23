# =============================================================================
# BMJ Pod Monitor - Backend Container Image
# =============================================================================
# Multi-stage build for the Flask API + processing workers.
# Runs as non-root user with minimal attack surface.
# =============================================================================

FROM python:3.12-slim AS base

# Install system dependencies for audio processing (pydub/ffmpeg)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r podmonitor && useradd -r -g podmonitor -m podmonitor

WORKDIR /app

# Install Python dependencies first (layer caching)
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir gunicorn==23.0.0 boto3==1.35.0

# Copy application code
COPY backend/ /app/backend/
COPY admin-app/ /app/admin-app/
COPY templates/ /app/templates/

# Create data directories (will be overridden by EBS/EFS mounts in k8s)
RUN mkdir -p /app/backend/data/{audio,config,emails,transcripts,summaries} && \
    chown -R podmonitor:podmonitor /app

USER podmonitor

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:5001/api/health || exit 1

EXPOSE 5001

# Default: run the Flask API via gunicorn
ENV FLASK_PORT=5001
CMD ["gunicorn", "--bind", "0.0.0.0:5001", "--workers", "4", "--timeout", "120", \
     "--access-logfile", "-", "--error-logfile", "-", \
     "backend.app:app"]
