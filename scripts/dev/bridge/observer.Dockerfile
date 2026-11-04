# Imagen local del harness; no contiene datos ni credenciales del origen.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends python3 strace ca-certificates && rm -rf /var/lib/apt/lists/*
