# UniFlow Skill Templates

> TASK-2012: 常用 Skill 模板

## 模板列表

### Python 模板

| 模板 | 功能 | 依赖 |
|------|------|------|
| `python-http-client.py` | HTTP 请求 (GET/POST/PUT/DELETE) | `requests` |
| `python-data-transformer.py` | 数据转换 (map/filter/sort/group) | - |

### Node.js 模板

| 模板 | 功能 | 依赖 |
|------|------|------|
| `nodejs-file-utils.js` | 文件操作 (读写/复制/搜索) | - |

---

## Python HTTP Client

HTTP 请求 Skill，支持自动重试、超时处理、响应解析�?

### 安装

```bash
pip install requests
```

### 使用

**命令�?**
```bash
python python-http-client.py \
  --url "https://api.example.com/users" \
  --method GET \
  --headers '{"Authorization": "Bearer xxx"}'
```

**Skill 输入:**
```json
{
  "url": "https://api.example.com/users",
  "method": "POST",
  "body": {"name": "John", "email": "john@example.com"},
  "headers": {"Authorization": "Bearer xxx"},
  "timeout": 30,
  "retry_count": 3
}
```

**输出:**
```json
{
  "success": true,
  "status_code": 201,
  "data": {"id": 1, "name": "John"},
  "headers": {...}
}
```

---

## Python Data Transformer

数据转换 Skill，支持数�?对象的各种操作�?

### 操作列表

| 操作 | 描述 | 配置 |
|------|------|------|
| `map` | 映射转换 | `expression`: 表达�?(x, idx) |
| `filter` | 过滤 | `condition`: 条件表达�?|
| `reduce` | 聚合 | `operation`: sum/count/avg/min/max/join |
| `sort` | 排序 | `key`: 排序字段, `reverse`: 是否降序 |
| `group` | 分组 | `key`: 分组字段 |
| `flatten` | 扁平�?| `depth`: 深度 |
| `unique` | 去重 | `key`: 去重字段 |
| `pick` | 选取字段 | `fields`: 字段列表 |
| `omit` | 排除字段 | `fields`: 字段列表 |
| `rename` | 重命�?| `mapping`: {旧名: 新名} |
| `convert` | 格式转换 | `from`/`to`: json/csv/string |
| `validate` | 数据验证 | `schema`: JSON Schema |

### 示例

```bash
# 数组映射
python python-data-transformer.py \
  --input '[1, 2, 3, 4, 5]' \
  --transform map \
  --expression "x * 2"

# 过滤
python python-data-transformer.py \
  --input '[1, 2, 3, 4, 5]' \
  --transform filter \
  --expression "x > 2"

# 分组
python python-data-transformer.py \
  --input '[{"name":"A","type":"x"},{"name":"B","type":"x"},{"name":"C","type":"y"}]' \
  --transform group \
  --config '{"key": "type"}'
```

---

## Node.js File Utils

文件操作 Skill，支持文件读写、目录管理、文件搜索�?

### 操作列表

| 操作 | 描述 | 必需参数 |
|------|------|----------|
| `read` | 读取文件 | `path` |
| `write` | 写入文件 | `path`, `content` |
| `delete` | 删除文件 | `path` |
| `copy` | 复制文件 | `path`, `dest` |
| `move` | 移动/重命�?| `path`, `dest` |
| `info` | 获取文件信息 | `path` |
| `list` | 列出目录 | `path` (可�? |
| `mkdir` | 创建目录 | `path` |
| `rmdir` | 删除目录 | `path` |
| `exists` | 检查是否存�?| `path` |

### 示例

```bash
# 读取文件
node nodejs-file-utils.js --action read --path "./config.json" --options '{"format":"json"}'

# 写入文件
node nodejs-file-utils.js --action write --path "./output.txt" --content "Hello World"

# 列出目录
node nodejs-file-utils.js --action list --path "./src" --options '{"recursive":true,"pattern":"*.js"}'

# 检查文件是否存�?
node nodejs-file-utils.js --action exists --path "./README.md"
```

---

## 创建自定�?Skill

1. 复制合适的模板
2. 修改 `execute_skill()` 函数
3. 添加业务逻辑
4. 测试 CLI �?Skill 接口

### 模板结构

```python
def execute_skill(input_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Skill 入口函数
    
    Args:
        input_data: 输入参数字典
        
    Returns:
        {
            "success": True/False,
            "data": 结果数据,
            "error": 错误�?(失败�?,
            "message": 错误信息 (失败�?
        }
    """
    # 1. 验证输入
    # 2. 执行业务逻辑
    # 3. 返回结果
    pass
```

---

## 更多模板 (计划)

- [ ] `python-database.py` - 数据库操�?(SQLite/MySQL/PostgreSQL)
- [ ] `python-email.py` - 邮件发�?(SMTP)
- [ ] `python-ocr.py` - 图片文字识别
- [ ] `nodejs-websocket.js` - WebSocket 客户�?
- [ ] `nodejs-queue.js` - 消息队列 (Redis/RabbitMQ)
