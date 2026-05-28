"""
UniFlow Code Executor Skill
===========================
Sandboxed Python code execution Skill.
"""

import ast
import sys
import traceback
from io import StringIO
from typing import Any, Dict, List, Optional
import structlog

from .base import BaseSkill, SkillCategory, SkillParameter, SkillResult

logger = structlog.get_logger(__name__)

# -----------------------------------------------------------------------------
# Safe Builtins
# -----------------------------------------------------------------------------

# Dangerous attribute patterns that could be used for sandbox escape
DANGEROUS_ATTRS = {
    '__class__', '__bases__', '__mro__', '__subclasses__',
    '__globals__', '__code__', '__func__', '__self__',
    '__dict__', '__builtins__', '__import__', '__loader__',
    '__spec__', '__cached__', '__file__', '__name__',
    '__qualname__', '__module__', '__annotations__',
    '__closure__', '__defaults__', '__kwdefaults__',
}

def safe_getattr(obj, name, *default):
    """
    Safe getattr that blocks access to dangerous attributes.
    
    Args:
        obj: Object to get attribute from
        name: Attribute name
        default: Optional default value
        
    Returns:
        Attribute value
        
    Raises:
        AttributeError: If attribute is blocked or doesn't exist
    """
    # Block dangerous attribute access
    if name in DANGEROUS_ATTRS:
        raise AttributeError(f"Access to '{name}' is not allowed in sandbox")
    
    # Block any dunder attributes except safe ones
    if name.startswith('__') and name.endswith('__'):
        allowed_dunders = {'__init__', '__str__', '__repr__', '__len__', 
                          '__iter__', '__next__', '__getitem__', '__contains__'}
        if name not in allowed_dunders:
            raise AttributeError(f"Access to '{name}' is not allowed in sandbox")
    
    if default:
        return getattr(obj, name, default[0])
    return getattr(obj, name)


# Allowed built-in functions for sandboxed execution
SAFE_BUILTINS = {
    # Type constructors
    "bool": bool,
    "int": int,
    "float": float,
    "str": str,
    "list": list,
    "dict": dict,
    "tuple": tuple,
    "set": set,
    "frozenset": frozenset,
    "bytes": bytes,
    "bytearray": bytearray,
    
    # Type checking
    "type": type,
    "isinstance": isinstance,
    "issubclass": issubclass,
    
    # Iteration
    "range": range,
    "enumerate": enumerate,
    "zip": zip,
    "map": map,
    "filter": filter,
    "reversed": reversed,
    "sorted": sorted,
    
    # Math
    "abs": abs,
    "min": min,
    "max": max,
    "sum": sum,
    "round": round,
    "pow": pow,
    "divmod": divmod,
    
    # String/Sequence
    "len": len,
    "chr": chr,
    "ord": ord,
    "repr": repr,
    "ascii": ascii,
    "format": format,
    
    # Logic
    "all": all,
    "any": any,
    
    # Other safe functions
    "print": print,  # Captured via stdout
    "hash": hash,
    "id": id,
    "callable": callable,
    "getattr": safe_getattr,  # SECURITY: Wrapped with safe_getattr to block dangerous attrs
    # "setattr": setattr,  # SECURITY: Removed - allows arbitrary attribute modification
    "hasattr": hasattr,
    # "delattr": delattr,  # SECURITY: Removed - allows arbitrary attribute deletion
    
    # Exceptions (for catching)
    "Exception": Exception,
    "ValueError": ValueError,
    "TypeError": TypeError,
    "KeyError": KeyError,
    "IndexError": IndexError,
    "AttributeError": AttributeError,
    "RuntimeError": RuntimeError,
    "StopIteration": StopIteration,
    "ZeroDivisionError": ZeroDivisionError,
    
    # Constants
    "True": True,
    "False": False,
    "None": None,
}

# Blocked imports
BLOCKED_IMPORTS = {
    "os",
    "sys",
    "subprocess",
    "shutil",
    "socket",
    "requests",
    "urllib",
    "http",
    "ftplib",
    "smtplib",
    "telnetlib",
    "pickle",
    "shelve",
    "marshal",
    "importlib",
    "__builtins__",
    "builtins",
    "ctypes",
    "multiprocessing",
    "threading",
    "asyncio",
    "concurrent",
    "signal",
}

# -----------------------------------------------------------------------------
# Code Validator
# -----------------------------------------------------------------------------

class CodeValidator(ast.NodeVisitor):
    """
    AST visitor to validate code safety.
    
    Checks for:
    - Dangerous imports
    - Forbidden function calls
    - Attribute access to dangerous objects
    """
    
    def __init__(self):
        self.errors: List[str] = []
        
    def visit_Import(self, node: ast.Import) -> None:
        """Check import statements."""
        for alias in node.names:
            module_name = alias.name.split(".")[0]
            if module_name in BLOCKED_IMPORTS:
                self.errors.append(f"Import of '{alias.name}' is not allowed")
        self.generic_visit(node)
    
    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        """Check from-import statements."""
        if node.module:
            module_name = node.module.split(".")[0]
            if module_name in BLOCKED_IMPORTS:
                self.errors.append(f"Import from '{node.module}' is not allowed")
        self.generic_visit(node)
    
    def visit_Call(self, node: ast.Call) -> None:
        """Check function calls."""
        # Check for dangerous calls like eval, exec, compile
        if isinstance(node.func, ast.Name):
            if node.func.id in ("eval", "exec", "compile", "open", "__import__"):
                self.errors.append(f"Call to '{node.func.id}' is not allowed")
        self.generic_visit(node)
    
    def visit_Attribute(self, node: ast.Attribute) -> None:
        """Check attribute access."""
        # Block dunder attributes except __init__, __str__, __repr__
        if node.attr.startswith("__") and node.attr.endswith("__"):
            allowed_dunders = {"__init__", "__str__", "__repr__", "__len__", "__iter__", "__next__"}
            if node.attr not in allowed_dunders:
                self.errors.append(f"Access to '{node.attr}' is not allowed")
        self.generic_visit(node)
    
    def validate(self, code: str) -> List[str]:
        """
        Validate code and return list of errors.
        
        Args:
            code: Python code to validate
            
        Returns:
            List of error messages (empty if valid)
        """
        self.errors = []
        try:
            tree = ast.parse(code)
            self.visit(tree)
        except SyntaxError as e:
            self.errors.append(f"Syntax error: {e}")
        return self.errors

# -----------------------------------------------------------------------------
# Code Executor Skill
# -----------------------------------------------------------------------------

class CodeExecutorSkill(BaseSkill):
    """
    Skill for executing Python code in a sandboxed environment.
    
    Features:
    - AST-based code validation
    - Limited builtins
    - Captured stdout/stderr
    - Timeout support (via external wrapper)
    - Safe math module access
    """
    
    def __init__(self):
        super().__init__(
            name="code_executor",
            description="Execute Python code in a sandboxed environment",
            version="1.0.0",
            category=SkillCategory.CODE,
            parameters=[
                SkillParameter(
                    name="code",
                    type="string",
                    description="Python code to execute",
                    required=True
                ),
                SkillParameter(
                    name="variables",
                    type="object",
                    description="Variables to inject into execution context",
                    required=False,
                    default={}
                ),
                SkillParameter(
                    name="return_var",
                    type="string",
                    description="Variable name to return as result",
                    required=False,
                    default="result"
                )
            ]
        )
        self._validator = CodeValidator()
        
    def _create_safe_globals(self, variables: Dict[str, Any]) -> Dict[str, Any]:
        """
        Create a safe globals dict for execution.
        
        Args:
            variables: User-provided variables
            
        Returns:
            Safe globals dictionary
        """
        safe_globals = {
            "__builtins__": SAFE_BUILTINS.copy(),
            "__name__": "__sandbox__",
            "__doc__": None,
        }
        
        # Add safe math module
        import math as math_module
        safe_math = {
            name: getattr(math_module, name)
            for name in [
                "pi", "e", "tau", "inf", "nan",
                "sqrt", "pow", "exp", "log", "log10", "log2",
                "sin", "cos", "tan", "asin", "acos", "atan", "atan2",
                "sinh", "cosh", "tanh", "asinh", "acosh", "atanh",
                "ceil", "floor", "trunc", "fabs",
                "factorial", "gcd", "isnan", "isinf", "isfinite",
                "degrees", "radians",
            ]
        }
        safe_globals["math"] = type("SafeMath", (), safe_math)()
        
        # Add user variables (sanitized)
        for key, value in variables.items():
            # Only allow safe types
            if isinstance(value, (str, int, float, bool, list, dict, tuple, type(None))):
                safe_globals[key] = value
            else:
                logger.warning(f"Skipping unsafe variable type: {key}={type(value)}")
        
        return safe_globals
    
    async def execute(
        self,
        params: Dict[str, Any],
        context: Dict[str, Any]
    ) -> SkillResult:
        """
        Execute Python code in sandbox.
        
        Args:
            params: Contains 'code', optional 'variables' and 'return_var'
            context: Execution context (unused)
            
        Returns:
            SkillResult with execution output
        """
        code = params.get("code", "")
        variables = params.get("variables", {})
        return_var = params.get("return_var", "result")
        
        # Validate code
        errors = self._validator.validate(code)
        if errors:
            return SkillResult.failure(
                f"Code validation failed: {'; '.join(errors)}",
                metadata={"validation_errors": errors}
            )
        
        # Prepare execution environment
        safe_globals = self._create_safe_globals(variables)
        local_vars: Dict[str, Any] = {}
        
        # Capture stdout
        old_stdout = sys.stdout
        captured_stdout = StringIO()
        
        try:
            sys.stdout = captured_stdout
            
            # Execute code
            exec(code, safe_globals, local_vars)
            
            # Get result
            result_value = local_vars.get(return_var)
            stdout_output = captured_stdout.getvalue()
            
            return SkillResult.success(
                data={
                    "value": result_value,
                    "stdout": stdout_output,
                    "variables": {
                        k: v for k, v in local_vars.items()
                        if isinstance(v, (str, int, float, bool, list, dict, tuple, type(None)))
                    }
                },
                metadata={
                    "return_var": return_var,
                    "has_output": bool(stdout_output)
                }
            )
            
        except Exception as e:
            error_msg = f"{type(e).__name__}: {str(e)}"
            tb = traceback.format_exc()
            
            logger.error(
                "Code execution error",
                error=error_msg,
                traceback=tb
            )
            
            return SkillResult.failure(
                error_msg,
                metadata={
                    "traceback": tb,
                    "stdout": captured_stdout.getvalue()
                }
            )
            
        finally:
            sys.stdout = old_stdout

# -----------------------------------------------------------------------------
# Package Init
# -----------------------------------------------------------------------------

__all__ = [
    "CodeExecutorSkill",
    "CodeValidator",
    "SAFE_BUILTINS",
    "BLOCKED_IMPORTS",
]
