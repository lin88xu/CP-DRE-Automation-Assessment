# Kong Gateway Docker Deployment Guide

This guide provides instructions for deploying Kong Gateway (backend API) and Kong Manager (frontend UI) locally using Docker.

## 📋 Prerequisites

- **Docker**: [Install Docker](https://docs.docker.com/get-docker/)
- **Docker Compose**: [Install Docker Compose](https://docs.docker.com/compose/install/)
- **Git**: For cloning the repository
- **curl** or **Postman**: For testing API endpoints
- **jq** (optional): For pretty-printing JSON responses

## 🚀 Quick Start

### 1. Start Kong Gateway and PostgreSQL

```bash
make -f Makefile.docker docker-up
```

This command:
- Starts Kong Gateway container
- Starts PostgreSQL database container
- Creates necessary volumes for persistence
- Sets up the Kong network

### 2. Initialize Kong with Sample Data (Optional)

```bash
make -f Makefile.docker docker-init
```

This creates:
- Sample service pointing to `httpbin.org`
- Sample route for testing
- Default admin credentials

### 3. Verify Services are Running

```bash
make -f Makefile.docker docker-status
```

Expected output:
```
Checking Kong services...
✓ Admin API is healthy
✓ Proxy API responding with HTTP 200
✓ Manager UI responding with HTTP 200
```

## 📍 Access Points

Once deployed, Kong is accessible at:

| Component | URL | Purpose |
|-----------|-----|---------|
| **Proxy API** | `http://localhost:8000` | Main API gateway (routes traffic) |
| **Admin API** | `http://localhost:8001` | REST API for managing Kong |
| **Manager UI** | `http://localhost:8002` | Web interface for configuration |
| **Proxy HTTPS** | `https://localhost:8443` | Secure proxy (self-signed cert) |
| **Admin HTTPS** | `https://localhost:8444` | Secure admin API |

## 🔐 Default Credentials

**Admin Manager UI** (`http://localhost:8002`)
- Username: `kong`
- Password: `kong-secret`

> ⚠️ **Important**: Change these credentials in production!

## 📦 Docker Compose Architecture

```
┌─────────────────────────────────────────────┐
│          Docker Network: kong-network       │
├─────────────────────────────────────────────┤
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │     Kong Gateway Container          │   │
│  │ ◆ Port 8000 (Proxy HTTP)            │   │
│  │ ◆ Port 8001 (Admin API)             │   │
│  │ ◆ Port 8002 (Manager UI Frontend)   │   │
│  │ ◆ Port 8443/8444 (HTTPS)            │   │
│  └─────────────────────────────────────┘   │
│                    ↓ (connects to)          │
│  ┌─────────────────────────────────────┐   │
│  │   PostgreSQL Container              │   │
│  │ ◆ Port 5432 (DB)                    │   │
│  │ ◆ Database: kong                    │   │
│  │ ◆ User: kong                        │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │   SSL Certificates (Host Volume)    │   │
│  │ ◆ kong/certs/kong-default.crt       │   │
│  │ ◆ kong/certs/kong-default.key       │   │
│  └─────────────────────────────────────┘   │
│                                             │
└─────────────────────────────────────────────┘
```

## 🎯 Common Tasks

### View Logs

```bash
# All services
make -f Makefile.docker docker-logs

# Specific service
docker-compose logs -f kong          # Kong Gateway logs
docker-compose logs -f kong-db       # PostgreSQL logs
```

### View Running Containers

```bash
make -f Makefile.docker docker-ps
```

### Test the Proxy

```bash
# List all services
make -f Makefile.docker admin-services

# List all routes
make -f Makefile.docker admin-routes

# List all plugins
make -f Makefile.docker admin-plugins
```

### Create a Service

```bash
curl -X POST http://localhost:8001/services \
  --data "name=my-service" \
  --data "url=http://example.com" \
  --data "protocol=http"
```

### Create a Route for the Service

```bash
curl -X POST http://localhost:8001/services/my-service/routes \
  --data "name=my-route" \
  --data "hosts=api.example.com" \
  --data "paths=/api"
```

### Add Authentication Plugin (JWT)

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=jwt" \
  --data "config.secret_is_base64=false"
```

### Test API Request

```bash
# Test through Kong proxy
curl -X GET http://localhost:8000/api \
  -H "Host: api.example.com"
```

## 🛑 Stopping and Cleanup

### Stop Services (Keep Data)

```bash
make -f Makefile.docker docker-down
```

### Stop and Remove Everything (Deletes Data)

```bash
make -f Makefile.docker docker-reset
```

### Restart Services

```bash
make -f Makefile.docker docker-restart
```

## 🔧 Configuration

Kong configuration is managed via environment variables in `docker-compose.yml`. Common settings:

```yaml
KONG_DATABASE: postgres                    # Database type
KONG_PG_HOST: kong-db                     # DB hostname
KONG_PG_USER: kong                        # DB username
KONG_PG_PASSWORD: kong                    # DB password
KONG_ADMIN_GUI_URL: http://localhost:8002 # Manager UI URL
KONG_LOG_LEVEL: info                      # Logging level (info/debug/warn/error)
```

To modify:
1. Edit `docker-compose.yml` environment section
2. Run `make -f Makefile.docker docker-restart`

Additional config in `.env.docker` file (if needed).

## 📚 Admin API Examples

### Get Kong Status

```bash
curl http://localhost:8001/status | jq '.'
```

### List All Services

```bash
curl http://localhost:8001/services | jq '.data'
```

### Get Specific Service

```bash
curl http://localhost:8001/services/my-service | jq '.'
```

### Update Service

```bash
curl -X PATCH http://localhost:8001/services/my-service \
  --data "url=http://newurl.com"
```

### Delete Service

```bash
curl -X DELETE http://localhost:8001/services/my-service
```

### Create Consumer

```bash
curl -X POST http://localhost:8001/consumers \
  --data "username=myuser" \
  --data "custom_id=customer123"
```

### Add Key-Auth Credentials

```bash
curl -X POST http://localhost:8001/consumers/myuser/key-auth \
  --data "key=my-secret-key"
```

## 🐛 Troubleshooting

### Services Won't Start

Check logs for errors:
```bash
make -f Makefile.docker docker-logs
```

### Kong Admin API Not Responding

Wait a bit longer for initialization (15-30 seconds):
```bash
make -f Makefile.docker docker-status
```

### Database Connection Error

Verify PostgreSQL is running:
```bash
docker-compose exec kong-db psql -U kong -d kong -c "SELECT 1"
```

### Port Already in Use

Change ports in `docker-compose.yml`:
```yaml
ports:
  - "8001:8001"  # Change 8001 to another port (e.g., 9001:8001)
```

### SSL Certificate Issues

Regenerate certificates:
```bash
cd kong/certs
rm -f kong-default.*
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout kong-default.key -out kong-default.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
cd ../..
```

## 📖 Additional Resources

- [Kong Official Documentation](https://docs.konghq.com)
- [Kong Admin API Reference](https://docs.konghq.com/gateway/latest/admin-api/)
- [Kong Plugin Hub](https://docs.konghq.com/hub/)
- [Plugin Development Guide](https://docs.konghq.com/gateway/latest/plugin-development/)
- [Official Kong-Docker Repository](https://github.com/Kong/docker-kong)

## 🔄 Using with Kong Manager UI

Kong Manager is the web-based admin interface:

1. Open `http://localhost:8002` in your browser
2. Login with:
   - Username: `kong`
   - Password: `kong-secret`
3. Navigate the dashboard to:
   - Create/manage Services
   - Create/manage Routes
   - Configure Plugins
   - Manage Consumers
   - View Analytics

## 🚨 Production Considerations

- ⚠️ Change default credentials
- ⚠️ Use real SSL certificates (not self-signed)
- ⚠️ Enable RBAC (Role-Based Access Control)
- ⚠️ Set up proper logging and monitoring
- ⚠️ Use strong database passwords
- ⚠️ Enable firewall rules
- ⚠️ Set up database backups
- ⚠️ Use environment-specific configuration

## 📝 Notes

- Volumes are persisted: data survives container restarts
- SSL certificates are self-signed (for development only)
- PostgreSQL password is set to `kong` (change in production)
- Sample service points to `httpbin.org` (public test API)

---

For more help:
```bash
make -f Makefile.docker help
```
