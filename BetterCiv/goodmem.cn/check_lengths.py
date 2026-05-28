import os
import yaml
import re

articles_dir = r"D:\_Progs\.DeepStory\《思维越狱》\LMM508定稿库\articles"
max_lens = {
    'title': 0,
    'subtitle': 0,
    'judgment_tag': 0,
    'keywords': 0,
    'rfi_type': 0,
    'external_code': 0,
    'drug_type': 0,
    'sub_category': 0 # also known as drug_layer
}

files = [f for f in os.listdir(articles_dir) if f.endswith('.md')]

for filename in files:
    with open(os.path.join(articles_dir, filename), 'r', encoding='utf-8') as f:
        content = f.read()
        match = re.match(r'^---\s*\n(.*?)\n---\s*\n', content, re.DOTALL)
        if match:
            fm = yaml.safe_load(match.group(1))
            for k in max_lens:
                val = fm.get(k, "")
                if isinstance(val, list):
                    val = ",".join(str(i) for i in val)
                if val:
                    l = len(str(val))
                    if l > max_lens[k]:
                        max_lens[k] = l
                        if l > 50 and k == 'judgment_tag':
                           print(f"Long judgment_tag in {filename}: {l} chars - {val}")
                        if l > 255 and k == 'subtitle':
                           print(f"Long subtitle in {filename}: {l} chars")

print("\nMaximum lengths found:")
for k, v in max_lens.items():
    print(f"  {k}: {v}")
