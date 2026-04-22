ARG BUILDER_REF="docker.io/library/debian:bookworm-slim@sha256:5a2a80d11944804c01b8619bc967e31801ec39bf3257ab80b91070eb23625644"
ARG BASE_REF="ghcr.io/runlix/distroless-runtime-v2-canary:stable@sha256:77f225cc62e8aa2cf6807434f112830cdcd186f1145fbf10f0283adb4ee39baf"
ARG PACKAGE_URL="https://github.com/seerr-team/seerr/archive/refs/tags/v3.1.0.tar.gz"
ARG NODE_VERSION=22.22.0
ARG COMMIT_TAG=unknown

FROM ${BUILDER_REF} AS fetch

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

FROM ${BUILDER_REF} AS build

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

FROM ${BUILDER_REF} AS prod-deps

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

FROM ${BASE_REF}

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
