# Fix Delphi Project Encoding

When the user reports garbled text (乱码) in Delphi source files (.pas, .dpr, .dfm, .fmx, .inc), use DeepCharset to batch-convert them to UTF-8 with BOM.

## Tool Location

```
DeepCharset\DeepCharset.exe
```

## Standard Command

```powershell
& 'DeepCharset\DeepCharset.exe' -s auto -t UTF-8 --add-bom -r -b '<ProjectDir>'
```

- `-s auto` — auto-detect source encoding (handles GBK, Big5, Shift-JIS, etc.)
- `-t UTF-8` — target encoding
- `--add-bom` — Delphi 13+ requires UTF-8 BOM for correct parsing
- `-r` — recursive (process all files in subdirectories)
- `-b` — create .bak backup of each file before conversion

## Expected Output

```
找到 N 个文件
转换完成:
  成功: M
  失败: K
```

## Known Safe Failures

These are NOT bugs — ignore them:
- `.db` / `.db-wal` / `.db-shm` files: locked by running process (error code 32)
- Empty XML files: tool refuses to write empty output (data safety)
- Binary files (.exe, .dll, .res): tool auto-skips or reports harmless failure

## Post-Conversion Verification

1. Rebuild the project with dcc64/msbuild — Chinese comments should display correctly
2. If satisfied, delete .bak files:
   ```powershell
   Get-ChildItem -Path '<ProjectDir>' -Filter '*.bak' -Recurse | Remove-Item -Force
   ```

## When to Use

- After cloning a project that was developed on a Chinese Windows system (GBK default)
- After Delphi version upgrade (D12 → D13) where IDE now expects UTF-8 BOM
- When IDE or compiler output shows `??` or mojibake in string literals and comments
- When `readFile` in Kiro shows garbled Chinese characters in .pas/.dfm files

## Notes

- Delphi 13 (Florence) requires UTF-8 with BOM for source files containing non-ASCII
- DFM/FMX files with string properties containing Chinese MUST be UTF-8 BOM or the IDE will corrupt them on save
- Always backup before batch conversion — encoding detection is heuristic
