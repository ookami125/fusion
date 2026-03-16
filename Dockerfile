FROM node:lts-alpine AS frontend-builder
RUN corepack enable && corepack prepare pnpm@latest --activate
WORKDIR /src/frontend
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY frontend/ ./
ARG FUSION_VERSION=dev
RUN VITE_FUSION_VERSION="$FUSION_VERSION" pnpm run build

FROM golang:1.26-alpine AS backend-builder
WORKDIR /src/backend
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/ ./
COPY --from=frontend-builder /src/frontend/dist ./internal/web/dist
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags '-extldflags "-static"' \
    -o /fusion \
    ./cmd/fusion

FROM alpine:3.21.0
LABEL org.opencontainers.image.source="https://github.com/0x2E/fusion"

RUN addgroup -S fusion && adduser -S -D -H -h /fusion -G fusion fusion && \
    mkdir -p /data && chown -R fusion:fusion /data

WORKDIR /fusion
COPY --from=backend-builder --chown=fusion:fusion /fusion ./fusion
RUN chmod 755 ./fusion
EXPOSE 8080
VOLUME ["/data"]
ENV DB="/data/fusion.db"
HEALTHCHECK --interval=10s --timeout=3s --start-period=2s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/api/oidc/enabled || exit 1
# TODO: Temporarily run as root until legacy /data DB files owned by root are migrated.
CMD [ "./fusion" ]
