# 生产部署指南

使用 Docker、Kubernetes 和云平台部署 UniFlow 到生产环境�?

## 架构概览

```
                    ┌─────────────────────�?
                    �?   负载均衡�?      �?
                    �?  (nginx/traefik)   �?
                    └─────────┬───────────�?
                              �?
        ┌─────────────────────┼─────────────────────�?
        �?                    �?                    �?
        �?                    �?                    �?
┌───────────────�?   ┌───────────────�?   ┌───────────────�?
�?  DeepBase     �?   �?   Python     �?   �?  Node.js     �?
�?  (Delphi)    �?   �?   Skills     �?   �?   Skills     �?
└───────┬───────�?   └───────┬───────�?   └───────┬───────�?
        �?                    �?                    �?
        └─────────────────────┼─────────────────────�?
                              �?
                    ┌─────────▼───────────�?
                    �?     数据�?        �?
                    �? (SQLite/Postgres)  �?
                    └─────────────────────�?
```

---

## 前置条件

- Docker 24.0+
- Docker Compose 2.20+（用�?Compose 部署�?
- Kubernetes 1.28+（用�?K8s 部署�?
- 建议 4GB+ 内存

---

## Docker 部署

### 构建镜像

```bash
# 构建所有服�?
docker compose build

# 或单独构�?
docker build -t uniflow-python-skills:latest ./Skills/Python
docker build -t uniflow-node-skills:latest ./Skills/NodeJS
```

### 生产环境 docker-compose.yml

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

### Nginx 配置

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

        # 重定向到 HTTPS
        return 301 https://$host$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/certs/cert.pem;
        ssl_certificate_key /etc/nginx/certs/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;

        # Python Skills
        location /api/skills/python/ {
            proxy_pass http://python_skills/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
        }

        # Node.js Skills
        location /api/skills/node/ {
            proxy_pass http://node_skills/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 60s;
        }

        # 健康检�?
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
```

### 启动服务

```bash
# 生产环境启动
docker compose -f docker-compose.yml up -d

# 查看日志
docker compose logs -f

# 扩展服务
docker compose up -d --scale python-skills=3
```

---

## Kubernetes 部署

### 命名空间

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

### Python Skills 部署

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

### Node.js Skills 部署

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

### 水平 Pod 自动扩缩

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

### 部署�?Kubernetes

```bash
# 应用所有配�?
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
kubectl apply -f secrets.yaml
kubectl apply -f python-skills-deployment.yaml
kubectl apply -f node-skills-deployment.yaml
kubectl apply -f ingress.yaml
kubectl apply -f hpa.yaml

# 检查状�?
kubectl get pods -n uniflow
kubectl get svc -n uniflow
kubectl get hpa -n uniflow

# 查看日志
kubectl logs -f deployment/python-skills -n uniflow
```

---

## 环境配置

### 必需变量

```bash
# API 密钥
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# 数据�?
DATABASE_URL=postgresql://user:pass@host:5432/uniflow
# 或使�?SQLite
DATABASE_PATH=/data/uniflow.db

# Redis（用于分布式会话�?
REDIS_URL=redis://host:6379/0

# 日志
LOG_LEVEL=INFO
LOG_FORMAT=json
```

### Python Skills 环境

```bash
# 工作进程
WORKERS=4                    # Gunicorn 工作进程数（CPU * 2 + 1�?
MAX_REQUESTS=1000           # 工作进程重启前的请求�?
MAX_REQUESTS_JITTER=50      # 防止同时重启的抖�?
TIMEOUT=60                  # 请求超时

# 性能
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
```

### Node.js Skills 环境

```bash
NODE_ENV=production
UV_THREADPOOL_SIZE=16       # 用于异步 I/O
NODE_OPTIONS="--max-old-space-size=512"
```

---

## 监控

### Prometheus 指标

为服务添加指标端点：

```python
# Python 使用 prometheus-fastapi-instrumentator
from prometheus_fastapi_instrumentator import Instrumentator

app = FastAPI()
Instrumentator().instrument(app).expose(app)
```

```javascript
// Node.js 使用 prom-client
const promClient = require('prom-client');
const collectDefaultMetrics = promClient.collectDefaultMetrics;
collectDefaultMetrics();

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(await promClient.register.metrics());
});
```

### Grafana 仪表�?

监控的关键指标：
- 请求速率和延迟（p50、p95、p99�?
- 按端点的错误�?
- CPU 和内存使用率
- 活动连接�?
- 工作流执行时�?
- 步骤成功/失败�?

### 健康检�?

```bash
# 检查所有服�?
curl http://localhost/api/skills/python/health
curl http://localhost/api/skills/node/health

# Kubernetes 就绪状�?
kubectl get pods -n uniflow
kubectl describe pod <pod-name> -n uniflow
```

---

## 安全

### 网络策略

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

### Pod 安全

```yaml
# 添加到部�?spec
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

### API 认证

```python
# Python FastAPI 使用 API 密钥认证
from fastapi import Depends, HTTPException, Security
from fastapi.security import APIKeyHeader

api_key_header = APIKeyHeader(name="X-API-Key")

async def verify_api_key(api_key: str = Security(api_key_header)):
    if api_key != os.environ.get("API_KEY"):
        raise HTTPException(status_code=403, detail="无效�?API 密钥")
    return api_key

@app.post("/execute", dependencies=[Depends(verify_api_key)])
async def execute(request: SkillRequest):
    ...
```

---

## 备份与恢�?

### 数据库备�?

```bash
# PostgreSQL
pg_dump -h localhost -U uniflow -d uniflow > backup.sql

# SQLite
sqlite3 uniflow.db ".backup 'backup.db'"

# 自动备份脚本
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME | gzip > /backups/uniflow_$DATE.sql.gz
find /backups -name "uniflow_*.sql.gz" -mtime +7 -delete
```

### Kubernetes 备份

```bash
# 备份 Secrets �?ConfigMaps
kubectl get secret uniflow-secrets -n uniflow -o yaml > secrets-backup.yaml
kubectl get configmap uniflow-config -n uniflow -o yaml > config-backup.yaml
```

---

## 故障排除

### 常见问题

**服务无法启动**
```bash
# 检查日�?
docker compose logs python-skills
kubectl logs -f deployment/python-skills -n uniflow

# 检查资�?
docker stats
kubectl top pods -n uniflow
```

**高延�?*
```bash
# 检查连接池
# 添加�?Python
SQLALCHEMY_POOL_SIZE=10
SQLALCHEMY_MAX_OVERFLOW=20

# 检查超时设�?
# 如需要则增加
TIMEOUT=120
```

**内存问题**
```bash
# Python 内存分析
pip install memory-profiler
python -m memory_profiler main.py

# Node.js 堆分�?
node --inspect main.js
# 连接 Chrome DevTools
```

### 调试模式

```bash
# 启用调试日志
LOG_LEVEL=DEBUG docker compose up

# Python 调试
PYTHONDEBUG=1 uvicorn main:app --reload

# Node.js 调试
DEBUG=* node src/index.js
```

---

## 性能调优

### Python Skills

```python
# 使用连接�?
from sqlalchemy import create_engine
engine = create_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_pre_ping=True
)

# 尽可能使用异�?
import asyncio
from concurrent.futures import ThreadPoolExecutor

executor = ThreadPoolExecutor(max_workers=4)

async def cpu_bound_task(data):
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(executor, process_sync, data)
```

### Node.js Skills

```javascript
// 使用集群模式
const cluster = require('cluster');
const numCPUs = require('os').cpus().length;

if (cluster.isPrimary) {
  for (let i = 0; i < numCPUs; i++) {
    cluster.fork();
  }
} else {
  require('./index');
}

// 数据库连接池
const { Pool } = require('pg');
const pool = new Pool({
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

### 缓存

```python
# Redis 缓存
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

## 检查清�?

### 部署�?

- [ ] 所有环境变量已配置
- [ ] SSL 证书已安�?
- [ ] 数据库迁移已执行
- [ ] 健康检查通过
- [ ] 资源限制已设�?
- [ ] 日志已配�?
- [ ] 监控已启�?

### 部署�?

- [ ] 服务在端点正常响�?
- [ ] 指标正在收集
- [ ] 告警已配�?
- [ ] 备份计划已激�?
- [ ] 文档已更�?
