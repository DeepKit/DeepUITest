# Skills Development Guide

Create custom skills to extend UniFlow capabilities.

## Overview

Skills are external services that provide specialized functionality:
- **Python Skills** - Data processing, ML inference, file operations
- **Node.js Skills** - Web scraping, API integrations, text processing

Skills communicate via HTTP REST API and can be deployed independently.

---

## Python Skill Development

### Project Structure

```
my_skill/
├── main.py           # FastAPI application
├── skill.py          # Skill implementation
├── requirements.txt  # Dependencies
├── Dockerfile        # Container definition
└── tests/
    └── test_skill.py
```

### Basic Implementation

```python
# main.py
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Any, Dict, Optional
import traceback

app = FastAPI(title="My Custom Skill")

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
    """Implement your skill logic here"""
    # Example: text processing
    text = input_data.get("text", "")
    return {"word_count": len(text.split())}
```

### Advanced Python Skill

```python
# skill.py - Structured skill with validation
from pydantic import BaseModel, Field
from typing import List, Optional
import asyncio

class TextAnalysisInput(BaseModel):
    text: str = Field(..., min_length=1)
    language: str = Field(default="en")
    features: List[str] = Field(default=["sentiment", "entities"])

class TextAnalysisOutput(BaseModel):
    sentiment: Optional[dict] = None
    entities: Optional[List[dict]] = None
    summary: Optional[str] = None

class TextAnalysisSkill:
    def __init__(self):
        self.nlp = None  # Lazy load
    
    async def initialize(self):
        """Load models on startup"""
        import spacy
        self.nlp = spacy.load("en_core_web_sm")
    
    async def execute(self, input: TextAnalysisInput) -> TextAnalysisOutput:
        result = TextAnalysisOutput()
        doc = self.nlp(input.text)
        
        if "entities" in input.features:
            result.entities = [
                {"text": ent.text, "label": ent.label_}
                for ent in doc.ents
            ]
        
        if "sentiment" in input.features:
            # Placeholder - use actual sentiment model
            result.sentiment = {"score": 0.5, "label": "neutral"}
        
        return result

# main.py integration
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

### Dockerfile for Python

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

## Node.js Skill Development

### Project Structure

```
my_skill/
├── src/
�?  ├── index.js      # Express application
�?  └── skill.js      # Skill implementation
├── package.json
├── Dockerfile
└── tests/
    └── skill.test.js
```

### Basic Implementation

```javascript
// src/index.js
const express = require('express');
const { processSkill } = require('./skill');

const app = express();
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', skill: 'my_node_skill' });
});

// Skill execution
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
  console.log(`Skill running on port ${PORT}`);
});
```

```javascript
// src/skill.js
async function processSkill(input, context = {}) {
  // Example: web scraping skill
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

### Advanced Node.js Skill

```javascript
// src/skill.js - Structured skill with validation
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
    // Validate input
    const { error, value } = inputSchema.validate(input);
    if (error) throw new Error(`Validation: ${error.message}`);
    
    const { url, selectors, options } = value;
    
    // Check cache
    const cacheKey = `${url}:${JSON.stringify(selectors)}`;
    if (this.cache.has(cacheKey)) {
      return { ...this.cache.get(cacheKey), cached: true };
    }
    
    // Fetch and parse
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
      
      // Cache result
      this.cache.set(cacheKey, results);
      
      return results;
    } finally {
      await browser.close();
    }
  }
}

module.exports = new WebScraperSkill();
```

### Dockerfile for Node.js

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

## Skill API Contract

All skills must implement this HTTP API:

### Health Check

```
GET /health

Response:
{
  "status": "healthy",
  "skill": "skill_name",
  "version": "1.0.0"  // optional
}
```

### Execute

```
POST /execute
Content-Type: application/json

Request:
{
  "input": { ... },      // Skill-specific input
  "context": {           // Optional workflow context
    "workflow_id": "...",
    "step_id": "...",
    "execution_id": "..."
  }
}

Response (success):
{
  "success": true,
  "result": { ... }
}

Response (error):
{
  "success": false,
  "error": "Error message"
}
```

---

## Registration

### Configuration

Add skill to `uniflow.config.json`:

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

### Using in Workflow

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

## Best Practices

### 1. Input Validation

Always validate input early:

```python
from pydantic import BaseModel, validator

class MyInput(BaseModel):
    query: str
    limit: int = 10
    
    @validator('limit')
    def limit_range(cls, v):
        if not 1 <= v <= 100:
            raise ValueError('limit must be 1-100')
        return v
```

### 2. Error Handling

Return structured errors:

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
        return {"success": False, "error": f"Internal: {str(e)}"}
```

### 3. Timeout Handling

Implement proper timeouts:

```python
import asyncio

async def execute_with_timeout(input_data, timeout_seconds=30):
    try:
        return await asyncio.wait_for(
            process(input_data),
            timeout=timeout_seconds
        )
    except asyncio.TimeoutError:
        raise SkillError("TIMEOUT", "Execution timed out")
```

### 4. Logging

Add structured logging:

```python
import logging
import json

logger = logging.getLogger(__name__)

@app.post("/execute")
async def execute(request: SkillRequest):
    logger.info("Skill execution started", extra={
        "context": request.context,
        "input_keys": list(request.input.keys())
    })
    
    try:
        result = await process(request.input)
        logger.info("Skill execution completed")
        return {"success": True, "result": result}
    except Exception as e:
        logger.error("Skill execution failed", exc_info=True)
        return {"success": False, "error": str(e)}
```

### 5. Resource Management

Clean up resources properly:

```python
class ResourceManagedSkill:
    def __init__(self):
        self.connections = []
    
    async def startup(self):
        # Initialize connections
        pass
    
    async def shutdown(self):
        # Cleanup
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

## Testing

### Python Tests

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
        "input": {"text": "Hello world"}
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

### Node.js Tests

```javascript
// tests/skill.test.js
const request = require('supertest');
const app = require('../src/index');

describe('Skill API', () => {
  test('GET /health returns healthy', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('healthy');
  });
  
  test('POST /execute with valid input', async () => {
    const res = await request(app)
      .post('/execute')
      .send({ input: { url: 'https://example.com', selector: 'h1' } });
    
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });
});
```

---

## Deployment

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

## Example Skills

### Code Executor Skill

Execute code in sandboxed environment:

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
        raise ValueError(f"Unsupported language: {language}")
    
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

### Knowledge Search Skill

Search vector database:

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
