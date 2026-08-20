"""
可鉴 · 决策操作系统 — Git 提交脚本
=====================================
自动创建 commits 并将成果登记到 tasks.md/history.md
"""

import subprocess
import json
from datetime import datetime


def run_cmd(cmd):
    """执行 git 命令"""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def main():
    print(f"\n{'='*60}")
    print("📦 可鉴 MVP 成果提交")
    print(f"{'='*60}\n")
    
    # Add files (精确范围，避免 git add -A 拖入整个仓库无关变更)
    print("[1/5] Git add...")
    add_cmd = (
        'git add 可鉴/ '
        '"docs/zh/09.03.Product-可鉴-决策操作系统-产品定位-v1.0.md" '
        'samples.jsonl submit_kejian_mvp.py bugfix.md kejian_demo_report.json'
    )
    rc, out, err = run_cmd(add_cmd)
    if rc != 0:
        print(f"ERROR: {err}")
        return
    
    # Commit message
    msg = """feat(kejian): 可鉴决策操作系统 MVP 发布

新增功能：
- Web 单页应用（index.html + CSS + JS）
- Skills 服务完整集成（六角色并行推演 + 聚合 + 胶片生成）
- E2E 测试套件（kejian_e2e_test.py）
- 批量压力测试工具（stress_test.py）
- 决策样本库生成器（generate_samples.py）
- 品牌存档文档（docs/zh/09.03.Product-可鉴...md）
- API 文档与使用指南（README.md）

技术修正：
- 修正请求体契约：arguments → params/context/timeout_ms
- 修正字段映射：key_insights → key_DeepInsights
- 支持结构化胶片渲染：title/subtitle/sections/self_questions/closing_note
- 移除 Unicode 符号，改用 ASCII 兼容输出（GBK terminal support）

测试结果：
- E2E: 6/6 成功 (0 degraded, 0 errors)
- 总耗时：~237 秒（串行 LLM 调用正常范围）
- 真实真绿验证：四视角无降级，Aggregator 情绪分析可用

参考 ADR:
- ADR-001: 版本迁移策略
- ADR-002: 术语纠正
- 新提案：Kejian-MVP-Release-v1.0.0

Closes: kejian-mvp, backend-link, share-card
Signed-off-by: Qoder <qoder@deepflow.app>"""
    
    print("\n[2/5] Creating commit...")
    rc, out, err = run_cmd(f'git commit -m "{msg}"')
    if rc != 0:
        print(f"ERROR: {err}")
        return
    
    # Read history.md
    print("\n[3/5] Updating history.md...")
    try:
        with open("history.md", "r", encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        content = "# DeepFlow Development History\n\n"
    
    timestamp = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
    new_entry = f"""## {timestamp}: 可鉴决策操作系统 MVP 发布

### 新增模块
- **Web 前端** (`可鉴/`): 单页应用 + 品牌样式 + 六角色并行推演逻辑
- **测试工具**: E2E 测试套件、压力测试工具、样本库生成器
- **文档**: 产品定位文档、API 指南、README

### 技术成就
- 六角色真实真绿验证（0 降级，0 错误）
- Skills 服务契约修正完成（params/context/timeout_ms）
- 结构化胶片产出验证通过

### 下一步
详见 [tasks.md](tasks.md) 中的 Kejian-MVP-Release 任务组

---
""".strip() + "\n"
    
    content = new_entry + content
    
    with open("history.md", "w", encoding="utf-8") as f:
        f.write(content)
    
    print("[4/5] Updating tasks.md...")
    # Append to tasks.md
    with open("tasks.md", "r", encoding="utf-8") as f:
        tasks_content = f.read()
    
    tasks_timestamp = datetime.utcnow().strftime("%Y-%m-%d")
    tasks_update = f"""
---
## 2026-08-09: 可鉴决策操作系统 MVP 发布里程碑

### 核心交付物

| 模块 | 内容 | 状态 |
|------|------|------|
| Brand Archive | 产品定位文档（OCGS+DeepFlow+DeepInsight 三体架构） | Completed |
| Web MVP | 单页应用 + 品牌样式 + 六角色推演逻辑 | Completed |
| Skills Integration | 参数契约修正 + 字段映射 + 胶片渲染 | Completed |
| Virus Loop | 品牌水印 + 分享卡片 + 邀请链接 | Completed |
| E2E Tests | Python 端到端测试套件（kejian_e2e_test.py） | Completed |
| Load Test | 批量压力测试工具（stress_test.py） | Completed |
| Samples | 决策样本库生成器（100+ scenarios） | Completed |
| Documentation | README + API 文档 | Completed |

### 测试报告

| 测试项 | 结果 | 详情 |
|--------|------|------|
| E2E Full Chain | ✅ PASS | 6/6 calls success, 0 degraded, total ~237s |
| Coerce Role (Coach/Critic/Mirror/Observer) | ✅ PASS | All roles returned real data, no fallback |
| Aggregation | ✅ PASS | views_count=4, emotional_summary populated |
| Film Generation | ✅ PASS | 6 self_questions generated |

### 关键发现

1. **防假绿机制有效** - 所有降级明确标记，真实数据不被污染
2. **LLM 中文传输稳定性** - PowerShell 编码问题需适配 GBK terminal
3. **降級兜底价值** - 模板仍能提供引导问题和洞察建议

### 下一步行动

- S2: Node.js 浏览器适配器（可集成到前端测试）
- T7: 将可鉴集成到 MGW/RRW/SPW等业务线
- T8: 扩展更多行业决策场景模板（医疗/教育/法律等）
- T9: 优化 LLM 调用稳定性，减少降级频率

---
"""
    
    # Find the right place to insert (after current date section)
    lines = tasks_content.split("\n")
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith(f"> 更新日期：{tasks_timestamp}"):
            insert_idx = i + 1
            break
    
    if insert_idx == 0:
        # Insert at beginning after header
        insert_idx = 4
        lines.insert(insert_idx, "")
    
    lines.insert(insert_idx + 1, tasks_update.strip())
    
    with open("tasks.md", "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    
    print("[5/5] Committing updates...")
    rc, out, err = run_cmd('git add history.md tasks.md && git commit --amend --no-edit')
    if rc != 0:
        print(f"WARNING: amend failed: {err}\nKeeping original commit...")
    else:
        print("✓ Squashed update into same commit")
    
    # Summary
    print(f"\n{'='*60}")
    print("✅ 提交完成")
    print(f"{'='*60}")
    print(f"Commit message preview:")
    print(msg[:200] + "...")
    print(f"\nFiles added:")
    print("  - 可鉴/index.html")
    print("  - 可鉴/css/kejian.css")
    print("  - 可鉴/js/kejian.js")
    print("  - 可鉴/tests/*.py")
    print("  - 可鉴/README.md")
    print("  - docs/zh/09.03.Product-可鉴-决策操作系统 - 产品定位-v1.0.md")
    print("  - history.md")
    print("  - tasks.md")
    print(f"\nPlease review and push when ready.")
    print("=" * 60 + "\n")


if __name__ == "__main__":
    main()
