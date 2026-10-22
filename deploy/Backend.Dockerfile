FROM node:22-bookworm-slim@sha256:ea11b74b986d520137cdef9a5346e447a00f275ecc4abc0055b7151226231e09 AS webbuild
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY web ./web
RUN npm run build
FROM docker.io/library/docker:29.9.0-cli@sha256:1a4c7cb63513f349bdad01fcc6e0f3f2f67d37b9da86f14dc0d4a0942eecda00 AS dockercli
FROM python:3.13-slim@sha256:d879ed88565a7a3c614b980b369d4a5025a9d057b71f93d09fc6d0b2ca823a18
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git golang-go && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
WORKDIR /opt/devops-quests
COPY . .
COPY --from=webbuild /src/web/vendor ./web/vendor
RUN pip install --no-cache-dir .
CMD ["python3", "scripts/container_start.py"]
