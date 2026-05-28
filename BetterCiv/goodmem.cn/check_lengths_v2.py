import os
import yaml
import re

articles_dir = r"D:\_Progs\.DeepStory\《思维越狱》\LMM508定稿库\articles"

files = [f for f in os.listdir(articles_dir) if f.endswith('.md')]

for filename in files:
    with open(os.path.join(articles_dir, filename), 'r', encoding='utf-8') as f:
        content = f.read()
        match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
        if match:
            fm = yaml.safe_load(match.group(1))
            for k, limit in [('judgment_tag', 255), ('subtitle', 512), ('rfi_type', 10), ('external_code', 20), ('title', 512)]:
                val = fm.get(k, "")
                if val and len(str(val)) > limit:
                    print(f"!!! {filename} has long {k}: {len(str(val))} chars: {val}")

            # Check keywords separately
            kw = fm.get('keywords', [])
            if isinstance(kw, list):
                kw_str = ",".join(str(i) for i in kw)
                # keywords is TEXT now, so no limit really, but let's see
                if len(kw_str) > 1000:
                   print(f"!!! {filename} has long keywords: {len(kw_str)} chars")
