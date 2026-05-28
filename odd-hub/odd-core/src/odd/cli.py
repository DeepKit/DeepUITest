"""
CLI 入口 - odd init / odd verify / odd seal / odd template
"""

import sys
import json
import yaml
from pathlib import Path
from datetime import datetime

import click
from rich.console import Console

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
from rich.table import Table

from odd.verifier import ContractVerifier
from odd.sealer import SealManager

TEMPLATES_DIR = Path(__file__).parent / "templates"

console = Console(highlight=False)
ODD_DIR = Path(".odd")


@click.group()
@click.version_option(package_name="odd-core")
def cli():
    """ODD (Output-Driven Development) CLI"""


# ── odd init ──────────────────────────────────────────────────────────────────

@cli.command()
def init():
    """初始化当前目录的 ODD 工作�?""
    if ODD_DIR.exists():
        console.print("[yellow]已存�?.odd/ 目录，跳过初始化[/yellow]")
        return

    (ODD_DIR / "contracts").mkdir(parents=True)
    (ODD_DIR / "seals").mkdir(parents=True)

    config = {"odd_version": "0.1.0", "project": Path.cwd().name}
    (ODD_DIR / "config.yaml").write_text(
        yaml.dump(config, allow_unicode=True), encoding="utf-8"
    )

    console.print("[green]OK[/green] 初始化完成：.odd/contracts/  .odd/seals/  .odd/config.yaml")


def _run_verify_all() -> None:
    """批量验证 .odd/contracts/ 下所有契约对应的代码文件"""
    contracts_dir = ODD_DIR / "contracts"
    if not contracts_dir.exists():
        console.print("[red]找不�?.odd/contracts/ 目录，请先运�?odd init[/red]")
        sys.exit(1)

    contracts = list(contracts_dir.glob("*.yaml"))
    if not contracts:
        console.print("[yellow]没有找到任何契约文件[/yellow]")
        return

    all_passed = True
    for contract_path in contracts:
        code_path = Path(contract_path.stem)
        for ext in (".py", ".js", ".ts", ".go", ".java", ".rb", ".rs"):
            candidate = code_path.with_suffix(ext)
            if candidate.exists():
                code_path = candidate
                break
        else:
            console.print(f"[yellow]跳过 {contract_path.name}：找不到对应代码文件[/yellow]")
            continue

        code = code_path.read_text(encoding="utf-8")
        contract = yaml.safe_load(contract_path.read_text(encoding="utf-8"))
        hints = contract.get("verification_hints", {})
        result = ContractVerifier().verify(code, hints)
        status = "[green]PASS[/green]" if result["passed"] else "[red]FAIL[/red]"
        console.print(f"  {status}  {code_path}  ({contract_path.name})")
        if not result["passed"]:
            all_passed = False

    if all_passed:
        console.print("[green]全部通过[/green]")
    else:
        console.print("[red]存在验证失败[/red]")
        sys.exit(1)


# ── odd verify ────────────────────────────────────────────────────────────────

@cli.command()
@click.argument("code_file", type=click.Path(exists=True), required=False)
@click.option("--contract", "-c", "contract_file", type=click.Path(exists=True),
              help="契约 YAML 文件路径（默认自动匹�?.odd/contracts/<stem>.yaml�?)
@click.option("--all", "verify_all", is_flag=True, help="批量验证 .odd/contracts/ 下所有契�?)
@click.option("--ai", "use_ai", is_flag=True, help="启用 AI 语义验证层（需设置 ODD_AI_API_KEY�?)
def verify(code_file: str | None, contract_file: str | None, verify_all: bool, use_ai: bool):
    """验证代码文件是否符合契约"""
    if verify_all:
        _run_verify_all()
        return
    if not code_file:
        console.print("[red]请指定代码文件，或使�?--all 批量验证[/red]")
        sys.exit(1)
    code_path = Path(code_file)
    code = code_path.read_text(encoding="utf-8")

    if contract_file is None:
        auto = ODD_DIR / "contracts" / f"{code_path.stem}.yaml"
        if not auto.exists():
            console.print(f"[red]找不到契约文件：{auto}[/red]")
            console.print("请用 --contract 指定，或将契约放�?.odd/contracts/<stem>.yaml")
            sys.exit(1)
        contract_file = str(auto)

    contract = yaml.safe_load(Path(contract_file).read_text(encoding="utf-8"))
    hints = contract.get("verification_hints", {})

    result = ContractVerifier().verify(code, hints)

    if use_ai:
        from odd.ai_verifier import AIVerifier
        ai = AIVerifier()
        ai_result = ai.verify(code, contract)
        console.print(f"\n[bold]AI 语义验证[/bold]")
        verdict_color = "green" if ai_result["passed"] else "red"
        console.print(f"  [{verdict_color}]{ai_result['verdict']}[/{verdict_color}]")
        console.print(f"  {ai_result['reasoning']}")
        if ai_result.get("suggestions"):
            for s in ai_result["suggestions"]:
                console.print(f"  �?{s}")

    table = Table(title=f"验证结果：{code_path.name}", show_lines=True)
    table.add_column("规则", style="cyan", no_wrap=False)
    table.add_column("类型", style="dim")
    table.add_column("严重�?)
    table.add_column("结果")

    for check in result["checks"]:
        status = "[green]PASS[/green]" if check["passed"] else "[red]FAIL[/red]"
        severity_color = {"critical": "red", "medium": "yellow", "low": "dim"}.get(check["severity"], "white")
        table.add_row(
            check["rule"],
            check["type"],
            f"[{severity_color}]{check['severity']}[/{severity_color}]",
            status,
        )

    console.print(table)

    if result["passed"]:
        console.print("[green]PASS 验证通过[/green]")
    else:
        console.print("[red]FAIL 验证失败[/red]")
        sys.exit(1)


# ── odd seal ──────────────────────────────────────────────────────────────────

@cli.command()
@click.argument("code_file", type=click.Path(exists=True))
@click.option("--contract", "-c", "contract_file", type=click.Path(exists=True),
              help="契约 YAML 文件路径")
def seal(code_file: str, contract_file: str | None):
    """封存代码 + 契约 + 验证结果（SHA-256 哈希链）"""
    code_path = Path(code_file)
    code = code_path.read_text(encoding="utf-8")

    if contract_file is None:
        auto = ODD_DIR / "contracts" / f"{code_path.stem}.yaml"
        if not auto.exists():
            console.print(f"[red]找不到契约文件：{auto}[/red]")
            sys.exit(1)
        contract_file = str(auto)

    contract = yaml.safe_load(Path(contract_file).read_text(encoding="utf-8"))
    hints = contract.get("verification_hints", {})
    verification = ContractVerifier().verify(code, hints)

    seal_dir = ODD_DIR / "seals"
    seal_dir.mkdir(parents=True, exist_ok=True)

    record = SealManager().seal(contract, code, verification, seal_dir)

    console.print(f"[green]OK 封存完成[/green]")
    console.print(f"  seal_id  : {record['seal_id']}")
    console.print(f"  integrity: {record['integrity']}")
    console.print(f"  文件     : {record['file']}")


# ── odd template ──────────────────────────────────────────────────────────────

@cli.group()
def template():
    """管理契约模板"""


@template.command("list")
def template_list():
    """列出所有内置模�?""
    templates = sorted(TEMPLATES_DIR.glob("*.yaml"))
    if not templates:
        console.print("[yellow]暂无模板[/yellow]")
        return
    console.print(f"内置模板（共 {len(templates)} 个）�?)
    for t in templates:
        meta = yaml.safe_load(t.read_text(encoding="utf-8"))
        console.print(f"  {t.stem:<25} {meta.get('name', '')}")


@template.command("pull")
@click.argument("template_name")
@click.option("--out", "-o", default=None, help="输出路径（默�?.odd/contracts/<name>.yaml�?)
def template_pull(template_name: str, out: str | None):
    """将内置模板复制到当前项目�?.odd/contracts/"""
    src = TEMPLATES_DIR / f"{template_name}.yaml"
    if not src.exists():
        console.print(f"[red]模板不存在：{template_name}[/red]")
        console.print("运行 `odd template list` 查看可用模板")
        sys.exit(1)

    dest = Path(out) if out else ODD_DIR / "contracts" / f"{template_name}.yaml"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    console.print(f"[green]OK[/green] 模板已复制到 {dest}")


@template.command("push")
@click.argument("contract_file", type=click.Path(exists=True))
def template_push(contract_file: str):
    """将本地契约保存为内置模板（开发用�?""
    src = Path(contract_file)
    dest = TEMPLATES_DIR / src.name
    TEMPLATES_DIR.mkdir(parents=True, exist_ok=True)
    dest.write_text(src.read_text(encoding="utf-8"), encoding="utf-8")
    console.print(f"[green]OK[/green] 已保存为模板：{dest.stem}")


# ── odd freeze ────────────────────────────────────────────────────────────────

@cli.command("freeze")
@click.argument("contract_name")
def freeze(contract_name: str):
    """锁定契约，禁止修改（FREEZE 状态）"""
    contract_file = ODD_DIR / "contracts" / f"{contract_name}.yaml"
    if not contract_file.exists():
        console.print(f"[red]契约不存在：{contract_name}[/red]")
        sys.exit(1)

    meta = yaml.safe_load(contract_file.read_text(encoding="utf-8"))
    if meta.get("frozen"):
        console.print(f"[yellow]契约已处于冻结状态：{contract_name}[/yellow]")
        return

    meta["frozen"] = True
    meta["frozen_at"] = datetime.now().isoformat()
    contract_file.write_text(yaml.dump(meta, allow_unicode=True), encoding="utf-8")
    console.print(f"[green]OK[/green] 契约已冻结：{contract_name}")


@cli.command("unfreeze")
@click.argument("contract_name")
def unfreeze(contract_name: str):
    """解锁契约，允许修�?""
    contract_file = ODD_DIR / "contracts" / f"{contract_name}.yaml"
    if not contract_file.exists():
        console.print(f"[red]契约不存在：{contract_name}[/red]")
        sys.exit(1)

    meta = yaml.safe_load(contract_file.read_text(encoding="utf-8"))
    if not meta.get("frozen"):
        console.print(f"[yellow]契约未冻结：{contract_name}[/yellow]")
        return

    meta.pop("frozen", None)
    meta.pop("frozen_at", None)
    contract_file.write_text(yaml.dump(meta, allow_unicode=True), encoding="utf-8")
    console.print(f"[green]OK[/green] 契约已解锁：{contract_name}")
