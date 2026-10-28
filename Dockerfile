# ---- Stage 1: install dependencies into a clean folder ----
FROM python:3.12-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage 2: the small image we actually ship ----
FROM python:3.12-slim
LABEL org.opencontainers.image.title="filepipe" \
      org.opencontainers.image.description="Nightly payment CSV cleaner"

# Security: never run as root inside the container.
# Create the user and the data folders while we still have root rights.
RUN useradd --create-home --uid 10001 filepipe \
 && mkdir -p /data/input /data/output \
 && chown -R filepipe:filepipe /data
WORKDIR /app

COPY --from=builder /install /usr/local
COPY app/ ./app/

ENV PYTHONUNBUFFERED=1 \
    INPUT_DIR=/data/input \
    OUTPUT_DIR=/data/output

USER filepipe
ENTRYPOINT ["python", "-m", "app.filepipe"]