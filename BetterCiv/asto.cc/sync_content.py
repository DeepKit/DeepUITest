"""
sync_content.py �?从一元论仓库提取公开内容�?asto.cc/content/

用法�?    python sync_content.py

�?asto.cc/ 目录下运行，会自动从 D:/_Progs/一元论/ 提取白名单文�?�?content/ 目录下。部署前运行一次即可�?"""

import shutil
from pathlib import Path

SOURCE = Path(r"D:\_Progs\一元论")
TARGET = Path(__file__).parent / "content"

# 白名单：每个层级的概览文�?LAYER_OVERVIEWS = {
    "dm":   SOURCE / "10-哲学核心层（DM�? / "ai差异一元论总览.md",
    "asto": SOURCE / "20-应用框架层（ASTO�? / "ai属集变迁存在论总览.md",
    "ecet": SOURCE / "30-文明演化层（ECET�? / "ai演化约束存在论总览.md",
    "tat":  SOURCE / "40-责任架构层（TAT�? / "ai责任架构理论总览.md",
    "odd":  SOURCE / "50-工程方法层（ODD�? / "ai产出物驱动开发总览.md",
    "cop":  SOURCE / "51-认知计算层（COP�? / "ai认知计算协议总览.md",
    "lmm":  SOURCE / "52-认知方法层（LMM�? / "public" / "ai灯塔营销方法论总览.md",
    "rt6":  SOURCE / "53-操作方法层（RT6�? / "ai共鸣与跃迁六步法总览.md",
}

# 其他公开文件
EXTRA_FILES = {
    "overview.md":     SOURCE / "ai一元论理论体系总览.md",
    "walkthrough.md":  SOURCE / "八层统一走通_医院AI诊断系统部署决策.md",
}

# 引用信息（从 CITATION.cff 生成�?CITATION_MD = """# 引用指南

## BibTeX

```bibtex
@software{fu2026difference,
  author = {Fu, Yi},
  title = {Difference Monism Theory Stack},
  year = {2026},
  version = {publication-snapshot-2026-03-20},
  publisher = {Zenodo},
  doi = {10.5281/zenodo.18207648}
}
```

## 引用格式

> Fu, Y. (2026). Difference Monism Theory Stack / 差异一元论理论�?
> Zenodo. https://doi.org/10.5281/zenodo.18207648

## ORCID

0009-0008-1251-2632

## 许可

- 代码/配置: MIT
- 论文/出版内容: CC-BY-4.0
"""


def sync():
    layers_dir = TARGET / "layers"
    layers_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    for slug, src in LAYER_OVERVIEWS.items():
        if src.exists():
            dst = layers_dir / f"{slug}.md"
            shutil.copy2(src, dst)
            print(f"  [OK] {slug}: {src.name}")
            count += 1
        else:
            print(f"  [MISSING] {slug}: {src}")

    for name, src in EXTRA_FILES.items():
        if src.exists():
            shutil.copy2(src, TARGET / name)
            print(f"  [OK] {name}")
            count += 1
        else:
            print(f"  [MISSING] {name}: {src}")

    # 写引用文�?    (TARGET / "citation.md").write_text(CITATION_MD, encoding="utf-8")
    print(f"  [OK] citation.md (generated)")
    count += 1

    print(f"\nDone: {count} files synced to {TARGET}")


if __name__ == "__main__":
    sync()
