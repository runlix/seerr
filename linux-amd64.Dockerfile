# Builder image and tag from docker-matrix.json
ARG BUILDER_IMAGE=docker.io/library/debian
ARG BUILDER_TAG=bookworm-slim
# Base image and tag from docker-matrix.json
ARG BASE_IMAGE=ghcr.io/runlix/distroless-runtime
ARG BASE_TAG=stable
# Selected digests (build script will set based on target configuration)
# Default to empty string - build script should always provide valid digests
# If empty, FROM will fail (which is desired to enforce digest pinning)
ARG BUILDER_DIGEST=""
ARG BASE_DIGEST=""
# Seerr source package URL from docker-matrix.json
ARG PACKAGE_URL=""
ARG NODE_VERSION=22.22.0
ARG COMMIT_TAG=unknown

# STAGE 1 — fetch Seerr source
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS fetch

ARG PACKAGE_URL

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    tar \
 && rm -rf /var/lib/apt/lists/* \
 && curl -L -f "${PACKAGE_URL}" -o seerr.tar.gz \
 && tar -xzf seerr.tar.gz -C /app --strip-components=1 \
 && rm seerr.tar.gz

# STAGE 2 — build Seerr app
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS build

ARG NODE_VERSION
ARG COMMIT_TAG

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
    python3 \
    make \
    g++ \
 && rm -rf /var/lib/apt/lists/*

RUN curl -L -f "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o node.tar.xz \
 && tar -xJf node.tar.xz -C /usr/local --strip-components=1 \
 && rm node.tar.xz \
 && corepack enable

COPY --from=fetch /app /app

RUN --mount=type=cache,id=pnpm-store-amd64,target=/pnpm/store \
    CYPRESS_INSTALL_BINARY=0 pnpm install --frozen-lockfile

RUN pnpm build \
 && rm -rf .next/cache \
 && mkdir -p config \
 && touch config/DOCKER \
 && printf '{"commitTag":"%s"}\n' "${COMMIT_TAG}" > committag.json

# STAGE 3 — install production dependencies only
FROM ${BUILDER_IMAGE}:${BUILDER_TAG}@${BUILDER_DIGEST} AS prod-deps

ARG NODE_VERSION

WORKDIR /app

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
    python3 \
    make \
    g++ \
 && rm -rf /var/lib/apt/lists/*

RUN curl -L -f "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o node.tar.xz \
 && tar -xJf node.tar.xz -C /usr/local --strip-components=1 \
 && rm node.tar.xz \
 && corepack enable

COPY --from=fetch /app /app

RUN --mount=type=cache,id=pnpm-store-amd64,target=/pnpm/store \
    CI=true pnpm install --prod --frozen-lockfile

# STAGE 4 — distroless final image
FROM ${BASE_IMAGE}:${BASE_TAG}@${BASE_DIGEST}

ARG LIB_DIR=x86_64-linux-gnu

ENV NODE_ENV=production
ENV PORT=5055

WORKDIR /app

# Node runtime
COPY --from=build /usr/local/bin/node /usr/local/bin/node
COPY --from=build /usr/local/lib/node_modules /usr/local/lib/node_modules

# App files and build output
COPY --from=build /app /app
COPY --from=prod-deps /app/node_modules /app/node_modules
COPY --from=build /app/.next /app/.next
COPY --from=build /app/dist /app/dist

# Native module runtime dependencies
COPY --from=build /usr/lib/${LIB_DIR}/libstdc++.so.* /usr/lib/${LIB_DIR}/
COPY --from=build /usr/lib/${LIB_DIR}/libgcc_s.so.* /usr/lib/${LIB_DIR}/

EXPOSE 5055
USER 20030:20030
ENTRYPOINT ["/usr/local/bin/node", "dist/index.js"]
