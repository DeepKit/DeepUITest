"""
asto.cc �?差异一元论理论展示�?FastAPI + Jinja2，从本地 markdown 文件渲染理论内容
"""

import json
import os
import re
from pathlib import Path

import markdown
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from jinja2 import Environment, FileSystemLoader, select_autoescape

BASE_DIR = Path(__file__).parent
CONTENT_DIR = BASE_DIR / "content"
TEMPLATE_DIR = BASE_DIR / "templates"
STATIC_DIR = BASE_DIR / "static"

# --- Jinja2 ---
env = Environment(
    loader=FileSystemLoader(str(TEMPLATE_DIR)),
    autoescape=select_autoescape(["html"]),
)

# --- FastAPI ---
app = FastAPI(title="asto.cc", version="1.0.0")
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


def load_layers() -> list[dict]:
    path = CONTENT_DIR / "layers.json"
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_site_config() -> dict:
    path = CONTENT_DIR / "site.json"
    with open(path, encoding="utf-8") as f:
        return json.load(f)


GITHUB_BASE = "https://github.com/ODDFounder/difference-monism/blob/main"
# 独立仓库（优先于总库�?STANDALONE_REPOS = {
    "odd": "https://github.com/ODDFounder/ODD/blob/main",
    "asto": "https://github.com/ODDFounder/ASTO/blob/main",
}

# 文件路径模式：markdown 渲染后的 <code>dir/file.md</code>
_FILE_PATH_RE = re.compile(
    r"<code>([^<]+\.(?:md|py|txt|json|sql|yaml|yml))</code>"
)


def _linkify_file_paths(html: str, source_dir: str = "", github_repo: str = "") -> str:
    """�?HTML 中的 <code>path/to/file.md</code> 转为 GitHub 链接"""
    base = github_repo or f"{GITHUB_BASE}/{source_dir}" if source_dir else GITHUB_BASE

    def _replace(m):
        path = m.group(1)
        if path.startswith("http") or path.startswith("/"):
            return m.group(0)
        if github_repo:
            full = path
        else:
            full = f"{source_dir}/{path}" if source_dir else path
        url = f"{base}/{full}"
        return f'<a href="{url}" target="_blank"><code>{path}</code></a>'
    return _FILE_PATH_RE.sub(_replace, html)


def read_md(rel_path: str, source_dir: str = "", slug: str = "") -> str:
    """读取 content/ 下的 markdown 文件，返�?HTML，文件路径自动转�?GitHub 链接"""
    full = CONTENT_DIR / rel_path
    if not full.exists():
        return "<p>内容待补�?/p>"
    text = full.read_text(encoding="utf-8")
    html = markdown.markdown(text, extensions=["tables", "fenced_code", "toc"])
    github_repo = STANDALONE_REPOS.get(slug, "")
    return _linkify_file_paths(html, source_dir=source_dir, github_repo=github_repo)


def render(template_name: str, **context) -> HTMLResponse:
    tmpl = env.get_template(template_name)
    html = tmpl.render(**context)
    return HTMLResponse(content=html)


@app.get("/")
def home():
    site = load_site_config()
    layers = load_layers()
    # 首页的系统总览
    overview_html = read_md("overview.md")
    return render("index.html", site=site, layers=layers, overview=overview_html)


@app.get("/about")
def about():
    site = load_site_config()
    citation_html = read_md("citation.md")
    return render("about.html", site=site, citation=citation_html)


@app.get("/walkthrough")
def walkthrough():
    site = load_site_config()
    layers = load_layers()
    body_html = read_md("walkthrough.md", source_dir="")
    return render("walkthrough.html", site=site, layers=layers, body=body_html)


@app.get("/{slug}")
def layer_page(slug: str):
    site = load_site_config()
    layers = load_layers()
    layer = None
    for l in layers:
        if l["slug"] == slug:
            layer = l
            break
    if not layer:
        raise HTTPException(status_code=404, detail="Layer not found")
    body_html = read_md(layer["overview_file"], source_dir=layer.get("github_dir", ""), slug=slug)
    return render("layer.html", site=site, layers=layers, layer=layer, body=body_html)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
