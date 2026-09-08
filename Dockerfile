# Stage 1: Build (production mode embeds static/templates/conf into binary)
FROM golang:1.25-alpine AS builder
WORKDIR /src
RUN apk add --no-cache python3
ENV GOPROXY=https://goproxy.cn,direct \
    GOSUMDB=sum.golang.google.cn
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG COMMIT
# Inject version for cache busting (git commit, fallback to build timestamp)
# timetzdata tag embeds timezone database into the binary
RUN python build.py --build --tags timetzdata

# Stage 2: Runtime
FROM alpine:latest
COPY --from=builder /src/bookstark /bookstark
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8089
VOLUME /data
ENV DB_PATH=/data/bookstark.db
ENTRYPOINT ["/bookstark"]
