# Stage 1: Build the Go binary
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install git (required for some packages if fetching remote modules)
RUN apk add --no-cache git

# Copy dependency manifests and download modules
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code
COPY . .

# Build the Go application statically
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o portal-api ./cmd/portal-api

# Stage 2: Minimal runtime image
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/portal-api .

# Expose port (default environment variable PORTAL_API_ADDR=:3000)
EXPOSE 3000

# Set production environment defaults
ENV PORTAL_API_ADDR=:3000

# Start command
CMD ["./portal-api"]
