"""
UniFlow Skills Base Module
==========================
Base classes and registry for Skills.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional, Type
import structlog

logger = structlog.get_logger(__name__)

# -----------------------------------------------------------------------------
# Enums
# -----------------------------------------------------------------------------

class SkillStatus(Enum):
    """Skill execution status."""
    SUCCESS = "success"
    ERROR = "error"
    TIMEOUT = "timeout"
    CANCELLED = "cancelled"
    PENDING = "pending"

class SkillCategory(Enum):
    """Skill categories."""
    CODE = "code"
    LLM = "llm"
    DATA = "data"
    IO = "io"
    UTILITY = "utility"
    CUSTOM = "custom"

# -----------------------------------------------------------------------------
# Data Classes
# -----------------------------------------------------------------------------

@dataclass
class SkillResult:
    """Result of Skill execution."""
    status: SkillStatus
    data: Optional[Any] = None
    error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    @classmethod
    def success(cls, data: Any, metadata: Optional[Dict[str, Any]] = None) -> "SkillResult":
        """Create a success result."""
        return cls(
            status=SkillStatus.SUCCESS,
            data=data,
            metadata=metadata or {}
        )
    
    @classmethod
    def failure(cls, error: str, metadata: Optional[Dict[str, Any]] = None) -> "SkillResult":
        """Create a failure result."""
        return cls(
            status=SkillStatus.ERROR,
            error=error,
            metadata=metadata or {}
        )

@dataclass
class SkillParameter:
    """Skill parameter definition."""
    name: str
    type: str
    description: str
    required: bool = True
    default: Any = None
    
    def to_schema(self) -> Dict[str, Any]:
        """Convert to JSON schema format."""
        schema = {
            "type": self.type,
            "description": self.description
        }
        if self.default is not None:
            schema["default"] = self.default
        return schema

# -----------------------------------------------------------------------------
# Base Skill Class
# -----------------------------------------------------------------------------

class BaseSkill(ABC):
    """
    Abstract base class for all Skills.
    
    Subclasses must implement:
    - execute(): The main execution logic
    - get_parameter_schema(): Parameter definitions
    """
    
    def __init__(
        self,
        name: str,
        description: str,
        version: str = "1.0.0",
        category: SkillCategory = SkillCategory.CUSTOM,
        parameters: Optional[List[SkillParameter]] = None
    ):
        self._name = name
        self._description = description
        self._version = version
        self._category = category
        self._parameters = parameters or []
        
    @property
    def name(self) -> str:
        """Skill name."""
        return self._name
    
    @property
    def description(self) -> str:
        """Skill description."""
        return self._description
    
    @property
    def version(self) -> str:
        """Skill version."""
        return self._version
    
    @property
    def category(self) -> SkillCategory:
        """Skill category."""
        return self._category
    
    def get_parameter_schema(self) -> Dict[str, Any]:
        """
        Get parameter schema for this Skill.
        
        Returns:
            JSON Schema compatible parameter definition
        """
        properties = {}
        required = []
        
        for param in self._parameters:
            properties[param.name] = param.to_schema()
            if param.required:
                required.append(param.name)
        
        return {
            "type": "object",
            "properties": properties,
            "required": required
        }
    
    def validate_params(self, params: Dict[str, Any]) -> Optional[str]:
        """
        Validate input parameters.
        
        Args:
            params: Parameters to validate
            
        Returns:
            Error message if validation fails, None otherwise
        """
        for param in self._parameters:
            if param.required and param.name not in params:
                return f"Missing required parameter: {param.name}"
        return None
    
    @abstractmethod
    async def execute(
        self,
        params: Dict[str, Any],
        context: Dict[str, Any]
    ) -> SkillResult:
        """
        Execute the Skill.
        
        Args:
            params: Skill parameters
            context: Execution context (session info, etc.)
            
        Returns:
            SkillResult with execution outcome
        """
        pass

# -----------------------------------------------------------------------------
# Skill Registry
# -----------------------------------------------------------------------------

class SkillRegistry:
    """
    Registry for managing Skills.
    
    Supports:
    - Registration by name
    - Lookup by name
    - Hot-reload (re-register)
    - Category filtering
    """
    
    def __init__(self):
        self._skills: Dict[str, BaseSkill] = {}
        
    def register(self, skill: BaseSkill) -> None:
        """
        Register a Skill.
        
        Args:
            skill: Skill instance to register
        """
        if skill.name in self._skills:
            logger.warning(
                "Replacing existing skill",
                skill_name=skill.name,
                old_version=self._skills[skill.name].version,
                new_version=skill.version
            )
        
        self._skills[skill.name] = skill
        logger.info(
            "Skill registered",
            skill_name=skill.name,
            version=skill.version,
            category=skill.category.value
        )
    
    def unregister(self, name: str) -> bool:
        """
        Unregister a Skill.
        
        Args:
            name: Skill name to unregister
            
        Returns:
            True if unregistered, False if not found
        """
        if name in self._skills:
            del self._skills[name]
            logger.info("Skill unregistered", skill_name=name)
            return True
        return False
    
    def get(self, name: str) -> Optional[BaseSkill]:
        """
        Get a Skill by name.
        
        Args:
            name: Skill name
            
        Returns:
            Skill instance or None if not found
        """
        return self._skills.get(name)
    
    def list_skills(self) -> List[BaseSkill]:
        """
        List all registered Skills.
        
        Returns:
            List of all Skills
        """
        return list(self._skills.values())
    
    def list_by_category(self, category: SkillCategory) -> List[BaseSkill]:
        """
        List Skills by category.
        
        Args:
            category: Category to filter by
            
        Returns:
            List of Skills in the category
        """
        return [
            skill for skill in self._skills.values()
            if skill.category == category
        ]
    
    def has(self, name: str) -> bool:
        """Check if a Skill exists."""
        return name in self._skills
    
    def clear(self) -> None:
        """Clear all registered Skills."""
        self._skills.clear()
        logger.info("All skills cleared")

# -----------------------------------------------------------------------------
# Decorators
# -----------------------------------------------------------------------------

def skill(
    name: str,
    description: str,
    version: str = "1.0.0",
    category: SkillCategory = SkillCategory.CUSTOM
):
    """
    Decorator to create a Skill from a function.
    
    Usage:
        @skill("my_skill", "Does something useful")
        async def my_skill(params: dict, context: dict) -> Any:
            return {"result": "done"}
    """
    def decorator(func):
        class FunctionSkill(BaseSkill):
            def __init__(self):
                super().__init__(
                    name=name,
                    description=description,
                    version=version,
                    category=category
                )
                self._func = func
            
            async def execute(
                self,
                params: Dict[str, Any],
                context: Dict[str, Any]
            ) -> SkillResult:
                try:
                    result = await self._func(params, context)
                    return SkillResult.success(result)
                except Exception as e:
                    return SkillResult.failure(str(e))
        
        return FunctionSkill()
    
    return decorator

# -----------------------------------------------------------------------------
# Package Init
# -----------------------------------------------------------------------------

__all__ = [
    "SkillStatus",
    "SkillCategory",
    "SkillResult",
    "SkillParameter",
    "BaseSkill",
    "SkillRegistry",
    "skill",
]
