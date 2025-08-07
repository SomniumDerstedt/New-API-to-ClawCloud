FROM oven/bun:latest AS builder

WORKDIR /build
COPY web/package.json .
COPY web/bun.lock .
RUN bun install
COPY ./web .
COPY ./VERSION .
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) bun run build

FROM golang:alpine AS builder2

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux

WORKDIR /build

ADD go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=builder /build/dist ./web/dist
RUN go build -ldflags "-s -w -X 'one-api/common.Version=$(cat VERSION)'" -o one-api

FROM alpine

# Install dependencies for the application and the services
RUN apk upgrade --no-cache \
    && apk add --no-cache ca-certificates tzdata ffmpeg postgresql redis supervisor su-exec

# Create the necessary directories for PostgreSQL and set permissions.
# The 'postgres' user is created by the postgresql package itself.
RUN mkdir -p /run/postgresql && chown -R postgres:postgres /run/postgresql && \
    mkdir -p /var/lib/postgresql/data && \
    chown -R postgres:postgres /var/lib/postgresql/data && \
    chmod 700 /var/lib/postgresql/data

# Copy the application binary from the builder stage
COPY --from=builder2 /build/one-api /one-api

# Copy the configuration files for supervisor
COPY supervisord.conf /etc/supervisord.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh && mkdir -p /app

EXPOSE 3000
EXPOSE 5432
EXPOSE 6379
WORKDIR /data

# Set the entrypoint to our script
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
