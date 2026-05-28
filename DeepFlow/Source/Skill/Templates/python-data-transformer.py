"""
UniFlow Skill Template: Python Data Transformer
================================================
TASK-2012: 更多 Skill 模板

功能:
- JSON 数据转换
- CSV/Excel 处理
- 数据过滤/映射/聚合
- 数据验证
- 格式转换

使用:
  python python-data-transformer.py --input '{"data": [1,2,3]}' --transform map --expression "x * 2"
"""

import argparse
import csv
import io
import json
import re
import sys
from typing import Any, Callable, Dict, List, Optional, Union
from datetime import datetime
from functools import reduce

# ============================================================================
# 数据转换�?
# ============================================================================

class DataTransformer:
    """通用数据转换�?""
    
    def __init__(self):
        self.transforms = {
            "map": self.transform_map,
            "filter": self.transform_filter,
            "reduce": self.transform_reduce,
            "sort": self.transform_sort,
            "group": self.transform_group,
            "flatten": self.transform_flatten,
            "unique": self.transform_unique,
            "pick": self.transform_pick,
            "omit": self.transform_omit,
            "rename": self.transform_rename,
            "convert": self.transform_convert,
            "validate": self.transform_validate
        }
    
    def execute(self, data: Any, operation: str, config: Dict = None) -> Dict[str, Any]:
        """执行转换"""
        config = config or {}
        
        if operation not in self.transforms:
            return {
                "success": False,
                "error": "unknown_operation",
                "message": f"Unknown operation: {operation}. Available: {list(self.transforms.keys())}"
            }
        
        try:
            result = self.transforms[operation](data, config)
            return {
                "success": True,
                "data": result,
                "count": len(result) if isinstance(result, (list, dict)) else 1
            }
        except Exception as e:
            return {
                "success": False,
                "error": "transform_failed",
                "message": str(e)
            }
    
    def transform_map(self, data: List, config: Dict) -> List:
        """映射转换 - 对每个元素应用表达式"""
        expression = config.get("expression", "x")
        
        # SECURITY: Validate expression before eval
        if not self._is_safe_expression(expression):
            raise ValueError(f"Unsafe expression rejected: {expression}")
        
        def eval_expr(x, idx=0):
            # 安全的表达式求�?- 严格限制可用函数
            safe_builtins = {
                "len": len, "str": str, "int": int, "float": float,
                "abs": abs, "min": min, "max": max, "sum": sum,
                "round": round, "bool": bool, "list": list,
                "True": True, "False": False, "None": None
            }
            local_vars = {"x": x, "idx": idx}
            return eval(expression, {"__builtins__": safe_builtins}, local_vars)
        
        return [eval_expr(item, i) for i, item in enumerate(data)]
    
    def transform_filter(self, data: List, config: Dict) -> List:
        """过滤 - 根据条件筛�?""
        condition = config.get("condition", "True")
        
        # SECURITY: Validate condition before eval
        if not self._is_safe_expression(condition):
            raise ValueError(f"Unsafe condition rejected: {condition}")
        
        def eval_condition(x, idx=0):
            safe_builtins = {
                "len": len, "str": str, "int": int, "float": float,
                "abs": abs, "min": min, "max": max, "sum": sum,
                "round": round, "bool": bool, "list": list,
                "True": True, "False": False, "None": None
            }
            local_vars = {"x": x, "idx": idx}
            return eval(condition, {"__builtins__": safe_builtins}, local_vars)
        
        return [item for i, item in enumerate(data) if eval_condition(item, i)]
    
    def _is_safe_expression(self, expr: str) -> bool:
        """验证表达式是否安�?""
        # 禁止危险关键�?
        dangerous_patterns = [
            r'\bimport\b', r'\bexec\b', r'\beval\b', r'\bcompile\b',
            r'\bopen\b', r'\bfile\b', r'\binput\b', r'\b__\w+__\b',
            r'\bgetattr\b', r'\bsetattr\b', r'\bdelattr\b', r'\bglobals\b',
            r'\blocals\b', r'\bvars\b', r'\bdir\b', r'\btype\b',
            r'\bbreakpoint\b', r'\bexit\b', r'\bquit\b',
        ]
        for pattern in dangerous_patterns:
            if re.search(pattern, expr, re.IGNORECASE):
                return False
        return True
    
    def transform_reduce(self, data: List, config: Dict) -> Any:
        """归约 - 聚合为单个�?""
        operation = config.get("operation", "sum")
        initial = config.get("initial", None)
        
        if operation == "sum":
            return sum(data) if not initial else sum(data, initial)
        elif operation == "count":
            return len(data)
        elif operation == "avg":
            return sum(data) / len(data) if data else 0
        elif operation == "min":
            return min(data) if data else None
        elif operation == "max":
            return max(data) if data else None
        elif operation == "join":
            separator = config.get("separator", ",")
            return separator.join(str(x) for x in data)
        elif operation == "first":
            return data[0] if data else None
        elif operation == "last":
            return data[-1] if data else None
        else:
            raise ValueError(f"Unknown reduce operation: {operation}")
    
    def transform_sort(self, data: List, config: Dict) -> List:
        """排序"""
        key_path = config.get("key")
        reverse = config.get("reverse", False)
        
        if key_path:
            def get_key(x):
                keys = key_path.split(".")
                value = x
                for k in keys:
                    if isinstance(value, dict):
                        value = value.get(k)
                    else:
                        return None
                return value
            return sorted(data, key=get_key, reverse=reverse)
        return sorted(data, reverse=reverse)
    
    def transform_group(self, data: List, config: Dict) -> Dict[str, List]:
        """分组"""
        key_path = config.get("key")
        if not key_path:
            raise ValueError("Group requires 'key' config")
        
        result = {}
        for item in data:
            keys = key_path.split(".")
            value = item
            for k in keys:
                if isinstance(value, dict):
                    value = value.get(k)
                else:
                    value = None
                    break
            
            group_key = str(value) if value is not None else "_null"
            if group_key not in result:
                result[group_key] = []
            result[group_key].append(item)
        
        return result
    
    def transform_flatten(self, data: List, config: Dict) -> List:
        """扁平化嵌套数�?""
        depth = config.get("depth", 1)
        
        def flatten_once(lst):
            result = []
            for item in lst:
                if isinstance(item, list):
                    result.extend(item)
                else:
                    result.append(item)
            return result
        
        result = data
        for _ in range(depth):
            result = flatten_once(result)
        return result
    
    def transform_unique(self, data: List, config: Dict) -> List:
        """去重"""
        key_path = config.get("key")
        
        if key_path:
            seen = set()
            result = []
            for item in data:
                keys = key_path.split(".")
                value = item
                for k in keys:
                    if isinstance(value, dict):
                        value = value.get(k)
                    else:
                        value = None
                        break
                
                if value not in seen:
                    seen.add(value)
                    result.append(item)
            return result
        
        # 简单去�?(保持顺序)
        seen = set()
        result = []
        for item in data:
            key = json.dumps(item, sort_keys=True) if isinstance(item, (dict, list)) else item
            if key not in seen:
                seen.add(key)
                result.append(item)
        return result
    
    def transform_pick(self, data: Union[Dict, List], config: Dict) -> Union[Dict, List]:
        """选取指定字段"""
        fields = config.get("fields", [])
        
        def pick_fields(obj):
            if isinstance(obj, dict):
                return {k: obj[k] for k in fields if k in obj}
            return obj
        
        if isinstance(data, list):
            return [pick_fields(item) for item in data]
        return pick_fields(data)
    
    def transform_omit(self, data: Union[Dict, List], config: Dict) -> Union[Dict, List]:
        """排除指定字段"""
        fields = config.get("fields", [])
        
        def omit_fields(obj):
            if isinstance(obj, dict):
                return {k: v for k, v in obj.items() if k not in fields}
            return obj
        
        if isinstance(data, list):
            return [omit_fields(item) for item in data]
        return omit_fields(data)
    
    def transform_rename(self, data: Union[Dict, List], config: Dict) -> Union[Dict, List]:
        """重命名字�?""
        mapping = config.get("mapping", {})
        
        def rename_fields(obj):
            if isinstance(obj, dict):
                return {mapping.get(k, k): v for k, v in obj.items()}
            return obj
        
        if isinstance(data, list):
            return [rename_fields(item) for item in data]
        return rename_fields(data)
    
    def transform_convert(self, data: Any, config: Dict) -> Any:
        """格式转换"""
        from_format = config.get("from", "json")
        to_format = config.get("to", "json")
        
        # JSON -> CSV
        if from_format == "json" and to_format == "csv":
            if isinstance(data, list) and data and isinstance(data[0], dict):
                output = io.StringIO()
                writer = csv.DictWriter(output, fieldnames=data[0].keys())
                writer.writeheader()
                writer.writerows(data)
                return output.getvalue()
        
        # CSV -> JSON
        if from_format == "csv" and to_format == "json":
            reader = csv.DictReader(io.StringIO(data))
            return list(reader)
        
        # JSON 字符�?-> 对象
        if from_format == "string" and to_format == "json":
            return json.loads(data)
        
        # 对象 -> JSON 字符�?
        if from_format == "json" and to_format == "string":
            return json.dumps(data, ensure_ascii=False, indent=2)
        
        return data
    
    def transform_validate(self, data: Any, config: Dict) -> Dict:
        """数据验证"""
        schema = config.get("schema", {})
        errors = []
        
        def validate_value(value, rules, path=""):
            if "type" in rules:
                expected = rules["type"]
                actual = type(value).__name__
                type_map = {"string": "str", "number": ("int", "float"), "boolean": "bool", "array": "list", "object": "dict"}
                expected_types = type_map.get(expected, expected)
                if isinstance(expected_types, tuple):
                    if actual not in expected_types:
                        errors.append(f"{path}: expected {expected}, got {actual}")
                elif actual != expected_types:
                    errors.append(f"{path}: expected {expected}, got {actual}")
            
            if "required" in rules and rules["required"] and value is None:
                errors.append(f"{path}: required field is missing")
            
            if "minLength" in rules and isinstance(value, str) and len(value) < rules["minLength"]:
                errors.append(f"{path}: length < {rules['minLength']}")
            
            if "maxLength" in rules and isinstance(value, str) and len(value) > rules["maxLength"]:
                errors.append(f"{path}: length > {rules['maxLength']}")
            
            if "min" in rules and isinstance(value, (int, float)) and value < rules["min"]:
                errors.append(f"{path}: value < {rules['min']}")
            
            if "max" in rules and isinstance(value, (int, float)) and value > rules["max"]:
                errors.append(f"{path}: value > {rules['max']}")
            
            if "pattern" in rules and isinstance(value, str):
                if not re.match(rules["pattern"], value):
                    errors.append(f"{path}: does not match pattern")
            
            if "enum" in rules and value not in rules["enum"]:
                errors.append(f"{path}: must be one of {rules['enum']}")
        
        # 验证对象
        if isinstance(data, dict) and "properties" in schema:
            for key, rules in schema["properties"].items():
                value = data.get(key)
                validate_value(value, rules, key)
        elif isinstance(data, list) and "items" in schema:
            for i, item in enumerate(data):
                validate_value(item, schema["items"], f"[{i}]")
        else:
            validate_value(data, schema, "root")
        
        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "data": data
        }


# ============================================================================
# UniFlow Skill 接口
# ============================================================================

def execute_skill(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Skill 入口函数
    
    输入:
        {
            "data": [...] �?{...},
            "transform": "map|filter|reduce|sort|group|...",
            "config": { 转换配置 }
        }
    
    输出:
        {
            "success": true,
            "data": 转换结果,
            "count": 结果数量
        }
    """
    
    data = input_data.get("data")
    if data is None:
        return {"success": False, "error": "missing_data", "message": "Data is required"}
    
    transform = input_data.get("transform")
    if not transform:
        return {"success": False, "error": "missing_transform", "message": "Transform operation is required"}
    
    config = input_data.get("config", {})
    
    transformer = DataTransformer()
    return transformer.execute(data, transform, config)


# ============================================================================
# CLI 入口
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="UniFlow Data Transformer Skill")
    parser.add_argument("--input", required=True, help="Input data (JSON)")
    parser.add_argument("--transform", required=True, 
                        choices=["map", "filter", "reduce", "sort", "group", "flatten", 
                                 "unique", "pick", "omit", "rename", "convert", "validate"])
    parser.add_argument("--config", type=json.loads, default={}, help="Transform config (JSON)")
    parser.add_argument("--expression", help="Expression for map/filter (shortcut)")
    parser.add_argument("--output", choices=["json", "pretty"], default="pretty")
    
    args = parser.parse_args()
    
    try:
        data = json.loads(args.input)
    except json.JSONDecodeError:
        data = args.input  # 可能�?CSV 字符�?
    
    config = args.config
    if args.expression:
        if args.transform == "map":
            config["expression"] = args.expression
        elif args.transform == "filter":
            config["condition"] = args.expression
    
    input_data = {
        "data": data,
        "transform": args.transform,
        "config": config
    }
    
    result = execute_skill(input_data)
    
    if args.output == "json":
        print(json.dumps(result))
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
