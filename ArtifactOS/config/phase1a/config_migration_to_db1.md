# Config Migration Plan: config/phase1a/* → DB1 (DeepBase)

> P1 #14 — ArtifactOS configuration convergence to DB1 ConfigDB

## Source files (kept as human-readable records)

| File | After migration | Reason |
|------|----------------|--------|
| `sourcepack_inventory_candidate.md` | **Keep as reference doc** | Needs human review; not machine config |
| `sourcepack_import_summary.md` | **Keep as reference doc** | Audit trail of import operation |
| `legacy_media_publish_discovery.md` | **Keep as reference doc** | Audit trail of environment discovery |
| `shadow_run_7d_checklist.md` | **Keep as reference doc** | Acceptance criteria; not machine config |
| `day0_dry_run_report.md` | **Keep as reference doc** | Run-time audit; not config |
| `db_state_20260527.md` | **Keep as reference doc** | Snapshot; not config |

## Machine config → DB1 (DeepBase.SetConfig)

| YAML path | DB1 key | Example value |
|-----------|---------|---------------|
| `first_operational_surface.source_pack_name` | `ArtifactOS.SourcePack.Name` | `一元论` |
| `first_operational_surface.source_root` | `ArtifactOS.SourcePack.Root` | `D:\_Progs\一元论` |
| `first_operational_surface.platform` | `ArtifactOS.Platform.Primary` | `zhihu` |
| `first_operational_surface.run_mode` | `ArtifactOS.RunMode` | `shadow` |
| `first_operational_surface.legacy_stage` | `ArtifactOS.LegacyStage` | `L0` |
| `first_operational_surface.real_publish_allowed` | `ArtifactOS.Publish.AllowReal` | `false` |
| `first_operational_surface.media_publish_mode` | `ArtifactOS.Publish.Mode` | `manual-review` |
| `first_operational_surface.audience_stage_scope` | `ArtifactOS.Audience.Scope` | `S1,S2,S3` |
| `first_operational_surface.theory_visibility` | `ArtifactOS.Theory.Visibility` | `medium` |
| `first_operational_surface.database.main` | `ArtifactOS.DB.Name` | `artifactos` |
| `first_operational_surface.database.test` | `ArtifactOS.DB.Test.Name` | `artifactos_test` |

## Credentials → DB1 (DeepBase.Security.SaveSecret)

| Secret | Key |
|--------|-----|
| PG password | `ArtifactOS.DB.Pass` |
| LLM API key | `ArtifactOS.LLM.ApiKey` (future) |

## Migration method

Done via Delphi one-time setup script or Python init script:
```
DeepBase.SetConfig('ArtifactOS.SourcePack.Name', '一元论');
DeepBase.Security.SaveSecret('ArtifactOS.DB.Pass', PwdFromEnv);
```

The YAML file `first_operational_surface.yaml` is kept as a human-readable reference but is no longer the machine config source.