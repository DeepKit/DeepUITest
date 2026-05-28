# Skill 开发指�?

创建自定�?Skill 来扩�?UniFlow 功能�?

## 概述

Skill 是提供专门功能的外部服务�?
- **Python Skill** - 数据处理、ML 推理、文件操�?
- **Node.js Skill** - 网页抓取、API 集成、文本处�?

Skill 通过 HTTP REST API 通信，可以独立部署�?

---

## Python Skill 开�?

### 项目结构

```
my_skill/
├── main.py           # FastAPI 应用
├── skill.py          # Skill 实现
├── requirements.txt  # 依赖
├── Dockerfile        # 容器定义
└── tests/
    └── test_skill.py
```

### 基础实现

```python
# main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Any, Dict, Optional
import traceback

app = FastAPI(title="我的自定�?Skill")

class SkillRequest(BaseModel):
    input: Dict[str, Any]
    context: Optional[Dict[str, Any]] = None

class SkillResponse(BaseModel):
    success: bool
    result: Optional[Any] = None
    error: Optional[str] = None

@app.get("/health")
async def health():
    return {"status": "healthy", "skill": "my_custom_skill"}

@app.post("/execute", response_model=SkillResponse)
async def execute(request: SkillRequest):
    try:
        result = process(request.input)
        return SkillResponse(success=True, result=result)
    except Exception as e:
        return SkillResponse(success=False, error=str(e))

def process(input_data: Dict[str, Any]) -> Any:
    """在这里实现你�?Skill 逻辑"""
    # 示例：文本处�?
    text = input_data.get("text", "")
    return {"word_count": len(text.split())}
```

### 高级 Python Skill

```python
# skill.py - 带验证的结构�?Skill
from pydantic import BaseModel, Field
from typing import List, Optional
import asyncio

class TextAnalysisInput(BaseModel):
    text: str = Field(..., min_length=1)
    language: str = Field(default="zh")
    features: List[str] = Field(default=["sentiment", "entities"])

class TextAnalysisOutput(BaseModel):
    sentiment: Optional[dict] = None
    entities: Optional[List[dict]] = None
    summary: Optional[str] = None

class TextAnalysisSkill:
    def __init__(self):
        self.nlp = None  # 延迟加载
    
    async def initialize(self):
        """启动时加载模�?""
        import spacy
        self.nlp = spacy.load("zh_core_web_sm")
    
    async def execute(self, input: TextAnalysisInput) -> TextAnalysisOutput:
        result = TextAnalysisOutput()
        doc = self.nlp(input.text)
        
        if "entities" in input.features:
            result.entities = [
                {"text": ent.text, "label": ent.label_}
                for ent in doc.ents
            ]
        
        if "sentiment" in input.features:
            # 占位�?- 使用实际的情感模�?
            result.sentiment = {"score": 0.5, "label": "neutral"}
        
        return result

# main.py 集成
skill_instance = TextAnalysisSkill()

@app.on_event("startup")
async def startup():
    await skill_instance.initialize()

@app.post("/execute")
async def execute(request: SkillRequest):
    input_data = TextAnalysisInput(**request.input)
    result = await skill_instance.execute(input_data)
    return SkillResponse(success=True, result=result.dict())
```

### Python Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Node.js Skill 开�?

### 项目结构

```
my_skill/
├── src/
�?  ├── index.js      # Express 应用
�?  └── skill.js      # Skill 实现
├── package.json
├── Dockerfile
└── tests/
    └── skill.test.js
```

### 基础实现

```javascript
// src/index.js
const express = require('express');
const { processSkill } = require('./skill');

const app = express();
app.use(express.json());

// 健康检�?
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', skill: 'my_node_skill' });
});

// Skill 执行
app.post('/execute', async (req, res) => {
  try {
    const { input, context } = req.body;
    const result = await processSkill(input, context);
    res.json({ success: true, result });
  } catch (error) {
    res.json({ success: false, error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Skill 运行在端�?${PORT}`);
});
```

```javascript
// src/skill.js
async function processSkill(input, context = {}) {
  // 示例：网页抓�?Skill
  const { url, selector } = input;
  
  const axios = require('axios');
  const cheerio = require('cheerio');
  
  const response = await axios.get(url, { timeout: 10000 });
  const $ = cheerio.load(response.data);
  
  const elements = $(selector).map((i, el) => $(el).text()).get();
  
  return {
    url,
    count: elements.length,
    items: elements
  };
}

module.exports = { processSkill };
```

### 高级 Node.js Skill

```javascript
// src/skill.js - 带验证的结构�?Skill
const Joi = require('joi');

const inputSchema = Joi.object({
  url: Joi.string().uri().required(),
  selectors: Joi.object().pattern(Joi.string(), Joi.string()).required(),
  options: Joi.object({
    timeout: Joi.number().default(10000),
    userAgent: Joi.string(),
    waitFor: Joi.number()
  }).default({})
});

class WebScraperSkill {
  constructor() {
    this.cache = new Map();
  }
  
  async execute(input) {
    // 验证输入
    const { error, value } = inputSchema.validate(input);
    if (error) throw new Error(`验证失败: ${error.message}`);
    
    const { url, selectors, options } = value;
    
    // 检查缓�?
    const cacheKey = `${url}:${JSON.stringify(selectors)}`;
    if (this.cache.has(cacheKey)) {
      return { ...this.cache.get(cacheKey), cached: true };
    }
    
    // 获取并解�?
    const puppeteer = require('puppeteer');
    const browser = await puppeteer.launch({ headless: 'new' });
    
    try {
      const page = await browser.newPage();
      if (options.userAgent) {
        await page.setUserAgent(options.userAgent);
      }
      
      await page.goto(url, { timeout: options.timeout });
      
      if (options.waitFor) {
        await page.waitForTimeout(options.waitFor);
      }
      
      const results = {};
      for (const [key, selector] of Object.entries(selectors)) {
        results[key] = await page.$$eval(selector, els => 
          els.map(el => el.textContent.trim())
        );
      }
      
      // 缓存结果
      this.cache.set(cacheKey, results);
      
      return results;
    } finally {
      await browser.close();
    }
  }
}

module.exports = new WebScraperSkill();
```

### Node.js Dockerfile

```dockerfile
FROM node:20-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3000

CMD ["node", "src/index.js"]
```

---

## Skill API 契约

所�?Skill 必须实现以下 HTTP API�?

### 健康检�?

```
GET /health

响应�?
{
  "status": "healthy",
  "skill": "skill_name",
  "version": "1.0.0"  // 可�?
}
```

### 执行

```
POST /execute
Content-Type: application/json

请求�?
{
  "input": { ... },      // Skill 特定输入
  "context": {           // 可选的工作流上下文
    "workflow_id": "...",
    "step_id": "...",
    "execution_id": "..."
  }
}

响应（成功）�?
{
  "success": true,
  "result": { ... }
}

响应（错误）�?
{
  "success": false,
  "error": "错误消息"
}
```

---

## 注册

### 配置

�?`uniflow.config.json` 中添�?Skill�?

```json
{
  "skills": {
    "my_skill": {
      "url": "http://localhost:8000",
      "timeout": 30000,
      "retry": {
        "max_retries": 3,
        "backoff_ms": 1000
      }
    }
  }
}
```

### 在工作流中使�?

```json
{
  "id": "use-skill",
  "type": "action",
  "action": {
    "type": "skill",
    "skill": "my_skill",
    "input": {
      "text": "{{ vars.user_text }}"
    }
  },
  "output": {
    "target": "skill_result"
  }
}
```

---

## 最佳实�?

### 1. 输入验证

尽早验证输入�?

```python
from pydantic import BaseModel, validator

class MyInput(BaseModel):
    query: str
    limit: int = 10
    
    @validator('limit')
    def limit_range(cls, v):
        if not 1 <= v <= 100:
            raise ValueError('limit 必须�?1-100 之间')
        return v
```

### 2. 错误处理

返回结构化错误：

```python
class SkillError(Exception):
    def __init__(self, code: str, message: str, details: dict = None):
        self.code = code
        self.message = message
        self.details = details or {}

@app.post("/execute")
async def execute(request: SkillRequest):
    try:
        result = await process(request.input)
        return {"success": True, "result": result}
    except SkillError as e:
        return {
            "success": False, 
            "error": e.message,
            "error_code": e.code,
            "details": e.details
        }
    except Exception as e:
        return {"success": False, "error": f"内部错误: {str(e)}"}
```

### 3. 超时处理

实现正确的超时：

```python
import asyncio

async def execute_with_timeout(input_data, timeout_seconds=30):
    try:
        return await asyncio.wait_for(
            process(input_data),
            timeout=timeout_seconds
        )
    except asyncio.TimeoutError:
        raise SkillError("TIMEOUT", "执行超时")
```

### 4. 日志记录

添加结构化日志：

```python
import logging
import json

logger = logging.getLogger(__name__)

@app.post("/execute")
async def execute(request: SkillRequest):
    logger.info("Skill 执行开�?, extra={
        "context": request.context,
        "input_keys": list(request.input.keys())
    })
    
    try:
        result = await process(request.input)
        logger.info("Skill 执行完成")
        return {"success": True, "result": result}
    except Exception as e:
        logger.error("Skill 执行失败", exc_info=True)
        return {"success": False, "error": str(e)}
```

### 5. 资源管理

正确清理资源�?

```python
class ResourceManagedSkill:
    def __init__(self):
        self.connections = []
    
    async def startup(self):
        # 初始化连�?
        pass
    
    async def shutdown(self):
        # 清理
        for conn in self.connections:
            await conn.close()

skill = ResourceManagedSkill()

@app.on_event("startup")
async def startup():
    await skill.startup()

@app.on_event("shutdown")
async def shutdown():
    await skill.shutdown()
```

---

## 测试

### Python 测试

```python
# tests/test_skill.py
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_execute_success():
    response = client.post("/execute", json={
        "input": {"text": "你好世界"}
    })
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is True
    assert "result" in data

def test_execute_invalid_input():
    response = client.post("/execute", json={
        "input": {}
    })
    data = response.json()
    assert data["success"] is False
```

### Node.js 测试

```javascript
// tests/skill.test.js
const request = require('supertest');
const app = require('../src/index');

describe('Skill API', () => {
  test('GET /health 返回 healthy', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
  
  test('POST /execute 使用有效输入', async () => {
    const res = await request(app)
      .post('/execute')
      .send({ input: { url: 'https://example.com', selector: 'h1' } });
    
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
```

---

## 部署

### Docker Compose

```yaml
version: '3.8'

services:
  my-python-skill:
    build: ./skills/my-python-skill
    ports:
      - "8001:8000"
    environment:
      - LOG_LEVEL=INFO
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
  
  my-node-skill:
    build: ./skills/my-node-skill
    ports:
      - "8002:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### Kubernetes

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-skill
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-skill
  template:
    metadata:
      labels:
        app: my-skill
    spec:
      containers:
      - name: skill
        image: my-skill:latest
        ports:
        - containerPort: 8000
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 10
          periodSeconds: 30
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: my-skill
spec:
  selector:
    app: my-skill
  ports:
  - port: 8000
    targetPort: 8000
```

---

## 示例 Skill

### 代码执行 Skill

在沙箱环境中执行代码�?

```python
# skill.py
import subprocess
import tempfile
import os

SUPPORTED_LANGUAGES = {
    'python': {'ext': '.py', 'cmd': ['python3']},
    'javascript': {'ext': '.js', 'cmd': ['node']},
}

async def execute_code(language: str, code: str, timeout: int = 30):
    if language not in SUPPORTED_LANGUAGES:
        raise ValueError(f"不支持的语言: {language}")
    
    config = SUPPORTED_LANGUAGES[language]
    
    with tempfile.NamedTemporaryFile(
        mode='w', suffix=config['ext'], delete=False
    ) as f:
        f.write(code)
        f.flush()
        
        try:
            result = subprocess.run(
                config['cmd'] + [f.name],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return {
                'stdout': result.stdout,
                'stderr': result.stderr,
                'exit_code': result.returncode
            }
        finally:
            os.unlink(f.name)
```

### 知识搜索 Skill

搜索向量数据库：

```python
# skill.py
from sentence_transformers import SentenceTransformer
import chromadb

class KnowledgeSearchSkill:
    def __init__(self):
        self.model = SentenceTransformer('all-MiniLM-L6-v2')
        self.client = chromadb.Client()
        self.collection = self.client.get_or_create_collection("knowledge")
    
    async def search(self, query: str, limit: int = 5):
        embedding = self.model.encode(query).tolist()
        results = self.collection.query(
            query_embeddings=[embedding],
            n_results=limit
        )
        return {
            'documents': results['documents'][0],
            'distances': results['distances'][0]
        }
```
