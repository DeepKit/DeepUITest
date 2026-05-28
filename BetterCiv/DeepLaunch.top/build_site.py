"""Build all HTML files for DeepLaunch.top"""

import os

BASE = os.path.dirname(os.path.abspath(__file__))


def write(path, content):
    full = os.path.join(BASE, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  Wrote: {path}")


# ============================================================
# CSS
# ============================================================
css = r"""/* ============================================================
   DeepLaunch.top - Tool Hub Site
   Design: Dark Tech
   ============================================================ */

:root {
    --bg: #0f0f17;
    --bg-elevated: #181825;
    --bg-surface: #1e1e2e;
    --bg-hover: #252538;
    --border: #2a2a3d;
    --border-light: #353550;
    --ink: #e0e0e6;
    --ink-strong: #f0f0f5;
    --muted: #8888a0;
    --accent: #5b9bd5;
    --accent-glow: rgba(91, 155, 213, 0.18);
    --accent-strong: #7ab8f0;
    --green: #4ec9a0;
    --orange: #e8a850;
    --red: #e06060;
    --gap-xs: 6px;
    --gap-sm: 12px;
    --gap-md: 24px;
    --gap-lg: 48px;
    --gap-xl: 80px;
    --max-w: 1100px;
    --radius-sm: 6px;
    --radius-md: 10px;
    --radius-lg: 16px;
    --shadow-card: 0 2px 16px rgba(0,0,0,0.35);
    --shadow-glow: 0 0 40px rgba(91,155,213,0.12);
    --font-sans: "Segoe UI", "Microsoft YaHei UI", system-ui, -apple-system, sans-serif;
    --font-mono: "Cascadia Code", "JetBrains Mono", "Fira Code", "Consolas", monospace;
}

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

html { scroll-behavior: smooth; font-size: 16px; }

body {
    font-family: var(--font-sans);
    background: var(--bg);
    color: var(--ink);
    line-height: 1.65;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
}

a { color: var(--accent); text-decoration: none; transition: color 0.2s; }
a:hover { color: var(--accent-strong); }

img { max-width: 100%; height: auto; display: block; }
ul, ol { list-style: none; }

h1, h2, h3, h4 { color: var(--ink-strong); font-weight: 600; line-height: 1.3; }
h1 { font-size: 2.6rem; letter-spacing: -0.02em; }
h2 { font-size: 1.9rem; letter-spacing: -0.01em; }
h3 { font-size: 1.3rem; }
h4 { font-size: 1.1rem; }

.container { max-width: var(--max-w); margin: 0 auto; padding: 0 var(--gap-md); }
.section { padding: var(--gap-xl) 0; }

/* Header */
.site-header {
    position: sticky; top: 0; z-index: 100;
    background: rgba(15,15,23,0.85);
    backdrop-filter: blur(14px);
    -webkit-backdrop-filter: blur(14px);
    border-bottom: 1px solid var(--border);
}
.nav-bar {
    display: flex; align-items: center; justify-content: space-between;
    height: 56px; max-width: var(--max-w); margin: 0 auto; padding: 0 var(--gap-md);
}
.nav-logo { display: flex; align-items: center; gap: var(--gap-xs); font-size: 1.2rem; font-weight: 700; color: var(--ink-strong); letter-spacing: -0.01em; }
.nav-logo .logo-accent { color: var(--accent); font-weight: 800; }
.nav-links { display: flex; align-items: center; gap: var(--gap-md); }
.nav-links a { font-size: 0.9rem; color: var(--muted); font-weight: 500; transition: color 0.2s; }
.nav-links a:hover, .nav-links a.active { color: var(--ink-strong); }
.nav-lang { font-size: 0.8rem; color: var(--muted); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 2px 8px; transition: all 0.2s; }
.nav-lang:hover { color: var(--ink-strong); border-color: var(--border-light); }

/* Hero */
.hero { text-align: center; padding: 100px 0 80px; position: relative; overflow: hidden; }
.hero::before { content: ''; position: absolute; top: -60%; left: 50%; transform: translateX(-50%); width: 800px; height: 800px; background: radial-gradient(circle, var(--accent-glow) 0%, transparent 70%); pointer-events: none; }
.hero h1 { font-size: 3.2rem; margin-bottom: var(--gap-sm); position: relative; }
.hero h1 .hl { color: var(--accent); }
.hero .subtitle { font-size: 1.25rem; color: var(--muted); max-width: 560px; margin: 0 auto var(--gap-lg); }
.hero-actions { display: flex; gap: var(--gap-sm); justify-content: center; flex-wrap: wrap; }

/* Buttons */
.btn { display: inline-flex; align-items: center; gap: 8px; padding: 12px 28px; font-size: 0.95rem; font-weight: 600; font-family: var(--font-sans); border: none; border-radius: var(--radius-sm); cursor: pointer; transition: all 0.2s; text-decoration: none; white-space: nowrap; }
.btn-primary { background: var(--accent); color: #fff; }
.btn-primary:hover { background: var(--accent-strong); color: #fff; box-shadow: var(--shadow-glow); }
.btn-outline { background: transparent; color: var(--ink); border: 1px solid var(--border); }
.btn-outline:hover { border-color: var(--accent); color: var(--accent-strong); }
.btn-lg { padding: 14px 36px; font-size: 1.05rem; border-radius: var(--radius-md); }

/* Tool Cards */
.tool-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: var(--gap-md); }
.tool-card { background: var(--bg-surface); border: 1px solid var(--border); border-radius: var(--radius-lg); padding: var(--gap-md); transition: all 0.25s; display: flex; flex-direction: column; }
.tool-card:hover { border-color: var(--accent); box-shadow: var(--shadow-card); transform: translateY(-2px); }
.tool-card .card-icon { font-size: 2rem; margin-bottom: var(--gap-sm); }
.tool-card h3 { margin-bottom: 4px; }
.tool-card .card-desc { color: var(--muted); font-size: 0.9rem; flex: 1; margin-bottom: var(--gap-sm); }
.tool-card .card-tag { display: inline-block; font-size: 0.75rem; padding: 2px 10px; border-radius: 20px; background: var(--accent-glow); color: var(--accent); font-weight: 600; align-self: flex-start; }
.tool-card.coming-soon { opacity: 0.55; pointer-events: none; }
.tool-card.coming-soon .card-tag { background: rgba(255,255,255,0.05); color: var(--muted); }

/* Features */
.feature-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: var(--gap-md); }
.feature-item { display: flex; gap: var(--gap-sm); padding: var(--gap-sm); }
.feature-item .feat-icon { font-size: 1.5rem; flex-shrink: 0; width: 40px; height: 40px; display: flex; align-items: center; justify-content: center; background: var(--bg-hover); border-radius: var(--radius-md); }
.feature-item h4 { margin-bottom: 4px; }
.feature-item p { color: var(--muted); font-size: 0.88rem; }

/* Screenshot */
.screenshot-box { background: var(--bg-surface); border: 1px solid var(--border); border-radius: var(--radius-lg); overflow: hidden; box-shadow: var(--shadow-card); }
.screenshot-box img { width: 100%; display: block; }
.screenshot-box .caption { padding: var(--gap-sm) var(--gap-md); font-size: 0.85rem; color: var(--muted); border-top: 1px solid var(--border); }

/* Download */
.download-card { background: var(--bg-surface); border: 1px solid var(--border); border-radius: var(--radius-lg); padding: var(--gap-lg); display: flex; align-items: center; justify-content: space-between; gap: var(--gap-md); flex-wrap: wrap; }
.download-info h3 { font-size: 1.2rem; }
.download-info .version { font-size: 0.88rem; color: var(--muted); font-family: var(--font-mono); }
.download-info .meta { font-size: 0.82rem; color: var(--muted); margin-top: 4px; }

/* Docs */
.doc-section { max-width: 780px; }
.doc-section h2 { margin: var(--gap-lg) 0 var(--gap-sm); padding-bottom: var(--gap-xs); border-bottom: 1px solid var(--border); }
.doc-section h3 { margin: var(--gap-md) 0 var(--gap-xs); }
.doc-section p, .doc-section li { color: var(--muted); margin-bottom: 8px; }
.doc-section ul { list-style: disc; padding-left: 24px; }
.doc-section code { font-family: var(--font-mono); font-size: 0.85em; background: var(--bg-hover); padding: 1px 6px; border-radius: 3px; color: var(--accent-strong); }
.doc-section kbd { font-family: var(--font-mono); font-size: 0.82em; background: var(--bg-hover); border: 1px solid var(--border); border-radius: 4px; padding: 1px 8px; color: var(--ink-strong); }

/* Footer */
.site-footer { border-top: 1px solid var(--border); padding: var(--gap-lg) 0; text-align: center; color: var(--muted); font-size: 0.85rem; margin-top: var(--gap-xl); }
.site-footer a { color: var(--muted); }
.site-footer a:hover { color: var(--ink); }
.footer-links { display: flex; justify-content: center; gap: var(--gap-md); margin-bottom: var(--gap-xs); }

/* Section head */
.section-head { text-align: center; margin-bottom: var(--gap-lg); }
.section-head h2 { margin-bottom: 8px; }
.section-head p { color: var(--muted); max-width: 560px; margin: 0 auto; }

/* Back link */
.back-link { display: inline-flex; align-items: center; gap: 4px; font-size: 0.9rem; color: var(--muted); margin-bottom: var(--gap-md); transition: color 0.2s; }
.back-link:hover { color: var(--ink-strong); }

/* Changelog table */
.changelog-table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
.changelog-table th, .changelog-table td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--border); }
.changelog-table th { color: var(--muted); font-weight: 600; font-size: 0.78rem; text-transform: uppercase; letter-spacing: 0.04em; }
.changelog-table td { color: var(--ink); }
.changelog-table .ver { font-family: var(--font-mono); color: var(--accent); }

/* Badges */
.badge { display: inline-block; font-size: 0.75rem; padding: 2px 10px; border-radius: 20px; font-weight: 600; }
.badge-free { background: rgba(78,201,160,0.15); color: var(--green); }
.badge-vip { background: rgba(232,168,80,0.15); color: var(--orange); }

/* Responsive */
@media (max-width: 768px) {
    h1 { font-size: 2rem; } h2 { font-size: 1.5rem; }
    .hero { padding: 60px 0 50px; } .hero h1 { font-size: 2.2rem; }
    .tool-grid { grid-template-columns: 1fr; }
    .feature-list { grid-template-columns: 1fr; }
    .download-card { flex-direction: column; align-items: flex-start; }
}
@media (max-width: 480px) {
    .nav-links { gap: var(--gap-sm); } .nav-links a { font-size: 0.8rem; }
    .hero h1 { font-size: 1.8rem; }
    .btn { padding: 10px 20px; font-size: 0.88rem; }
}
"""

write("assets/css/style.css", css)

# ============================================================
# Common template parts
# ============================================================
HEAD_COMMON = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">"""

FOOTER_COMMON = """<footer class="site-footer">
    <div class="container">
        <div class="footer-links">
            <a href="/">首页</a>
            <a href="/tools/DeepLaunch/">DeepLaunch</a>
            <a href="/tools/DeepLaunch/docs.html">文档</a>
            <a href="https://www.goodmem.cn" target="_blank" rel="noopener">goodmem.cn</a>
            <a href="/en/">English</a>
        </div>
        <p>&copy; 2026 DeepLaunch.top</p>
    </div>
</footer>
</body>
</html>"""

NAV_INDEX = """<header class="site-header">
    <nav class="nav-bar">
        <a href="/" class="nav-logo">
            <span class="logo-accent">2Key</span>Run
        </a>
        <div class="nav-links">
            <a href="/" class="active">首页</a>
            <a href="/tools/DeepLaunch/">DeepLaunch</a>
            <a href="/tools/DeepLaunch/docs.html">文档</a>
            <a href="/en/" class="nav-lang">EN</a>
        </div>
    </nav>
</header>"""

NAV_TOOL = """<header class="site-header">
    <nav class="nav-bar">
        <a href="/" class="nav-logo">
            <span class="logo-accent">2Key</span>Run
        </a>
        <div class="nav-links">
            <a href="/">首页</a>
            <a href="/tools/DeepLaunch/" class="active">DeepLaunch</a>
            <a href="/tools/DeepLaunch/docs.html">文档</a>
            <a href="/en/" class="nav-lang">EN</a>
        </div>
    </nav>
</header>"""

NAV_DOCS = """<header class="site-header">
    <nav class="nav-bar">
        <a href="/" class="nav-logo">
            <span class="logo-accent">2Key</span>Run
        </a>
        <div class="nav-links">
            <a href="/">首页</a>
            <a href="/tools/DeepLaunch/">DeepLaunch</a>
            <a href="/tools/DeepLaunch/docs.html" class="active">文档</a>
            <a href="/en/" class="nav-lang">EN</a>
        </div>
    </nav>
</header>"""

NAV_EN = """<header class="site-header">
    <nav class="nav-bar">
        <a href="/" class="nav-logo">
            <span class="logo-accent">2Key</span>Run
        </a>
        <div class="nav-links">
            <a href="/">Home</a>
            <a href="/tools/DeepLaunch/">DeepLaunch</a>
            <a href="/tools/DeepLaunch/docs.html">Docs</a>
            <a href="/en/" class="nav-lang active">EN</a>
        </div>
    </nav>
</header>"""

# ============================================================
# 1. index.html - Homepage
# ============================================================
index_html = (
    HEAD_COMMON
    + """
    <meta name="description" content="DeepLaunch �?Windows 效率工具集。按两下键启动任何程序。键盘启动器、剪贴板增强、聚合搜索�?>
    <title>DeepLaunch 工具�?| 按两下键，启动任何程�?/title>
    <link rel="stylesheet" href="assets/css/style.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><text y='28' font-size='28'>�?/text></svg>">
</head>
<body>
"""
    + NAV_INDEX
    + """
<section class="hero">
    <div class="container">
        <h1>按两下键�?span class="hl">启动任何程序</span></h1>
        <p class="subtitle">不翻菜单、不等搜索、不用鼠标�?br>肌肉记忆驱动�?Windows 效率工具集�?/p>
        <div class="hero-actions">
            <a href="/tools/DeepLaunch/" class="btn btn-primary btn-lg">�?了解 DeepLaunch</a>
            <a href="#tools" class="btn btn-outline btn-lg">查看全部工具</a>
        </div>
    </div>
</section>

<section class="section" id="tools">
    <div class="container">
        <div class="section-head">
            <h2>工具�?/h2>
            <p>每一个工具独立解决一个具体问题，不打折扣，不堆功能�?/p>
        </div>
        <div class="tool-grid">

            <a href="/tools/DeepLaunch/" class="tool-card">
                <div class="card-icon">�?/div>
                <h3>DeepLaunch 双键快启</h3>
                <p class="card-desc">240 格分层键盘网�?+ 聚合搜索 + 剪贴�?+ 30 套主题。装了就回不去的启动器�?/p>
                <span class="card-tag">v2.0 · 免费</span>
            </a>

            <div class="tool-card coming-soon">
                <div class="card-icon">🔧</div>
                <h3>工具�?/h3>
                <p class="card-desc">即将上线，敬请期待�?/p>
                <span class="card-tag">开发中</span>
            </div>

            <div class="tool-card coming-soon">
                <div class="card-icon">🔧</div>
                <h3>工具�?/h3>
                <p class="card-desc">即将上线，敬请期待�?/p>
                <span class="card-tag">开发中</span>
            </div>

            <div class="tool-card coming-soon">
                <div class="card-icon">🔧</div>
                <h3>工具�?/h3>
                <p class="card-desc">即将上线，敬请期待�?/p>
                <span class="card-tag">规划�?/span>
            </div>

            <div class="tool-card coming-soon">
                <div class="card-icon">🔧</div>
                <h3>工具�?/h3>
                <p class="card-desc">即将上线，敬请期待�?/p>
                <span class="card-tag">规划�?/span>
            </div>

            <div class="tool-card coming-soon">
                <div class="card-icon">🔧</div>
                <h3>工具�?/h3>
                <p class="card-desc">即将上线，敬请期待�?/p>
                <span class="card-tag">规划�?/span>
            </div>

        </div>
    </div>
</section>
"""
    + FOOTER_COMMON
)

write("index.html", index_html)

# ============================================================
# 2. tools/DeepLaunch/index.html - Product page
# ============================================================
tool_html = (
    HEAD_COMMON
    + """
    <meta name="description" content="DeepLaunch 双键快启 �?按两下键启动任何程序�?40 格分层网�?+ 聚合搜索 + 剪贴�?+ 30 套主题。肌肉记忆驱动的 Windows 键盘启动器�?>
    <title>DeepLaunch 双键快启 | 按两下键，启动任何程�?/title>
    <link rel="stylesheet" href="/assets/css/style.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><text y='28' font-size='28'>�?/text></svg>">
</head>
<body>
"""
    + NAV_TOOL
    + """
<section class="hero">
    <div class="container">
        <h1><span class="hl">DeepLaunch</span> 双键快启</h1>
        <p class="subtitle">按两下键，启动任何程序�?br>不翻菜单、不等搜索、不用鼠标。装了就回不去�?/p>
        <div class="hero-actions">
            <a href="#download" class="btn btn-primary btn-lg">�?免费下载</a>
            <a href="docs.html" class="btn btn-outline btn-lg">📖 使用文档</a>
        </div>
    </div>
</section>

<section class="section">
    <div class="container">
        <div class="screenshot-box">
            <img src="/assets/images/DeepLaunch/main-screenshot.png" alt="DeepLaunch 主界�?�?左侧程序导航�?+ 右侧 60 格快速启动网�?+ 底部控制面板" onerror="this.style.display='none'">
            <div class="caption">DeepLaunch 主界�?�?左侧程序导航�?+ 右侧 60 格键盘映射网�?+ 底部控制面板。深色主题，科技蓝强调色�?/div>
        </div>
    </div>
</section>

<section class="section">
    <div class="container">
        <div class="section-head">
            <h2>它不是又一个搜索框</h2>
            <p>其他启动器让你打字搜索�?KeyRun 让你用肌肉记忆——和按电视遥控器一样简单�?/p>
        </div>
        <div class="feature-list">

            <div class="feature-item">
                <div class="feat-icon">🚀</div>
                <div>
                    <h4>分层网格快启 �?核心中的核心</h4>
                    <p>4 �?× 60 �?= <strong>240 个快捷槽�?/strong>。键盘布局直接映射到屏幕：QWERTY 行就是第三行格子。开�?strong>单键模式</strong>后，按一个字母键直接启动——不需�?Ctrl+Q，就是一个键。把 exe 拖到格子上即完成绑定�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">🔍</div>
                <div>
                    <h4>聚合搜索 �?没绑定的也能秒找</h4>
                    <p>一个搜索框同时查三源：已绑定动�?+ 系统已安装程�?+ Everything 全盘文件。支�?strong>拼音首字母、全拼、中文、英�?/strong>。输�?<code>wx</code> �?微信�?code>chrome</code> �?浏览器�? 个字母触发搜索，不等回车�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">🌲</div>
                <div>
                    <h4>程序导航�?�?你的软件自动整理好了</h4>
                    <p>首次打开即自动扫描所有已安装程序，按 <strong>13 个大�?/strong>自动分类。最近使用、常用文件、常用目录各自独立标签页。内嵌文件浏览器，点文件就能打开�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">⌨️</div>
                <div>
                    <h4>全局热键 �?手不离开键盘</h4>
                    <p>F1 一键唤出，再按隐藏。任何界面、任何软件、任何状态下都能呼出。系统托盘常驻，不占任务栏空间。搜索框获焦<strong>自动切英文输入法</strong>——这个细节每天帮你省无数次切换�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">📋</div>
                <div>
                    <h4>剪贴板增�?�?低调但救�?/h4>
                    <p>后台自动记录剪贴板历史，复制过的东西不会丢。中途覆盖了 A 内容？点历史列表就能找回。支持文本、链接等常用格式�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">🎨</div>
                <div>
                    <h4>30 套主�?�?看着舒服才能用得�?/h4>
                    <p>深色 15 �?+ 浅色 15 套。设置中<strong>实时预览、一键切�?/strong>，无需重启。默认暗蓝黑 + 科技蓝强调色，和 Windows 暗色模式完美搭配�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">🖱�?/div>
                <div>
                    <h4>拖放操作 �?不是功能，是直觉</h4>
                    <p>�?exe 到空格子 �?绑定。拖 A 格到 B �?�?互换。拖格子到常用文件树 �?收藏。全部操作遵�?Windows 用户的本能�?/p>
                </div>
            </div>

            <div class="feature-item">
                <div class="feat-icon">💡</div>
                <div>
                    <h4>配置分享 �?肌肉记忆应该可以带走</h4>
                    <p>一键导出全�?Grid 布局为文件。换电脑、重装系统、帮同事配置——导入文件，秒级复现整个工作环境。所有数据存本地 SQLite，不依赖网络�?/p>
                </div>
            </div>

        </div>
    </div>
</section>

<section class="section">
    <div class="container">
        <div class="section-head">
            <h2>为什么不是又一�?PowerToys Run / Wox / uTools�?/h2>
            <p>那些是「搜索框」逻辑——先想名字、再打字、再看结果、再点�?KeyRun 是「遥控器」逻辑�?/p>
        </div>
        <div class="download-card" style="justify-content:center;text-align:center;flex-direction:column;">
            <p style="max-width:600px;color:var(--muted);line-height:1.8;">
                你知�?<strong>Q</strong> 是微信，�?<strong>Q</strong> 就是微信�?br>
                你知�?<strong>W</strong> 是浏览器，按 <strong>W</strong> 就是浏览器�?br>
                <strong>不需要搜索、不需要选择、不需要确认�?/strong><br>
                眼睛看一次，手指记住一辈子�?
            </p>
        </div>
    </div>
</section>

<section class="section">
    <div class="container">
        <div class="section-head">
            <h2>版本与授�?/h2>
            <p>基础功能永久免费。高级功能按需解锁�?/p>
        </div>
        <div class="download-card" style="justify-content:center;text-align:center;flex-direction:column;">
            <div>
                <p style="margin-bottom:12px;">
                    <span class="badge badge-free">免费�?/span>
                    &nbsp; 网格快启�?40 格）+ 聚合搜索�? 源）+ 程序导航�?+ 全局热键 + 剪贴板增�?+ 30 套主�?+ 拖放绑定 + 配置分享
                </p>
                <p>
                    <span class="badge badge-vip">VIP �?/span>
                    &nbsp; 高级功能解锁
                </p>
                <p style="margin-top:16px;color:var(--muted);font-size:0.88rem;">
                    VIP 购买请前往
                    <a href="https://www.goodmem.cn" target="_blank" rel="noopener">goodmem.cn �?/a>
                </p>
            </div>
        </div>
    </div>
</section>

<section class="section" id="download">
    <div class="container">
        <div class="section-head">
            <h2>下载</h2>
            <p>适用�?Windows 10 / 11�?4 位）</p>
        </div>
        <div class="download-card">
            <div class="download-info">
                <h3>DeepLaunch v2.0</h3>
                <p class="version">TwoKeyRun.exe</p>
                <p class="meta">最新构�?· Windows 10/11 x64 · 便携版，解压即用</p>
            </div>
            <a href="#" class="btn btn-primary btn-lg">�?前往 GitHub Releases 下载</a>
        </div>
        <div style="margin-top:var(--gap-md);">
            <h3 style="margin-bottom:var(--gap-sm);">更新日志</h3>
            <table class="changelog-table">
                <thead>
                    <tr><th>日期</th><th>版本</th><th>变更</th></tr>
                </thead>
                <tbody>
                    <tr><td>2026-05-01</td><td class="ver">v2.0</td><td>主链功能稳定：搜�?Grid/热键/托盘/收藏�?8 项行为测试通过</td></tr>
                    <tr><td>2026-04-29</td><td class="ver">v2.0-rc</td><td>搜索管线线程安全加固；退出生命周期硬化；UI 类注册修�?/td></tr>
                    <tr><td>2026-04-19</td><td class="ver">v2.0-beta</td><td>Grid 拖放重构；F1/F3 热键行为优化；搜索结果显示修�?/td></tr>
                </tbody>
            </table>
        </div>
    </div>
</section>
"""
    + FOOTER_COMMON
)

write("tools/DeepLaunch/index.html", tool_html)

# ============================================================
# 3. tools/DeepLaunch/docs.html - Documentation
# ============================================================
docs_html = (
    HEAD_COMMON
    + """
    <meta name="description" content="DeepLaunch 使用文档 �?热键说明、Grid 操作指南、搜索技巧�?>
    <title>DeepLaunch 使用文档</title>
    <link rel="stylesheet" href="/assets/css/style.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><text y='28' font-size='28'>�?/text></svg>">
</head>
<body>
"""
    + NAV_DOCS
    + """
<section class="section">
    <div class="container">
        <a href="/tools/DeepLaunch/" class="back-link">�?返回 DeepLaunch</a>
        <h1>使用文档</h1>
        <p style="color:var(--muted);margin-bottom:var(--gap-lg);">快速上�?DeepLaunch，掌握所有快捷键和操作技巧�?/p>

        <div class="doc-section">

            <h2>快速上�?/h2>

            <h3>第一步：启动</h3>
            <p>下载并解压后，运�?<code>TwoKeyRun.exe</code>。程序会自动缩小到系统托盘，不占用任务栏空间�?/p>

            <h3>第二步：唤出主界�?/h3>
            <p>按下 <kbd>F1</kbd> �?<kbd>F3</kbd> 键唤�?DeepLaunch 主窗口。再按一次则隐藏�?/p>

            <h3>第三步：绑定你的第一个程�?/h3>
            <p>将任�?<code>.exe</code> 文件或快捷方式从文件管理器拖到网格中的任意空格，即完成绑定。之后在单键模式下按对应字母键即可启动�?/p>

            <h3>第四步：搜索一�?/h3>
            <p>点击「搜索面板」标签，在搜索框中输入程序名称（中文、拼音首字母或英文均可），从结果列表中点击或回车启动�?/p>

            <h2>热键说明</h2>
            <table class="changelog-table">
                <thead>
                    <tr><th>热键</th><th>功能</th><th>说明</th></tr>
                </thead>
                <tbody>
                    <tr><td><kbd>F1</kbd> / <kbd>F3</kbd></td><td>唤出 / 隐藏主窗�?/td><td>窗口在前台时隐藏，在后台时显示并提到最�?/td></tr>
                    <tr><td><kbd>A</kbd> ~ <kbd>Z</kbd> / <kbd>0</kbd> ~ <kbd>9</kbd></td><td>单键启动</td><td>需开启「单键模式」。按对应字母/数字键启动该格位绑定的程�?/td></tr>
                    <tr><td><kbd>Ctrl</kbd> + 字母�?/td><td>Ctrl 层启�?/td><td>切换�?Ctrl 修饰层后，按键启动该层对应程�?/td></tr>
                    <tr><td><kbd>Alt</kbd> + 字母�?/td><td>Alt 层启�?/td><td>切换�?Alt 修饰层后，按键启动该层对应程�?/td></tr>
                    <tr><td><kbd>Shift</kbd> + 字母�?/td><td>Shift 层启�?/td><td>切换�?Shift 修饰层后，按键启动该层对应程�?/td></tr>
                    <tr><td><kbd>�?/kbd> <kbd>�?/kbd> <kbd>�?/kbd> <kbd>�?/kbd></td><td>网格导航</td><td>在网格中用方向键移动选中�?/td></tr>
                    <tr><td><kbd>Enter</kbd></td><td>启动当前选中程序</td><td>在网格中按下 Enter 启动当前选中格的程序</td></tr>
                    <tr><td><kbd>Apps</kbd> / 右键</td><td>右键菜单</td><td>在网格格子上弹出菜单：执�?/ 编辑 / 清空 / 查看属�?/td></tr>
                </tbody>
            </table>

            <h2>Grid 网格操作指南</h2>

            <h3>网格布局</h3>
            <p>主界面右侧的网格区域�?<strong>10 �?× 6 �?= 60 �?/strong>。每个格子可以绑定一个程序，显示其图标和名称�?/p>
            <p>通过底部控制面板的「Grid 层级」可以在 4 层之间切换：</p>
            <ul>
                <li><strong>无修饰层</strong>（none）：默认层，直接按键启动</li>
                <li><strong>Shift �?/strong>：Shift + 按键启动</li>
                <li><strong>Ctrl �?/strong>：Ctrl + 按键启动</li>
                <li><strong>Alt �?/strong>：Alt + 按键启动</li>
            </ul>
            <p>总计 <strong>4 × 60 = 240 个快捷槽�?/strong>�?/p>

            <h3>单键模式</h3>
            <p>在底部控制面板勾选「单键模式」后，无需按任何修饰键，直接按字母或数字键即可启动对应格位的程序�?/p>
            <p>关闭单键模式后，按键输入会进入搜索框，不会触发程序启动，避免误操作�?/p>

            <h3>拖放操作</h3>
            <ul>
                <li><strong>从文件管理器拖入</strong>：将 exe / lnk / bat / cmd / ps1 / url 文件拖到空格子上，自动绑�?/li>
                <li><strong>格子间互�?/strong>：拖动一个格子到另一个格子上，交换两个格子的内容</li>
                <li><strong>拖到左侧�?/strong>：将格子拖到左侧「常用文件」树节点，加入收�?/li>
                <li><strong>右键编辑</strong>：右键格�?�?编辑，手动设置程序路径、名称、启动参�?/li>
            </ul>

            <h3>双击�?Enter</h3>
            <p>在网格中<strong>双击</strong>格子或选中格子后按 <kbd>Enter</kbd>，立即启动该程序。单击仅选中，不启动�?/p>

            <h2>搜索技�?/h2>

            <h3>搜索�?/h3>
            <p>DeepLaunch 的搜索框同时从以下来源检索：</p>
            <ul>
                <li><strong>已绑定的快捷动作</strong>：你�?Grid 中绑定的所有程�?/li>
                <li><strong>系统已安装程�?/strong>：自动扫描开始菜单和桌面建立的程序索�?/li>
                <li><strong>Everything 全盘文件</strong>：需安装 <a href="https://www.voidtools.com/" target="_blank" rel="noopener">Everything</a>，开启后在设置中启用</li>
            </ul>

            <h3>匹配规则</h3>
            <ul>
                <li><strong>拼音首字�?/strong>：输�?<code>wx</code> 可匹配「微信�?/li>
                <li><strong>全拼</strong>：输�?<code>weixin</code> 也可匹配</li>
                <li><strong>中文</strong>：直接输入「微信�?/li>
                <li><strong>英文</strong>：输�?<code>chrome</code> 匹配 Chrome 浏览�?/li>
                <li><strong>全字匹配</strong>：多字符查询只匹配连续子串，不会拆分到不连续位置</li>
            </ul>

            <h3>触发条件</h3>
            <p>输入 <strong>2 个拉丁字�?/strong>�?<strong>1 个中文字�?/strong>后自动开始搜索。空输入框时显示最近使用记录（MRU）�?/p>

            <h2>剪贴板增�?/h2>
            <p>在设置中开启「启用剪贴板伴生进程」后�?KeyRun 会在后台监听剪贴板变化：</p>
            <ul>
                <li>自动记录每次复制的内容到历史列表</li>
                <li>在「剪贴板」标签页中查看历史记�?/li>
                <li>点击任意一条即可粘贴到当前应用</li>
            </ul>

            <h2>主题切换</h2>
            <p>点击底部「设置」按钮，进入「外观」标签页�?/p>
            <ul>
                <li>浅色系和深色系各 15 套主�?/li>
                <li>点击主题名称即时预览，无需重启</li>
                <li>推荐默认深色主题以匹配系统暗色模�?/li>
            </ul>

            <h2>设置说明</h2>
            <table class="changelog-table">
                <thead>
                    <tr><th>设置�?/th><th>说明</th></tr>
                </thead>
                <tbody>
                    <tr><td>唤醒热键</td><td>默认�?F1，可在设置中自定�?/td></tr>
                    <tr><td>自动切英文输入法</td><td>搜索框获焦时自动切换为英文，建议保持开�?/td></tr>
                    <tr><td>运行模式</td><td>唤醒（默认）/ 重复上一�?/ 新建实例</td></tr>
                    <tr><td>Everything 集成</td><td>需安装 Everything 并保持运行，开启后搜索结果会包含全盘文�?/td></tr>
                    <tr><td>高级视觉效果</td><td>开启圆角等高级渲染效果，低配电脑可关闭</td></tr>
                    <tr><td>分享配置</td><td>导出当前 Grid 布局和设置为文件，分享或迁移</td></tr>
                </tbody>
            </table>

            <h2>常见问题</h2>

            <h3>Q: 程序启动后找不到窗口�?/h3>
            <p>A: DeepLaunch 默认最小化到系统托盘（右下角图标区）。按 <kbd>F1</kbd> 或双击托盘图标即可唤出�?/p>

            <h3>Q: 输入中文时总是变成英文�?/h3>
            <p>A: 这是「自动切英文输入法」功能，防止搜索时误输入中文。可在设置中关闭此功能�?/p>

            <h3>Q: 搜索不到某个已安装的程序�?/h3>
            <p>A: 在设置中点击「重建程序索引」，系统会重新扫描开始菜单和桌面。完成后即可搜索到新安装的程序�?/p>

            <h3>Q: 如何完全退出程序？</h3>
            <p>A: 右键系统托盘图标 �?退出，或在主窗口底部点击「退出」按钮�?/p>

            <h3>Q: 配置文件在哪里？</h3>
            <p>A: 所有配置和 Grid 数据存储在程序目录下�?<code>data\\</code> 文件夹中（SQLite 数据库）。备份该文件夹即可迁移全部配置�?/p>

        </div>
    </div>
</section>
"""
    + FOOTER_COMMON
)

write("tools/DeepLaunch/docs.html", docs_html)

# ============================================================
# 4. en/index.html - English placeholder
# ============================================================
en_html = (
    HEAD_COMMON.replace("zh-CN", "en")
    + """
    <meta name="description" content="DeepLaunch �?Windows efficiency toolset. Two keystrokes to launch anything.">
    <title>DeepLaunch �?Toolset | Two Keys to Everything</title>
    <link rel="stylesheet" href="/assets/css/style.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'><text y='28' font-size='28'>�?/text></svg>">
</head>
<body>
"""
    + NAV_EN
    + """
<section class="hero">
    <div class="container">
        <h1><span class="hl">2Key</span>Run Toolset</h1>
        <p class="subtitle">A Windows efficiency toolbox.<br>Keyboard-driven, minimal interaction, no menus, no waiting.</p>
        <div class="hero-actions">
            <a href="/tools/DeepLaunch/" class="btn btn-primary btn-lg">�?Explore DeepLaunch</a>
        </div>
    </div>
</section>
<section class="section">
    <div class="container" style="text-align:center;">
        <p style="color:var(--muted);">English version is under construction.<br>Please visit the <a href="/">Chinese site</a> for full content.</p>
    </div>
</section>
<footer class="site-footer">
    <div class="container">
        <div class="footer-links">
            <a href="/">Home</a>
            <a href="/tools/DeepLaunch/">DeepLaunch</a>
            <a href="/en/">English</a>
        </div>
        <p>&copy; 2026 DeepLaunch.top</p>
    </div>
</footer>
</body>
</html>"""
)

write("en/index.html", en_html)

print("\n�?All files generated successfully!")
