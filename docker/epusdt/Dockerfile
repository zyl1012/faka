FROM alpine/git:2.49.1 AS source

ARG EPUSDT_VERSION=v2.0.0
ARG EPUSDT_COMMIT=619cecb11d6bbd1dcdd1b698ee08b37fc722d3e3

RUN git clone --depth 1 --branch "${EPUSDT_VERSION}" \
      https://github.com/GMwalletApp/epusdt.git /source \
    && test "$(git -C /source rev-parse HEAD)" = "${EPUSDT_COMMIT}"

COPY postgres-compat.patch /tmp/postgres-compat.patch
RUN git -C /source apply /tmp/postgres-compat.patch

FROM golang:1.25-alpine AS builder

RUN apk add --no-cache build-base
ENV CGO_ENABLED=0

WORKDIR /source/src
COPY --from=source /source /source

ARG EPUSDT_VERSION=v2.0.0
RUN go mod tidy \
    && go mod verify \
    && go build -trimpath \
      -ldflags="-s -w -X github.com/GMWalletApp/epusdt/config.BuildVersion=${EPUSDT_VERSION}" \
      -o /app/epusdt .

FROM alpine:3.22 AS runner

ENV TZ=Asia/Shanghai
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app
COPY --from=builder /source/src/.env.example /app/.env
COPY --from=builder /app/epusdt /app/epusdt
COPY docker-entrypoint.sh /usr/local/bin/epusdt-entrypoint
RUN chmod 0755 /usr/local/bin/epusdt-entrypoint

VOLUME /app/conf
ENTRYPOINT ["/usr/local/bin/epusdt-entrypoint"]
CMD ["./epusdt", "http", "start"]
