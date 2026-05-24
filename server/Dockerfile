# Build stage
FROM golang:1.23-alpine AS builder

# Set Go proxy for China (Optimized for faster deployment)
ENV GOPROXY=https://goproxy.cn,direct

# Install system dependencies
RUN apk --no-cache add tzdata ca-certificates

WORKDIR /app

# Copy dependency definition files to leverage Docker layer cache
COPY go.mod go.sum ./
RUN go mod download

# Copy entire source code (including logic directory)
COPY . .

# Build a compact, production-ready binary with stripped debugging symbols
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o server .

# Runtime stage
FROM alpine:3.19

RUN apk --no-cache add tzdata ca-certificates

# Create a non-privileged system user for running the game server securely
RUN addgroup -S gamegroup && adduser -S gameuser -G gamegroup
USER gameuser

WORKDIR /app/

# Copy the pre-compiled binary and static assets from builder stage
COPY --from=builder /app/server .
COPY --from=builder /app/banner.txt .
COPY --from=builder /app/users.json .

# Set timezone
ENV TZ=Asia/Shanghai

# Expose main Game WebSocket port and optional Prometheus metrics port
EXPOSE 8080 9090

# Launch server
CMD ["./server"]
