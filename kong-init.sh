#!/bin/bash

# Kong Docker Initialization Script
# This script sets up Kong, creates sample services and routes, and configures the Admin UI

set -e

echo "=========================================="
echo "Kong Gateway Docker Setup"
echo "=========================================="

# Wait for Kong to be ready
echo "Waiting for Kong to be ready..."
sleep 10

until curl -s -f http://localhost:8001/status > /dev/null 2>&1; do
  echo "Waiting for Kong Admin API..."
  sleep 2
done

echo "✓ Kong is ready!"

# Create sample service
echo "Creating sample service..."
curl -X POST http://localhost:8001/services \
  --data "name=sample-service" \
  --data "url=http://httpbin.org" \
  --data "enabled=true" \
  --data "protocol=http" \
  -s | jq '.' || true

# Create sample route
echo "Creating sample route..."
curl -X POST http://localhost:8001/services/sample-service/routes \
  --data "name=sample-route" \
  --data "hosts=example.com" \
  --data "methods=GET,POST" \
  --data "strip_path=true" \
  -s | jq '.' || true

echo ""
echo "=========================================="
echo "Kong Gateway is Ready!"
echo "=========================================="
echo ""
echo "Access points:"
echo "  - Proxy API:          http://localhost:8000"
echo "  - Admin API:          http://localhost:8001"
echo "  - Admin Manager UI:   http://localhost:8002"
echo "  - Admin Proxy HTTPS:  https://localhost:8443"
echo "  - Admin API HTTPS:    https://localhost:8444"
echo ""
echo "Default Admin UI Credentials:"
echo "  - Username: kong"
echo "  - Password: kong-secret"
echo ""
echo "Sample Service Details:"
echo "  - Name: sample-service"
echo "  - URL:  http://httpbin.org"
echo "  - Route: http://localhost:8000 (Host: example.com)"
echo ""
