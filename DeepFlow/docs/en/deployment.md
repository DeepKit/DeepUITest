# Production Deployment Guide

Deploy UniFlow in production environments with Docker, Kubernetes, and cloud platforms.

## Architecture Overview

```
                    ┌─────────────────────�?
                    �?  Load Balancer     �?
                    �?  (nginx/traefik)   �?
                    └─────────┬───────────�?
                              �?
        ┌─────────────────────┼─────────────────────�?
        �?                    �?                    �?
        �?                    �?                    �?
┌───────────────�?   ┌───────────────�?   ┌───────────────�?
�? DeepBase      �?   �?  Python      �?   �?  Node.js     �?
�? (Delphi)     �?   �?  Skills      �?   �?  Skills      �?
└───────┬───────�?   └───────┬───────�?   └───────┬───────�?
        �?                    �?                    �?
        └─────────────────────┼─────────────────────�?
                              �?
                    ┌─────────▼───────────�?
                    �?  Database          �?
                    �?  (SQLite/Postgres) �?
                    └─────────────────────�?
```

---

## Prerequisites

- Docker 24.0+
- Docker Compose 2.20+ (for compose deployment)
- Kubernetes 1.28+ (for k8s deployment)
- 4GB+ RAM recommended

---

## Docker Deployment

### Build Images

```bash
# Build all services
docker compose build

# Or build individually
docker build -t uniflow-python-skills:latest ./Skills/Python
docker build -t uniflow-node-skills:latest ./Skills/NodeJS
```

### Production docker-compose.yml

```yaml
version: '3.8'

services:
  python-skills:
    image: uniflow-python-skills:latest
    build:
      context: ./Skills/Python
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - LOG_LEVEL=INFO
      - WORKERS=4
      - MAX_REQUESTS=1000
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  node-skills:
    image: uniflow-node-skills:latest
    build:
      context: ./Skills/NodeJS
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certs:/etc/nginx/certs:ro
    depends_on:
      - python-skills
      - node-skills
    restart: unless-stopped

networks:
  default:
    driver: bridge
```

### Nginx Configuration

```nginx
# nginx.conf
worker_processes auto;

events {
    worker_connections 1024;
}

http {
    upstream python_skills {
        least_conn;
        server python-skills:8000;
    }

    upstream node_skills {
        least_conn;
        server node-skills:3000;
    }

    server {
        listen 80;
        server_name _;

        # Redirect to HTTPS
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/certs/cert.pem;
        ssl_certificate_key /etc/nginx/certs/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

        # Python skills
        location /api/skills/python/ {
            proxy_pass http://python_skills/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
        }

        # Node.js skills
        location /api/skills/node/ {
            proxy_pass http://node_skills/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
        }

        # Health check
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
```

### Start Services

```bash
# Production start
docker compose -f docker-compose.yml up -d

# View logs
docker compose logs -f

# Scale services
docker compose up -d --scale python-skills=3
```

---

## Kubernetes Deployment

### Namespace

```yaml
# namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: uniflow
  labels:
    app.kubernetes.io/name: uniflow
```

### ConfigMap

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: uniflow-config
  namespace: uniflow
data:
  LOG_LEVEL: "INFO"
  PYTHON_WORKERS: "4"
  NODE_ENV: "production"
```

### Secrets

```yaml
# secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: uniflow-secrets
  namespace: uniflow
type: Opaque
stringData:
  OPENAI_API_KEY: "your-api-key"
  DATABASE_URL: "postgresql://user:pass@host:5432/uniflow"
```

### Python Skills Deployment

```yaml
# python-skills-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: python-skills
  namespace: uniflow
  labels:
    app: python-skills
spec:
  replicas: 3
  selector:
    matchLabels:
      app: python-skills
  template:
    metadata:
      labels:
        app: python-skills
    spec:
      containers:
      - name: python-skills
        image: ghcr.io/your-org/uniflow-python-skills:latest
        ports:
        - containerPort: 8000
        envFrom:
        - configMapRef:
            name: uniflow-config
        - secretRef:
            name: uniflow-secrets
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
          limits:
            cpu: "1000m"
            memory: "1Gi"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: python-skills
              topologyKey: kubernetes.io/hostname
---
apiVersion: v1
kind: Service
metadata:
  name: python-skills
  namespace: uniflow
spec:
  selector:
    app: python-skills
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
```

### Node.js Skills Deployment

```yaml
# node-skills-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: node-skills
  namespace: uniflow
  labels:
    app: node-skills
spec:
  replicas: 2
  selector:
    matchLabels:
      app: node-skills
  template:
    metadata:
      labels:
        app: node-skills
    spec:
      containers:
      - name: node-skills
        image: ghcr.io/your-org/uniflow-node-skills:latest
        ports:
        - containerPort: 3000
        envFrom:
        - configMapRef:
            name: uniflow-config
        - secretRef:
            name: uniflow-secrets
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 3
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: node-skills
  namespace: uniflow
spec:
  selector:
    app: node-skills
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
```

### Ingress

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: uniflow-ingress
  namespace: uniflow
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "60"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - uniflow.example.com
    secretName: uniflow-tls
  rules:
  - host: uniflow.example.com
    http:
      paths:
      - path: /api/skills/python
        pathType: Prefix
        backend:
          service:
            name: python-skills
            port:
              number: 8000
      - path: /api/skills/node
        pathType: Prefix
        backend:
          service:
            name: node-skills
            port:
              number: 3000
```

### Horizontal Pod Autoscaler

```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: python-skills-hpa
  namespace: uniflow
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: python-skills
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
```

### Deploy to Kubernetes

```bash
# Apply all configurations
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secrets.yaml
kubectl apply -f python-skills-deployment.yaml
kubectl apply -f node-skills-deployment.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml

# Check status
kubectl get pods -n uniflow
kubectl get svc -n uniflow
kubectl get hpa -n uniflow

# View logs
kubectl logs -f deployment/python-skills -n uniflow
```

---

## Environment Configuration

### Required Variables

```bash
# API Keys
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# Database
DATABASE_URL=postgresql://user:pass@host:5432/uniflow
# Or for SQLite
DATABASE_PATH=/data/uniflow.db

# Redis (for distributed sessions)
REDIS_URL=redis://host:6379/0

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
```

### Python Skills Environment

```bash
# Workers
WORKERS=4                    # Gunicorn workers (CPU * 2 + 1)
MAX_REQUESTS=1000           # Requests before worker restart
MAX_REQUESTS_JITTER=50      # Jitter to prevent simultaneous restart
TIMEOUT=60                  # Request timeout

# Performance
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
```

### Node.js Skills Environment

```bash
NODE_ENV=production
UV_THREADPOOL_SIZE=16       # For async I/O
NODE_OPTIONS="--max-old-space-size=512"
```

---

## Monitoring

### Prometheus Metrics

Add metrics endpoint to services:

```python
# Python with prometheus-fastapi-instrumentator
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()
Instrumentator().instrument(app).expose(app)
```

```javascript
// Node.js with prom-client
const promClient = require('prom-client');
const collectDefaultMetrics = promClient.collectDefaultMetrics;
collectDefaultMetrics();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(await promClient.register.metrics());
});
```

### Grafana Dashboard

Key metrics to monitor:
- Request rate and latency (p50, p95, p99)
- Error rate by endpoint
- CPU and memory usage
- Active connections
- Workflow execution duration
- Step success/failure rates

### Health Checks

```bash
# Check all services
curl http://localhost/api/skills/python/health
curl http://localhost/api/skills/node/health

# Kubernetes readiness
kubectl get pods -n uniflow
kubectl describe pod <pod-name> -n uniflow
```

---

## Security

### Network Policies

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: uniflow-network-policy
  namespace: uniflow
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8000
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 5432
```

### Pod Security

```yaml
# Add to deployment spec
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
containers:
- name: app
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
```

### API Authentication

```python
# Python FastAPI with API key auth
from fastapi import Depends, HTTPException, Security
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key")

async def verify_api_key(api_key: str = Security(api_key_header)):
    if api_key != os.environ.get("API_KEY"):
        raise HTTPException(status_code=403, detail="Invalid API key")
    return api_key

@app.post("/execute", dependencies=[Depends(verify_api_key)])
async def execute(request: SkillRequest):
    ...
```

---

## Backup & Recovery

### Database Backup

```bash
# PostgreSQL
pg_dump -h localhost -U uniflow -d uniflow > backup.sql

# SQLite
sqlite3 uniflow.db ".backup 'backup.db'"

# Automated backup script
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME | gzip > /backups/uniflow_$DATE.sql.gz
find /backups -name "uniflow_*.sql.gz" -mtime +7 -delete
```

### Kubernetes Backup

```bash
# Backup secrets and configmaps
kubectl get secret uniflow-secrets -n uniflow -o yaml > secrets-backup.yaml
kubectl get configmap uniflow-config -n uniflow -o yaml > config-backup.yaml
```

---

## Troubleshooting

### Common Issues

**Services not starting**
```bash
# Check logs
docker compose logs python-skills
kubectl logs -f deployment/python-skills -n uniflow

# Check resources
docker stats
kubectl top pods -n uniflow
```

**High latency**
```bash
# Check connection pool
# Add to Python
SQLALCHEMY_POOL_SIZE=10
SQLALCHEMY_MAX_OVERFLOW=20

# Check timeout settings
# Increase if needed
TIMEOUT=120
```

**Memory issues**
```bash
# Python memory profiling
pip install memory-profiler
python -m memory_profiler main.py

# Node.js heap analysis
node --inspect main.js
# Connect Chrome DevTools
```

### Debug Mode

```bash
# Enable debug logging
LOG_LEVEL=DEBUG docker compose up

# Python debug
PYTHONDEBUG=1 uvicorn main:app --reload

# Node.js debug  
DEBUG=* node src/index.js
```

---

## Performance Tuning

### Python Skills

```python
# Use connection pooling
from sqlalchemy import create_engine
engine = create_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True
)

# Async where possible
import asyncio
from concurrent.futures import ThreadPoolExecutor

executor = ThreadPoolExecutor(max_workers=4)

async def cpu_bound_task(data):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, process_sync, data)
```

### Node.js Skills

```javascript
// Use cluster mode
const cluster = require('cluster');
const numCPUs = require('os').cpus().length;

if (cluster.isPrimary) {
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork();
  }
} else {
  require('./index');
}

// Connection pooling for databases
const { Pool } = require('pg');
const pool = new Pool({
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

### Caching

```python
# Redis caching
import redis
from functools import wraps

redis_client = redis.from_url(os.environ.get("REDIS_URL"))

def cached(ttl=300):
    def decorator(func):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            key = f"{func.__name__}:{hash(str(args) + str(kwargs))}"
            cached = redis_client.get(key)
            if cached:
                return json.loads(cached)
            result = await func(*args, **kwargs)
            redis_client.setex(key, ttl, json.dumps(result))
            return result
        return wrapper
    return decorator
```

---

## Checklist

### Pre-deployment

- [ ] All environment variables configured
- [ ] SSL certificates installed
- [ ] Database migrations applied
- [ ] Health checks passing
- [ ] Resource limits set
- [ ] Logging configured
- [ ] Monitoring enabled

### Post-deployment

- [ ] Services responding on endpoints
- [ ] Metrics being collected
- [ ] Alerts configured
- [ ] Backup schedule active
- [ ] Documentation updated
