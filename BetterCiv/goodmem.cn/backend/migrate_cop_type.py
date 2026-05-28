"""
迁移脚本: 为已存在�?articles 表添�?cop_type 字段，并统一 UNIQUE 约束
运行方式: �?backend 目录�?python migrate_cop_type.py
"""
import asyncio
import asyncpg
import os
from dotenv import load_dotenv

load_dotenv()
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:a29806588-run@localhost:5432/DeepStory")

async def migrate_db():
    conn = await asyncpg.connect(DATABASE_URL)
    try:
        print("[*] 开始迁�?..")

        # 1. articles 表加 cop_type �?        await conn.execute("ALTER TABLE articles ADD COLUMN IF NOT EXISTS cop_type VARCHAR(4)")
        print("[+] articles.cop_type 字段添加完毕")

        # 2. articles 表加 UNIQUE 约束（防重复入库�?        try:
            await conn.execute("ALTER TABLE articles ADD CONSTRAINT uq_articles_novel_title UNIQUE (novel_key, title)")
            print("[+] UNIQUE(novel_key, title) 约束添加完毕")
        except asyncpg.exceptions.DuplicateTableError:
            print("[-] UNIQUE 约束已存在，跳过")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("[-] UNIQUE 约束已存在，跳过")
            else:
                print(f"[!] UNIQUE 约束添加失败: {e}")

        # 3. �?granted_novels TEXT 升级�?JSONB（需要先转换�?        #    如果类型已经�?JSONB 则跳�?        col_type = await conn.fetchval(
            "SELECT data_type FROM information_schema.columns "
            "WHERE table_name='users' AND column_name='granted_novels'"
        )
        if col_type and col_type.lower() != 'jsonb':
            await conn.execute(
                "ALTER TABLE users ALTER COLUMN granted_novels TYPE JSONB USING granted_novels::jsonb"
            )
            print("[+] granted_novels 已从 TEXT 升级�?JSONB")
        else:
            print("[-] granted_novels 已是 JSONB，跳�?)

        print("\n�?迁移完成�?)
    except Exception as e:
        print(f"�?迁移失败: {e}")
    finally:
        await conn.close()

if __name__ == '__main__':
    asyncio.run(migrate_db())
