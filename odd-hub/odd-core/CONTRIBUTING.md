# Contributing to odd-core

感谢你的贡献！以下是参与 odd-core 开发的指南�?
---

## 环境准备

```bash
git clone https://github.com/your-org/odd-hub
cd odd-hub/odd-core
pip install -e ".[dev]"
```

## 项目结构

```
odd-core/
├── src/odd/
�?  ├── cli.py          # CLI 入口（Click�?�?  ├── verifier.py     # 规则验证引擎
�?  ├── sealer.py       # 封存 / 哈希�?�?  ├── ai_verifier.py  # AI 语义验证�?�?  ├── plugins.py      # 插件机制（BasePlugin / PluginRegistry�?�?  └── templates/      # 内置契约模板（YAML�?└── tests/
```

## 贡献模板

最欢迎的贡献类型。每个模板是一�?YAML 文件，放�?`src/odd/templates/`�?
### 模板格式

```yaml
id: my_template          # 唯一 ID，用�?odd template pull <id>
name: 我的模板契约
description: 一句话说明用�?verification_hints:
  must_contain_any:
    - patterns: ["keyword1", "keyword2"]
      reason: 必须包含 XX 逻辑
      severity: critical        # critical | medium | low
  must_not_contain:
    - patterns: ["dangerous_call("]
      reason: 禁止使用 XX
      severity: critical
  should_contain:
    - patterns: ["docstring_hint"]
      reason: 建议添加文档注释
      severity: low
```

### 模板命名规范

- ID 使用 `snake_case`，与文件名一致（`my_template.yaml`�?- `must_contain_any` �?违反�?FAIL，用于核心结构检�?- `must_not_contain` �?违反�?FAIL，用于安�?禁用模式
- `should_contain` �?违反�?WARNING，用于最佳实践建�?
### 提交模板 PR 前请确认

- [ ] `odd template pull <your_id>` 能正常拉�?- [ ] patterns 覆盖主流语言（Python / JS / Java / Go 至少两种�?- [ ] 每条规则都有清晰�?`reason`

## 贡献插件

�?`src/odd/plugins.py` 中继�?`BasePlugin`�?
```python
from odd.plugins import BasePlugin, PluginRegistry

class MyPlugin(BasePlugin):
    name = "my_plugin"

    def run(self, code: str, contract: dict) -> list[dict]:
        # 返回 [{"rule": "...", "passed": bool, "reason": "..."}]
        ...

PluginRegistry.register(MyPlugin())
```

插件通过 `odd verify` 自动加载（放�?`.odd/plugins/` 目录下即可）�?
## 提交规范

```
feat: 新功�?fix:  Bug 修复
docs: 文档更新
tmpl: 新增/修改模板
```

## 运行测试

```bash
python -m pytest tests/ -v
```
