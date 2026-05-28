with open('import_out_v2.txt', 'r', encoding='utf-16le', errors='ignore') as f:
    lines = f.readlines()
    for line in lines[:50]:
        print(line.strip())
