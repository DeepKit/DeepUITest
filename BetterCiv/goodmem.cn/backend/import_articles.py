import os
import asyncio
import asyncpg
import markdown
import re
import yaml
from dotenv import load_dotenv

# ================= 配置�?=================
load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL")
ARTICLES_DIR = os.getenv("ARTICLES_DIR", "articles")
TARGET_NOVEL_KEY = "mindbreak"  # 本次灌注所属的隔离书库标识

async def import_articles():
    if not DATABASE_URL:
        print("[!] DATABASE_URL 未设置。请�?export DATABASE_URL 或配�?.env�?)
        return

    print(f"[*] 准备连接数据�? {DATABASE_URL}")
    try:
        conn = await asyncpg.connect(DATABASE_URL)
    except Exception as e:
        print(f"[!] 数据库连接失�? {e}")
        return

    print(f"[*] 读取目录: {ARTICLES_DIR}")
    if not os.path.exists(ARTICLES_DIR):
        print("[!] 设定�?Markdown 目录不存在，请修改配置�?)
        return

    # 清空旧文章数据以保证 508 篇为最�?    print("[*] 清空旧文章数�?(TRUNCATE)...")
    await conn.execute("TRUNCATE articles RESTART IDENTITY CASCADE")

    md_files = [f for f in os.listdir(ARTICLES_DIR) if f.endswith('.md')]
    md_files.sort()

    print(f"[*] 找到 {len(md_files)} 篇文档，准备灌注至小说库: [{TARGET_NOVEL_KEY}] ...")

    found_count = 0
    fail_count = 0

    for filename in md_files:
        filepath = os.path.join(ARTICLES_DIR, filename)
        with open(filepath, 'r', encoding='utf-8') as f:
            raw_text = f.read()

        # 1. 提取 YAML frontmatter 和正�?        match = re.match(r'^---\s*\n(.*?)\n---\s*\n(.*)', raw_text, re.DOTALL)
        if match:
            yaml_str = match.group(1)
            content_md = match.group(2)
            try:
                frontmatter = yaml.safe_load(yaml_str)
            except Exception as e:
                print(f"  [!] {filename}: YAML 解析失败: {e}")
                fail_count += 1
                continue
        else:
            # 如果没有 YAML，抛出警告但兼容性保留原逻辑
            print(f"  [!] {filename}: 未找�?YAML frontmatter，这已经不符合统一格式协议�?)
            frontmatter = {}
            content_clean = re.sub(r'^---.*?---\n', '', raw_text, flags=re.DOTALL)
            content_md = content_clean

        # 2. 转换为基础 HTML
        html_output = markdown.markdown(content_md, extensions=['tables', 'fenced_code'])

        # 3. 提取核心字段
        title = frontmatter.get('title')
        if not title:
            # 兼容：如果没配置，提取文件名
            title = filename.replace('.md', '')

        is_free = False 
        if "free" in filename.lower() or "试读" in title:
            is_free = True

        rfi_type = frontmatter.get('rfi_type')
        if not rfi_type:
            # 兼容老逻辑
            if re.search(r'边界|滑|模糊|接锅|主责|�?, title):
                rfi_type = 'water'
            elif re.search(r'补位|蔓|帮忙|默认|长成', title):
                rfi_type = 'wood'
            elif re.search(r'引爆|火线|事故|点名|突然', title):
                rfi_type = 'fire'
            elif re.search(r'沉积|旧账|沉没|缓冲|堆积', title):
                rfi_type = 'earth'
            elif re.search(r'割裂|权责|拍板|判断权|背责', title):
                rfi_type = 'metal'

        # �?YAML 读取 RFI-5 体系的新字段
        external_code = frontmatter.get('external_code')
        subtitle = frontmatter.get('subtitle')
        drug_type = frontmatter.get('drug_type')
        drug_layer = frontmatter.get('sub_category')
        judgment_tag = frontmatter.get('judgment_tag')
        raw_keywords = frontmatter.get('keywords')
        keywords = ""
        if isinstance(raw_keywords, list):
            keywords = ",".join(str(k) for k in raw_keywords)
        elif isinstance(raw_keywords, str):
            keywords = raw_keywords

        status = frontmatter.get('status', 'ready')
        legacy_id = frontmatter.get('legacy_id')

        # 如果没有指定 external_code，则尝试从文件名提取 (格式：ASTO.S0110.题名.md)
        if not external_code:
            fn_match = re.match(r'^ASTO\.([A-Z]?\d{4})\.', filename)
            if fn_match:
                external_code = fn_match.group(1)

        # 动态推�?cluster_id, position_type, variant
        cluster_id = None
        position_type = 1
        variant = 0
        if external_code and len(external_code) >= 4:
            # 千位�?3081 -> cluster=30, pos=8, var=1
            cluster_id = external_code[-4:-2]
            try:
                position_type = int(external_code[-2])
                variant = int(external_code[-1])
            except:
                pass

        # 4. 入库
        try:
            await conn.execute("""
                INSERT INTO articles (
                    novel_key, title, content_html, is_free, rfi_type,
                    external_code, subtitle, cluster_id, drug_type, drug_layer,
                    judgment_tag, keywords, status, legacy_id, position_type, variant
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
                ON CONFLICT (novel_key, title) DO UPDATE SET 
                    content_html = EXCLUDED.content_html, 
                    is_free = EXCLUDED.is_free, 
                    rfi_type = EXCLUDED.rfi_type,
                    external_code = EXCLUDED.external_code,
                    subtitle = EXCLUDED.subtitle,
                    cluster_id = EXCLUDED.cluster_id,
                    drug_type = EXCLUDED.drug_type,
                    drug_layer = EXCLUDED.drug_layer,
                    judgment_tag = EXCLUDED.judgment_tag,
                    keywords = EXCLUDED.keywords,
                    status = EXCLUDED.status,
                    legacy_id = EXCLUDED.legacy_id,
                    position_type = EXCLUDED.position_type,
                    variant = EXCLUDED.variant
            """, TARGET_NOVEL_KEY, title, html_output, is_free, rfi_type,
                 external_code, subtitle, cluster_id, drug_type, drug_layer,
                 judgment_tag, keywords, status, legacy_id, position_type, variant)
            print(f"  [+] 已入�?更新: {title} (编号: {external_code or '�?})")
            found_count += 1
        except Exception as e:
            print(f"  [!] 失败: {title} | Error: {e}")
            print(f"      Data: code={external_code}, subtitle={subtitle}, layer={drug_layer}, tags={judgment_tag}")
            fail_count += 1

    await conn.close()
    print(f"[*] 数据库封存就绪。成�? {found_count}, 失败: {fail_count}。文章注入完成！")

if __name__ == "__main__":
    asyncio.run(import_articles())
