# odd-core

ODD (Output-Driven Development) 命令行工具�?
## 安装

```bash
pip install odd-core
```

或本地开发安装：

```bash
git clone https://github.com/your-org/odd-hub
cd odd-hub/odd-core
pip install -e .
```

## 快速开�?
```bash
# 1. 初始化工作区
odd init
# 生成 .odd/contracts/  .odd/seals/  .odd/config.yaml

# 2. 编写契约�?odd/contracts/my_func.yaml�?cat > .odd/contracts/my_func.yaml << 'EOF'
id: my-func
name: 我的函数契约
verification_hints:
  must_contain_any:
    - patterns: ["def ", "class "]
      reason: 必须包含函数或类定义
      severity: critical
  must_not_contain:
    - patterns: ["eval(", "exec("]
      reason: 禁止使用 eval/exec
      severity: critical
  should_contain:
    - patterns: ['"""', "'''"]
      reason: 建议添加 docstring
      severity: low
EOF

# 3. 验证代码
odd verify my_code.py --contract .odd/contracts/my_func.yaml

# 4. 封存（生成哈希链记录�?odd seal my_code.py --contract .odd/contracts/my_func.yaml
```

## 命令

| 命令 | 说明 |
|------|------|
| `odd init` | 初始化当前目录的 ODD 工作�?|
| `odd verify <file>` | 验证代码是否符合契约 |
| `odd verify --all` | 批量验证 `.odd/contracts/` 下所有契�?|
| `odd verify --ai` | 启用 AI 语义验证层（需设置 `ODD_AI_API_KEY`�?|
| `odd seal <file>` | 封存代码 + 契约 + 验证结果（SHA-256 哈希链） |
| `odd freeze <name>` | 锁定契约，禁止未经审批的修改 |
| `odd unfreeze <name>` | 解锁契约 |
| `odd template list` | 列出所有可用模板（内置 15 个） |
| `odd template pull <name>` | 从模板库拉取契约�?`.odd/contracts/` |
| `odd template push <file>` | 将契约文件保存为本地模板 |

**内置模板列表**

| 模板 ID | 说明 |
|---------|------|
| `auth_login` | 认证登录模块 |
| `crud_api` | 增删改查 API |
| `rest_api_endpoint` | REST API 端点 |
| `db_model` | 数据库模�?ORM |
| `unit_test` | 单元测试 |
| `cache_layer` | 缓存读写�?|
| `background_job` | 异步后台任务 |
| `event_handler` | 事件监听/处理 |
| `config_loader` | 配置加载�?|
| `filter` | 数据过滤/清洗 |
| `parser` | 数据/文本解析 |
| `logger` | 日志模块 |
| `rate_limiter` | 接口限流 |
| `webhook` | Webhook 回调处理 |
| `cli_command` | CLI 命令 |

## 契约格式

```yaml
id: string           # 唯一标识
name: string         # 契约名称
verification_hints:
  must_contain_any:  # 至少匹配一�?pattern（违�?= FAIL�?    - patterns: [...]
      reason: string
      severity: critical | medium | low
  must_not_contain:  # 不能包含任何 pattern（违�?= FAIL�?    - patterns: [...]
      reason: string
      severity: critical | medium | low
  should_contain:    # 建议包含（违�?= WARNING，不影响整体结果�?    - patterns: [...]
      reason: string
      severity: low
```

## 封存记录

`odd seal` �?`.odd/seals/` 下生�?JSON 文件，包含：

- `seal_id` �?UUID
- `timestamp` �?ISO 8601
- `hashes.contract` �?契约 SHA-256
- `hashes.code` �?代码 SHA-256
- `hashes.verification` �?验证结果 SHA-256
- `integrity` �?三者合并哈�?

## 开�?
```bash
pip install -e .
python -m pytest tests/ -v
```

## 相关链接

 **学术论文（Zenodo�?*: [doi.org/10.5281/zenodo.18207648](https://doi.org/10.5281/zenodo.18207648)
 **实验数据 & Demo**: [odd-demo](../odd-demo/)
 **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)
 **作�?*: Yi Fu �?fuyi.it@live.cn
