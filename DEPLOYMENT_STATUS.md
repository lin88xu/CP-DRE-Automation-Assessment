# Kong Gateway Docker Deployment - Complete Setup

## ✅ Deployment Status

Kong Gateway is now **successfully deployed** locally with Docker! Here's what's running:

### Running Services

```
SERVICE          STATUS        PORTS
────────────────────────────────────────────────────────────────
kong             Up (healthy)  8000 (Proxy), 8001 (Admin), 8002 (UI)
kong-db          Up (healthy)  5432 (PostgreSQL)
```

### Access Points

| Service | URL | Purpose |
|---------|-----|---------|
| **Proxy API** | `http://localhost:8000` | Main API Gateway (routes requests) |
| **Admin API** | `http://localhost:8001` | Kong Management API (REST) |
| **Manager UI** | `http://localhost:8002` | Web Admin Interface (Frontend) |

---

## 📦 What's Included

### Backend (Kong Gateway)
- **Version**: Latest Kong Gateway
- **Mode**: DB-less (Declarative Configuration)
- **Configuration**: Loaded from `kong.yml`
- **Features**: Routing, plugins, rate limiting, CORS, request transformation

### Frontend (Kong Manager)
- **Web UI**: Accessible at `http://localhost:8002`
- **Purpose**: Visual management of Kong configuration
- **Default Login**: `kong` / `kong-secret`

### Database
- **PostgreSQL 15 Alpine**: Optional persistent database
- **Port**: `5432`
- **Database**: `kong`
- **User**: `kong`
- **Password**: `kong`

---

## 🚀 Quick Start Commands

```bash
# View all containers
make -f Makefile.docker docker-ps

# View logs
make -f Makefile.docker docker-logs

# Stop services
make -f Makefile.docker docker-down

# Restart services
make -f Makefile.docker docker-restart

# Reset everything
make -f Makefile.docker docker-reset

# Check health
make -f Makefile.docker docker-status
```

---

## 🎯 Configuration Model

### DB-less Mode (Current)
kong.yml → LMDB Cache → Kong Runtime

**Pros:**
- ✓ Simple setup
- ✓ No database required
- ✓ Fast startup
- ✓ Perfect for development and testing

**Cons:**
- ✗ Configuration is read-only (via Admin API)
- ✗ Changes require restarting Kong

### PostgreSQL Mode (Optional)
To switch to PostgreSQL with dynamic updates:

1. Edit `docker-compose.yml` and uncomment PostgreSQL settings
2. Run: `docker-compose restart kong`

---

## 📝 Declarative Configuration (kong.yml)

The file `kong.yml` contains:

✓ **Services** - Backend services to proxy  
✓ **Routes** - URL paths mapped to services  
✓ **Consumers** - Users/API clients  
✓ **Plugins** - Features like auth, rate limiting, CORS  

Example routes configured:
- `GET / (Host: example.com)` → `httpbin.org`
- `GET /api/*` → `httpbin.org/api`

---

## 🔌 Plugins Configured

| Plugin | Purpose | Configuration |
|--------|---------|----------------|
| `key-auth` | API key authentication | Required for sample-service |
| `rate-limiting` | Limit requests per minute/hour | 100 req/min, 1000 req/hour |
| `cors` | Cross-Origin Resource Sharing | All origins allowed |
| `request-transformer` | Add/modify request headers | Adds X-Demo: true |

---

## 🧪 Testing the Deployment

### Test 1: Proxy is working

```bash
curl -H "Host: example.com" http://localhost:8000/
```

Expected: JSON response from httpbin.org

### Test 2: Admin API is working

```bash
curl http://localhost:8001/status
```

Expected: Kong health status (JSON)

### Test 3: Manager UI is accessible

Open browser: `http://localhost:8002`

Expected: Kong Manager login page

---

## 📋 File Structure

```
project-root/
├── docker-compose.yml          # Docker services definition
├── kong.yml                    # Declarative Kong configuration
├── kong-init.sh                # Sample initialization script
├── kong/
│   └── certs/                  # SSL certificates
│       └── kong-default.*      # Self-signed certificates
├── Makefile.docker             # Convenience commands
├── DOCKER_DEPLOYMENT.md        # This guide
└── .env.docker                 # Default environment config
```

---

## 🔐 Security Notes (Development Only)

⚠️ **Important**: This setup is for **development/testing only**

Production considerations:
- [ ] Change default credentials `kong`/`kong-secret`
- [ ] Use real SSL certificates (not self-signed)
- [ ] Enable RBAC (Role-Based Access Control)
- [ ] Use strong PostgreSQL passwords
- [ ] Implement firewall rules
- [ ] Set up database backups
- [ ] Enable audit logging
- [ ] Use secrets for credentials

---

## 🔧 Modifying Configuration

### To add a new Service

Edit `kong.yml` and add to the `services:` section:

```yaml
  - name: my-new-service
    url: http://myapi.example.com
    protocol: http
    routes:
      - name: my-route
        paths: [/api]
        methods: [GET, POST]
```

Then restart: `make -f Makefile.docker docker-restart`

### To add a Plugin

Add to the `plugins:` section in `kong.yml`:

```yaml
  - name: request-size-limiting
    service: my-new-service
    config:
      allowed_payload_size: 10
```

### To add a Consumer

Add to the `consumers:` section in `kong.yml`:

```yaml
  - username: acme-dev
    custom_id: ACME-001
```

---

## 📊 Port Mapping

```
Host:Container  Purpose
────────────────────────────────────────
8000:8000      Proxy (API Gateway)
8001:8001      Admin API (Management)
8002:8002      Manager UI (Frontend)
8443:8443      Proxy HTTPS (disabled)
8444:8444      Admin HTTPS (disabled)
5432:5432      PostgreSQL Database
```

---

## 🐛 Troubleshooting

### Kong container not starting?
```bash
make -f Makefile.docker docker-logs | tail -50
```

### Port already in use?
Edit `docker-compose.yml` and change ports:
```yaml
ports:
  - "9000:8000"  # Use 9000 instead of 8000
```

### Database connection error?
Verify PostgreSQL is running (if using DB mode):
```bash
docker-compose exec kong-db psql -U kong -d kong -c "SELECT 1"
```

### Admin API not responding?
Wait a bit longer (30-60 seconds):
```bash
make -f Makefile.docker docker-status
```

---

## 📚 Additional Resources

- [Kong Official Docs](https://docs.konghq.com)
- [Admin API Reference](https://docs.konghq.com/gateway/latest/admin-api/)
- [Plugin Documentation](https://docs.konghq.com/hub/)
- [Plugin Development](https://docs.konghq.com/gateway/latest/plugin-development/)
- [Docker Kong Image](https://hub.docker.com/_/kong)

---

## 🔄 Switching Between Modes

### To use PostgreSQL instead of DB-less:

```bash
# 1. Edit docker-compose.yml
# 2. Uncomment PostgreSQL settings
# 3. Change KONG_DATABASE from "off" to "postgres"
# 4. Run migrations (first time only):
docker-compose exec -T kong kong migrations bootstrap

# 5. Remove old config
rm -f kong/data/lmdb/*

# 6. Restart
docker-compose restart kong
```

### To return to DB-less mode:

```bash
# 1. Edit docker-compose.yml
# 2. Change KONG_DATABASE back to "off"
# 3. Keep the kong.yml file
# 4. Restart
docker-compose restart kong
```

---

## ✨ Features Enabled

- ✓ Proxy traffic to upstream services
- ✓ Load balancing with health checks
- ✓ Authentication (key-auth, basic-auth, JWT, OAuth2+)
- ✓ Rate limiting and quota management
- ✓ Request/response transformation
- ✓ CORS support
- ✓ Logging and monitoring
- ✓ API versioning
- ✓ Service discovery
- ✓ Plugin system (Lua/Go/JavaScript)

---

## 📈 Next Steps

1. **Customize Configuration**: Edit `kong.yml` to add your services
2. **Test Your API**: Send requests through Kong proxy
3. **Add Authentication**: Configure JWT or API key auth
4. **Monitor Traffic**: Check Manager UI dashboards
5. **Scale Up**: Switch to PostgreSQL for production

---

## 💡 Tips and Best Practices

1. **Always backup `kong.yml`** before making changes
2. **Test configuration changes** before deploying to production
3. **Monitor logs regularly** for errors and warnings
4. **Use health checks** to monitor upstream services
5. **Implement rate limiting** to protect backend services
6. **Enable CORS** only for trusted origins
7. **Use versioning** for APIs that change frequently

---

## 🎓 Learning Resources

- Understanding Kong concepts: Refer to official documentation
- YAML syntax: Kong uses standard YAML format
- Plugin development: Check plugin examples in Kong GitHub repo
- API security: Review Kong security best practices guide

---

**Deployment Date**: March 3, 2026  
**Kong Version**: Latest  
**Status**: ✅ Running and Healthy

For more help, refer to the comprehensive guide: `DOCKER_DEPLOYMENT.md`
