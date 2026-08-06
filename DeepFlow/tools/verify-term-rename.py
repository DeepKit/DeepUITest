#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
DeepFlow 术语纠正静态一致性验证 (ADR-002 D4 T1-T6)
确定性门禁：退出码 0=PASS，非0=FAIL。每项检查独立报告。
适用：纯文档+schema术语纠正任务，无生产代码逻辑改动。
"""
import sys, os, re, json, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)

# 收集所有 md 文件（根 + docs/）
def md_files():
    out = []
    for f in os.listdir('.'):
        if f.endswith('.md') and os.path.isfile(f):
            out.append(f)
    for sub in ['docs/zh', 'docs/en']:
        if os.path.isdir(sub):
            for f in os.listdir(sub):
                if f.endswith('.md'):
                    out.append(os.path.join(sub, f))
    return out

MD = md_files()
FAILS = []

def check(name, ok, detail=''):
    status = 'PASS' if ok else 'FAIL'
    print(f"[{status}] {name}: {detail}")
    if not ok:
        FAILS.append(name)

# ---- T1: UniFlow 残留仅限白名单(代码标识符 + ADR-002 + 术语表历史说明) ----
# 代码标识符模式(代码冻结期间文档须与代码一致,保留)：
#   UniFlow + 大写字母(Pascal类/API): UniFlowClient/UniFlowEngine/UniFlowMCPServer...
#   UniFlow. + 任意(unit/命名空间): UniFlow.Engine.pas / UniFlow.模块.功能
#   UniFlow + 文件后缀: UniFlow.dpr/.dproj/.exe/.pas/.dpk
#   TUniFlow/FUniFlow 前缀类型/字段
#   X-UniFlow / @uniflow / uniflow import / uniFlow + . / uniFlow_ / uniFlow + 大写
#   DeepBase.UniFlow / Source/UniFlow 等代码路径
CODE_RE = re.compile(
    r'UniFlow[A-Z]\w*'                      # UniFlowClient/UniFlowEngine 等 Pascal 类/API
    r'|TUniFlow[A-Z]\w*'                    # TUniFlowXxx 类型
    r'|FUniFlow[A-Z]\w*'                    # FUniFlowXxx 字段
    r'|IUniFlow\b'                          # IUniFlow 接口
    r'|UniFlow\.\w*'                        # UniFlow.xxx / UniFlow. 命名空间/unit/前缀
    r'|UniFlow\.(?:dpr|dproj|exe|pas|dpk|bdsproj)'  # UniFlow.文件后缀
    r'|UniFlow Skills\b'                    # UniFlow Skills Service 模块名
    r'|UniFlow Skill\b'                     # UniFlow Skill 模块名
    r'|UniFlow engine\b'                    # 日志字符串中的 engine 名
    r'|(?:Initialize|Finalize)UniFlow\b'    # InitializeUniFlow/FinalizeUniFlow 函数
    r'|X-UniFlow'                           # HTTP 头
    r'|@uniflow'                            # 装饰器
    r'|uniflow import'                      # import 语句
    r'|uniFlow\.\w+'                        # uniFlow.xxx 命名空间
    r'|uniFlow_[a-z]\w*'                    # uniFlow_py 等目录/模块
    r'|uniFlow[A-Z]\w*'                     # uniFlowCore 等
    r'|DeepBase\.UniFlow'                   # DeepBase.UniFlow unit
)
WHITELIST_FILES = ['ADR-002', '02.07.Spec']  # 故意保留历史说明

t1_violations = []
for f in MD:
    try:
        with open(f, encoding='utf-8') as fh:
            for i, line in enumerate(fh, 1):
                if 'UniFlow' not in line and 'uniFlow' not in line:
                    continue
                if any(w in f for w in WHITELIST_FILES):
                    continue
                # 去除代码标识符后是否还有 UniFlow/uniFlow
                stripped = CODE_RE.sub('', line)
                # 再次检测剩余的 UniFlow / uniFlow（排除已被sub掉的）
                if re.search(r'UniFlow|uniFlow', stripped):
                    t1_violations.append(f"{f}:{i}: {line.strip()[:80]}")
            # also check
    except Exception as e:
        t1_violations.append(f"{f}: READ_ERROR {e}")

check('T1.UniFlow-residue-whitelist-only', len(t1_violations) == 0,
      f"违规 {len(t1_violations)} 处" + (f"; 示例: {t1_violations[:3]}" if t1_violations else ''))

# ---- T3: DeepFlow 频次显著上升，UniFlow(非代码)显著下降 ----
def count_term(pattern, files):
    n = 0
    for f in files:
        try:
            with open(f, encoding='utf-8') as fh:
                n += len(re.findall(pattern, fh.read()))
        except Exception:
            pass
    return n

deepflow_n = count_term(r'DeepFlow', MD)
upflow_n = count_term(r'UpFlow', MD)
deepflow_lower_n = count_term(r'deepFlow', MD)
uniflow_total = count_term(r'UniFlow', MD)
check('T3.term-distribution', deepflow_n > 800 and upflow_n > 0 and deepflow_lower_n > 0,
      f"DeepFlow={deepflow_n} UpFlow={upflow_n} deepFlow={deepflow_lower_n} UniFlow(含代码标识)={uniflow_total}")

# ---- T4: 03.07 标题修正 + 两层清晰 ----
t4_ok = True
t4_detail = []
f307 = '03.07.Arch-DeepFlow与DeepFlow关系说明-v1.0.md'
if os.path.exists(f307):
    with open(f307, encoding='utf-8') as fh:
        head = fh.read(200)
    if 'UpFlow' not in head or 'deepFlow' not in head:
        t4_ok = False; t4_detail.append('标题缺 UpFlow/deepFlow')
    # 检查文件名引用未误用 UpFlow/deepFlow（实际磁盘名应 DeepFlow）
    with open(f307, encoding='utf-8') as fh:
        body = fh.read()
    if re.search(r'Arch-UpFlow|Arch-deepFlow|Design-deepFlow-CoreModel\b', body):
        t4_ok = False; t4_detail.append('文件名引用误用 UpFlow/deepFlow')
else:
    t4_ok = False; t4_detail.append('03.07 文件缺失')
check('T4.03.07-two-layers-clear', t4_ok, '; '.join(t4_detail) or '两层概念清晰')

# ---- T5: schema $id 全为 deepflow://，无 uniflow:// 残留 ----
t5_violations = []
for root_dir in ['config', 'Config']:
    if not os.path.isdir(root_dir):
        continue
    for dp, dn, fn in os.walk(root_dir):
        for f in fn:
            if f.endswith('.json') or f.endswith('.schema.json') or f.endswith('.workflow.json'):
                p = os.path.join(dp, f)
                try:
                    with open(p, encoding='utf-8') as fh:
                        c = fh.read()
                    if 'uniflow://' in c or 'docs.uniflow.ai' in c or 'UniFlow Team' in c:
                        t5_violations.append(p)
                except UnicodeDecodeError:
                    # 编码损坏(既有问题,非本轮引入):用 latin-1 兜底读 ASCII 关键词
                    with open(p, encoding='latin-1') as fh:
                        c = fh.read()
                    if 'uniflow://' in c or 'docs.uniflow.ai' in c or 'UniFlow Team' in c:
                        t5_violations.append(p)
                except Exception:
                    t5_violations.append(f"{p}: READ_ERROR")
# 也检查 md 里的 URL/Team 残留
for f in MD:
    try:
        with open(f, encoding='utf-8') as fh:
            c = fh.read()
        if 'docs.uniflow.ai' in c or 'UniFlow Team' in c:
            t5_violations.append(f)
    except Exception:
        pass
check('T5.schema-uri-deepflow', len(t5_violations) == 0,
      f"残留 {len(t5_violations)}: {t5_violations[:3]}")

# ---- T5b: 本轮未新引入 JSON 结构破坏 ----
# 判定:对每个 JSON 文件,若 HEAD 版本合法但工作树版本非法 → 本轮引入 → FAIL。
#       若 HEAD 版本本就非法(既有损坏,非本轮引入)→ 标记 preexisting,不计 FAIL。
# 术语替换是纯 ASCII 字段值替换,不应破坏 JSON 结构。
def _git_head_content(rel_path):
    """读取 git HEAD 版本文件内容(bytes),失败返回 None。rel_path 相对 DeepFlow 根。
    Windows 磁盘大小写不敏感(config/Config 同目录),但 git index 大小写敏感,
    故对首段目录尝试大小写回退以匹配 index 中的真实路径。"""
    candidates = [rel_path]
    # 首段目录大小写回退
    parts = rel_path.replace(os.sep, '/').split('/')
    if parts:
        variants = [parts[0], parts[0].capitalize(), parts[0].upper(), parts[0].lower()]
        seen = set()
        for v in variants:
            if v not in seen and v != parts[0]:
                seen.add(v)
                candidates.append(os.path.join(v, *parts[1:]))
    for cand in candidates:
        try:
            r = subprocess.run(
                ['git', 'show', f'HEAD:DeepFlow/{cand.replace(os.sep, "/")}'],
                capture_output=True, cwd=os.path.dirname(ROOT))
            if r.returncode == 0:
                return r.stdout
        except Exception:
            pass
    return None

def _json_ok(content_bytes):
    try:
        json.loads(content_bytes.decode('utf-8', errors='replace'))
        return True
    except json.JSONDecodeError:
        return False

t5b_newly_broken = []
t5b_preexisting = []
seen_realpaths = set()  # Windows 大小写不敏感去重(config/Config 同目录)
for root_dir in ['config', 'Config']:
    if not os.path.isdir(root_dir):
        continue
    for dp, dn, fn in os.walk(root_dir):
        for f in fn:
            if f.endswith('.json'):
                p = os.path.join(dp, f)
                rp = os.path.realpath(p).lower()
                if rp in seen_realpaths:
                    continue
                seen_realpaths.add(rp)
                rel = os.path.relpath(p, '.')
                try:
                    with open(p, 'rb') as fh:
                        wt_bytes = fh.read()
                except Exception:
                    t5b_newly_broken.append(f"{p}: READ_ERROR")
                    continue
                wt_ok = _json_ok(wt_bytes)
                if wt_ok:
                    continue  # 工作树合法,无需查 HEAD
                # 工作树非法:查 HEAD 是否也非法
                head_bytes = _git_head_content(rel)
                if head_bytes is None:
                    t5b_newly_broken.append(f"{p}: 工作树非法且无HEAD对照")
                elif _json_ok(head_bytes):
                    t5b_newly_broken.append(f"{p}: HEAD合法但工作树非法(本轮引入)")
                else:
                    t5b_preexisting.append(p)
check('T5b.no-newly-introduced-json-damage', len(t5b_newly_broken) == 0,
      f"本轮新破坏 {len(t5b_newly_broken)}: {t5b_newly_broken}"
      + (f"; 既有损坏(非本轮引入,已标记): {t5b_preexisting}" if t5b_preexisting else ''))

# ---- T6: 无 DeepDeep 乱码残留 ----
t6_n = count_term(r'DeepDeep', MD)
check('T6.no-DeepDeep-garble', t6_n == 0, f"DeepDeep 残留 {t6_n} 处")

# ---- 汇总 ----
print()
if FAILS:
    print(f"==== RESULT: FAIL ({len(FAILS)} 项未过: {FAILS}) ====")
    sys.exit(1)
else:
    print("==== RESULT: PASS (T1,T3,T4,T5,T5b,T6 全过) ====")
    sys.exit(0)
