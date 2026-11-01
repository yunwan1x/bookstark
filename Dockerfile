# Stage 1: Build (production mode embeds static/templates/conf into binary)
ARG GO_BUILDER_IMAGE=golang:1.25-alpine
FROM --platform=$BUILDPLATFORM ${GO_BUILDER_IMAGE} AS builder
WORKDIR /src
RUN apk add --no-cache python3
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG COMMIT
ARG TARGETOS
ARG TARGETARCH
# Inject version for cache busting (git commit, fallback to build timestamp)
# timetzdata tag embeds timezone database into the binary
RUN python3 build.py --build --tags timetzdata \
    --goos "$TARGETOS" --goarch "$TARGETARCH" --output bookstark

# Stage 2: Runtime
FROM alpine:latest
ARG COMMIT=unknown
LABEL org.opencontainers.image.revision="${COMMIT}"
COPY --from=builder /src/bookstark /bookstark
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8089
VOLUME /data
ENV DB_PATH=/data/bookstark.db
ENTRYPOINT ["/bookstark"]
