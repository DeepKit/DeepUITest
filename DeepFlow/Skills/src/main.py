"""
UniFlow Skills Service
======================
FastAPI-based microservice for executing Skills in UniFlow workflows.

Features:
- RESTful API for Skill execution
- Hot-reload Skill support
- LLM integration via LiteLLM
- Sandboxed code execution
- Health monitoring & metrics
"""

import asyncio
import os
import sys
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import structlog

from .skills.base import SkillRegistry, SkillResult, SkillStatus
from .skills.code_executor import CodeExecutorSkill
from .llm.client import LLMClient, LLMConfig

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

APP_NAME = "UniFlow Skills Service"
APP_VERSION = "1.0.0"
APP_ENV = os.getenv("APP_ENV", "development")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")

# Configure structured logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer()
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)

# -----------------------------------------------------------------------------
# Request/Response Models
# -----------------------------------------------------------------------------

class SkillRequest(BaseModel):
    """Request model for Skill execution."""
    skill_name: str = Field(..., description="Name of the Skill to execute")
    params: Dict[str, Any] = Field(default_factory=dict, description="Skill parameters")
    context: Dict[str, Any] = Field(default_factory=dict, description="Execution context")
    timeout_ms: int = Field(default=30000, ge=100, le=300000, description="Timeout in milliseconds")
    
class SkillResponse(BaseModel):
    """Response model for Skill execution."""
    skill_name: str
    status: str
    result: Optional[Any] = None
    error: Optional[str] = None
    execution_time_ms: int
    timestamp: str = Field(default_factory=lambda: datetime.utcnow().isoformat())

class LLMRequest(BaseModel):
    """Request model for LLM calls."""
    model: str = Field(default="gpt-4o-mini", description="Model name")
    messages: List[Dict[str, str]] = Field(..., description="Chat messages")
    temperature: float = Field(default=0.7, ge=0, le=2)
    max_tokens: int = Field(default=4096, ge=1, le=128000)
    stream: bool = Field(default=False)

class LLMResponse(BaseModel):
    """Response model for LLM calls."""
    content: str
    model: str
    usage: Dict[str, int]
    finish_reason: str

class HealthResponse(BaseModel):
    """Health check response."""
    status: str
    version: str
    environment: str
    timestamp: str
    skills_loaded: int

class SkillInfo(BaseModel):
    """Skill information."""
    name: str
    description: str
    version: str
    parameters: Dict[str, Any]

# -----------------------------------------------------------------------------
# Application State
# -----------------------------------------------------------------------------

class AppState:
    """Global application state."""
    def __init__(self):
        self.skill_registry: SkillRegistry = SkillRegistry()
        self.llm_client: Optional[LLMClient] = None
        self.start_time: datetime = datetime.utcnow()
        
    async def initialize(self):
        """Initialize application components."""
        logger.info("Initializing application state")
        
        # Initialize LLM client
        llm_config = LLMConfig(
            api_key=os.getenv("OPENAI_API_KEY", ""),
            default_model=os.getenv("DEFAULT_LLM_MODEL", "gpt-4o-mini"),
            timeout=30.0,
            max_retries=3
        )
        self.llm_client = LLMClient(llm_config)
        
        # Register built-in Skills
        self._register_builtin_skills()
        
        logger.info(
            "Application initialized",
            skills_count=len(self.skill_registry.list_skills())
        )
        
    def _register_builtin_skills(self):
        """Register built-in Skills."""
        # Code Executor Skill
        code_executor = CodeExecutorSkill()
        self.skill_registry.register(code_executor)
        
        logger.info(f"Registered built-in skill: {code_executor.name}")
        
    async def shutdown(self):
        """Cleanup on shutdown."""
        logger.info("Shutting down application")
        if self.llm_client:
            await self.llm_client.close()

app_state = AppState()

# -----------------------------------------------------------------------------
# Application Lifecycle
# -----------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan manager."""
    # Startup
    await app_state.initialize()
    yield
    # Shutdown
    await app_state.shutdown()

# -----------------------------------------------------------------------------
# FastAPI Application
# -----------------------------------------------------------------------------

app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
    description="Microservice for executing Skills in UniFlow workflows",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -----------------------------------------------------------------------------
# Exception Handlers
# -----------------------------------------------------------------------------

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Global exception handler."""
    logger.error(
        "Unhandled exception",
        error=str(exc),
        path=request.url.path,
        method=request.method
    )
    # SECURITY: Only include error details in development mode
    if APP_ENV == "development":
        content = {"detail": "Internal server error", "error": str(exc)}
    else:
        content = {"detail": "Internal server error"}
    
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=content
    )

# -----------------------------------------------------------------------------
# API Endpoints
# -----------------------------------------------------------------------------

@app.get("/health", response_model=HealthResponse, tags=["System"])
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        status="healthy",
        version=APP_VERSION,
        environment=APP_ENV,
        timestamp=datetime.utcnow().isoformat(),
        skills_loaded=len(app_state.skill_registry.list_skills())
    )

@app.get("/skills", response_model=List[SkillInfo], tags=["Skills"])
async def list_skills():
    """List all available Skills."""
    skills = []
    for skill in app_state.skill_registry.list_skills():
        skills.append(SkillInfo(
            name=skill.name,
            description=skill.description,
            version=skill.version,
            parameters=skill.get_parameter_schema()
        ))
    return skills

@app.get("/skills/{skill_name}", response_model=SkillInfo, tags=["Skills"])
async def get_skill(skill_name: str):
    """Get information about a specific Skill."""
    skill = app_state.skill_registry.get(skill_name)
    if not skill:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Skill '{skill_name}' not found"
        )
    return SkillInfo(
        name=skill.name,
        description=skill.description,
        version=skill.version,
        parameters=skill.get_parameter_schema()
    )

@app.post("/skills/execute", response_model=SkillResponse, tags=["Skills"])
async def execute_skill(request: SkillRequest):
    """Execute a Skill."""
    start_time = datetime.utcnow()
    
    logger.info(
        "Executing skill",
        skill_name=request.skill_name,
        timeout_ms=request.timeout_ms
    )
    
    # Get skill
    skill = app_state.skill_registry.get(request.skill_name)
    if not skill:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Skill '{request.skill_name}' not found"
        )
    
    # Execute with timeout
    try:
        timeout_sec = request.timeout_ms / 1000.0
        result = await asyncio.wait_for(
            skill.execute(request.params, request.context),
            timeout=timeout_sec
        )
    except asyncio.TimeoutError:
        execution_time = int((datetime.utcnow() - start_time).total_seconds() * 1000)
        logger.warning(
            "Skill execution timeout",
            skill_name=request.skill_name,
            timeout_ms=request.timeout_ms
        )
        return SkillResponse(
            skill_name=request.skill_name,
            status=SkillStatus.TIMEOUT.value,
            error=f"Execution timed out after {request.timeout_ms}ms",
            execution_time_ms=execution_time
        )
    except Exception as e:
        execution_time = int((datetime.utcnow() - start_time).total_seconds() * 1000)
        logger.error(
            "Skill execution error",
            skill_name=request.skill_name,
            error=str(e)
        )
        return SkillResponse(
            skill_name=request.skill_name,
            status=SkillStatus.ERROR.value,
            error=str(e),
            execution_time_ms=execution_time
        )
    
    execution_time = int((datetime.utcnow() - start_time).total_seconds() * 1000)
    
    logger.info(
        "Skill executed successfully",
        skill_name=request.skill_name,
        execution_time_ms=execution_time
    )
    
    return SkillResponse(
        skill_name=request.skill_name,
        status=result.status.value,
        result=result.data,
        error=result.error,
        execution_time_ms=execution_time
    )

@app.post("/llm/chat", response_model=LLMResponse, tags=["LLM"])
async def llm_chat(request: LLMRequest):
    """Call LLM for chat completion."""
    if not app_state.llm_client:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LLM client not initialized"
        )
    
    logger.info(
        "LLM chat request",
        model=request.model,
        messages_count=len(request.messages)
    )
    
    try:
        response = await app_state.llm_client.chat(
            messages=request.messages,
            model=request.model,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        return LLMResponse(
            content=response.content,
            model=response.model,
            usage=response.usage,
            finish_reason=response.finish_reason
        )
    except Exception as e:
        logger.error("LLM chat error", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"LLM call failed: {str(e)}"
        )

@app.get("/metrics", tags=["System"])
async def get_metrics():
    """Get application metrics (Prometheus format)."""
    uptime = (datetime.utcnow() - app_state.start_time).total_seconds()
    
    metrics = [
        f"# HELP uniflow_skills_uptime_seconds Service uptime in seconds",
        f"# TYPE uniflow_skills_uptime_seconds gauge",
        f"uniflow_skills_uptime_seconds {uptime}",
        f"",
        f"# HELP uniflow_skills_loaded Number of loaded skills",
        f"# TYPE uniflow_skills_loaded gauge",
        f"uniflow_skills_loaded {len(app_state.skill_registry.list_skills())}",
    ]
    
    return "\n".join(metrics)

# -----------------------------------------------------------------------------
# Entry Point
# -----------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "src.main:app",
        host="0.0.0.0",
        port=8000,
        reload=APP_ENV == "development"
    )
