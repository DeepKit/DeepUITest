# Changelog

All notable changes to DeepDevLite will be documented in this file.

---

## [Unreleased]

### 🔧 Changed
- Migrated to Delphi 13.1 (from 12.3)
- dproj upgraded to ProjectVersion 20.4, ProjectFileVersion 13
- Search Path fixed: from invalid `..\DeepBase\Source` to `..\DeepBase\TestResults\dcu32;dcp32;Core;FMX;Persistence;Features`

### ✨ Modernized
- Applied ternary operator + inline var refactoring to HelperJson.pas

### 🧪 Build
- Win32 Clean + Build: 18,406 lines / 1.70s → `bin\DeepDevLite.exe` (40 MB)
