#!/usr/bin/env python3
"""
DeepFlow UTF-8 Corruption Fix Script
检测并自动修复常见的 UTF-8 损坏模式
"""
import sys
import os

# 常见损坏模式映射
CORRECTION_MAP = {
    # '?' character represents corrupted third byte of UTF-8 char
    # Pattern: "执?" -> "执行", "状?" -> "状态", etc.
}

def find_corrupted_chars(file_path):
    """Find all corrupted UTF-8 sequences in a file"""
    issues = []
    
    try:
        with open(file_path, 'rb') as f:
            content = f.read()
            
        # Look for the specific corruption pattern (0x3f which is '?')
        # in positions where Chinese characters should be
        
        # Decode with replacement
        text = content.decode('utf-8', errors='replace')
        
        # Find replacement characters
        import re
        matches = list(re.finditer(r'\ufffd', text))
        
        for match in matches:
            line_num = text[:match.start()].count('\n') + 1
            context_start = max(0, match.start() - 20)
            context_end = min(len(text), match.end() + 20)
            context = text[context_start:context_end]
            
            issues.append({
                'line': line_num,
                'position': match.start(),
                'context': context.strip()
            })
            
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        
    return issues

def main():
    if len(sys.argv) < 2:
        print("Usage: python utf8-fix-analyzer.py <file_or_directory>")
        sys.exit(1)
        
    path = sys.argv[1]
    
    if os.path.isfile(path):
        issues = find_corrupted_chars(path)
        print(f"File: {path}")
        print(f"Found {len(issues)} corruption instances:")
        for issue in issues:
            print(f"  Line {issue['line']}: {issue['context']}")
    elif os.path.isdir(path):
        count = 0
        for root, dirs, files in os.walk(path):
            for file in files:
                if file.endswith('.pas'):
                    full_path = os.path.join(root, file)
                    issues = find_corrupted_chars(full_path)
                    if issues:
                        print(f"\n{'='*60}")
                        print(f"File: {full_path}")
                        print(f"{'='*60}")
                        for issue in issues:
                            print(f"  Line {issue['line']}: (UTF-8 corruption detected in context)")
                        count += 1
                        
        print(f"\n{'='*60}")
        print(f"Total files with issues: {count}")

if __name__ == '__main__':
    main()
