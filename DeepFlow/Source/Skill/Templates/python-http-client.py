"""
UniFlow Skill Template: Python HTTP Client
==========================================
TASK-2012: 更多 Skill 模板

功能:
- HTTP GET/POST/PUT/DELETE 请求
- 自动重试机制
- 超时处理
- 响应解析 (JSON/XML/Text)
- 请求/响应日志

使用:
  python python-http-client.py --url "https://api.example.com/data" --method GET
"""

import argparse
import json
import logging
import time
import sys
from typing import Any, Dict, Optional
from urllib.parse import urljoin, urlparse

try:
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry
except ImportError:
    print("Error: requests library not installed. Run: pip install requests")
    sys.exit(1)

# ============================================================================
# 配置
# ============================================================================

DEFAULT_TIMEOUT = 30
DEFAULT_RETRY_COUNT = 3
DEFAULT_RETRY_BACKOFF = 0.5
LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"

# ============================================================================
# 日志设置
# ============================================================================

logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
logger = logging.getLogger(__name__)


# ============================================================================
# HTTP Client
# ============================================================================

class HTTPClient:
    """可靠�?HTTP 客户�?""
    
    def __init__(
        self,
        base_url: str = "",
        timeout: int = DEFAULT_TIMEOUT,
        retry_count: int = DEFAULT_RETRY_COUNT,
        retry_backoff: float = DEFAULT_RETRY_BACKOFF,
        headers: Optional[Dict[str, str]] = None
    ):
        self.base_url = base_url
        self.timeout = timeout
        self.session = self._create_session(retry_count, retry_backoff)
        
        # 默认请求�?
        self.default_headers = {
            "User-Agent": "UniFlow-Skill/1.0",
            "Accept": "application/json",
            "Content-Type": "application/json"
        }
        if headers:
            self.default_headers.update(headers)
    
    def _create_session(self, retry_count: int, retry_backoff: float) -> requests.Session:
        """创建带重试的会话"""
        session = requests.Session()
        
        retry_strategy = Retry(
            total=retry_count,
            backoff_factor=retry_backoff,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET", "OPTIONS", "POST", "PUT", "DELETE"]
        )
        
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        
        return session
    
    def _build_url(self, endpoint: str) -> str:
        """构建完整 URL"""
        if self.base_url:
            return urljoin(self.base_url, endpoint)
        return endpoint
    
    def request(
        self,
        method: str,
        url: str,
        params: Optional[Dict[str, Any]] = None,
        data: Optional[Dict[str, Any]] = None,
        headers: Optional[Dict[str, str]] = None,
        json_data: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """发�?HTTP 请求"""
        
        full_url = self._build_url(url)
        request_headers = {**self.default_headers, **(headers or {})}
        
        logger.info(f">>> {method} {full_url}")
        if params:
            logger.debug(f"Params: {params}")
        if json_data:
            logger.debug(f"Body: {json.dumps(json_data)[:200]}...")
        
        start_time = time.time()
        
        try:
            response = self.session.request(
                method=method.upper(),
                url=full_url,
                params=params,
                data=data,
                json=json_data,
                headers=request_headers,
                timeout=self.timeout
            )
            
            elapsed = time.time() - start_time
            logger.info(f"<<< {response.status_code} ({elapsed:.2f}s)")
            
            return self._parse_response(response)
            
        except requests.exceptions.Timeout:
            logger.error(f"Request timeout after {self.timeout}s")
            return {
                "success": False,
                "error": "timeout",
                "message": f"Request timed out after {self.timeout} seconds"
            }
        except requests.exceptions.ConnectionError as e:
            logger.error(f"Connection error: {e}")
            return {
                "success": False,
                "error": "connection_error",
                "message": str(e)
            }
        except Exception as e:
            logger.error(f"Request failed: {e}")
            return {
                "success": False,
                "error": "request_failed",
                "message": str(e)
            }
    
    def _parse_response(self, response: requests.Response) -> Dict[str, Any]:
        """解析响应"""
        result = {
            "success": response.ok,
            "status_code": response.status_code,
            "headers": dict(response.headers)
        }
        
        content_type = response.headers.get("Content-Type", "")
        
        if "application/json" in content_type:
            try:
                result["data"] = response.json()
            except json.JSONDecodeError:
                result["data"] = response.text
        elif "application/xml" in content_type or "text/xml" in content_type:
            result["data"] = response.text
            result["format"] = "xml"
        else:
            result["data"] = response.text
            result["format"] = "text"
        
        if not response.ok:
            result["error"] = f"HTTP {response.status_code}"
            result["message"] = response.reason
        
        return result
    
    # 便捷方法
    def get(self, url: str, params: Optional[Dict] = None, **kwargs) -> Dict:
        return self.request("GET", url, params=params, **kwargs)
    
    def post(self, url: str, json_data: Optional[Dict] = None, **kwargs) -> Dict:
        return self.request("POST", url, json_data=json_data, **kwargs)
    
    def put(self, url: str, json_data: Optional[Dict] = None, **kwargs) -> Dict:
        return self.request("PUT", url, json_data=json_data, **kwargs)
    
    def delete(self, url: str, **kwargs) -> Dict:
        return self.request("DELETE", url, **kwargs)
    
    def patch(self, url: str, json_data: Optional[Dict] = None, **kwargs) -> Dict:
        return self.request("PATCH", url, json_data=json_data, **kwargs)


# ============================================================================
# UniFlow Skill 接口
# ============================================================================

def execute_skill(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Skill 入口函数
    
    输入:
        {
            "url": "https://api.example.com/endpoint",
            "method": "GET|POST|PUT|DELETE|PATCH",
            "params": {"key": "value"},
            "body": {"json": "data"},
            "headers": {"Authorization": "Bearer xxx"},
            "timeout": 30,
            "retry_count": 3
        }
    
    输出:
        {
            "success": true,
            "status_code": 200,
            "data": {...},
            "headers": {...}
        }
    """
    
    url = input_data.get("url")
    if not url:
        return {"success": False, "error": "missing_url", "message": "URL is required"}
    
    method = input_data.get("method", "GET").upper()
    params = input_data.get("params")
    body = input_data.get("body")
    headers = input_data.get("headers")
    timeout = input_data.get("timeout", DEFAULT_TIMEOUT)
    retry_count = input_data.get("retry_count", DEFAULT_RETRY_COUNT)
    
    client = HTTPClient(
        timeout=timeout,
        retry_count=retry_count,
        headers=headers
    )
    
    return client.request(
        method=method,
        url=url,
        params=params,
        json_data=body
    )


# ============================================================================
# CLI 入口
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="UniFlow HTTP Client Skill")
    parser.add_argument("--url", required=True, help="Request URL")
    parser.add_argument("--method", default="GET", choices=["GET", "POST", "PUT", "DELETE", "PATCH"])
    parser.add_argument("--params", type=json.loads, help="Query parameters (JSON)")
    parser.add_argument("--body", type=json.loads, help="Request body (JSON)")
    parser.add_argument("--headers", type=json.loads, help="Request headers (JSON)")
    parser.add_argument("--timeout", type=int, default=30, help="Timeout in seconds")
    parser.add_argument("--retry", type=int, default=3, help="Retry count")
    parser.add_argument("--output", choices=["json", "pretty"], default="pretty")
    
    args = parser.parse_args()
    
    input_data = {
        "url": args.url,
        "method": args.method,
        "params": args.params,
        "body": args.body,
        "headers": args.headers,
        "timeout": args.timeout,
        "retry_count": args.retry
    }
    
    result = execute_skill(input_data)
    
    if args.output == "json":
        print(json.dumps(result))
    else:
        print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
