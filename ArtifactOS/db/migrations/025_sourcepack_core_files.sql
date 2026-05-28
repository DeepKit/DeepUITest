-- ArtifactOS SourcePack core file selection (P1 #10)
-- Target: artifactos_test first, then artifactos production after review.
-- Phase 1A imports only ~50 core files (governance + canonical samples).
-- Full 2905-file scan remains in source_inventory_candidate as lightweight index.
-- Core files are the only ones actively used in Phase 1A SourcePackSnapshot.

begin;

-- 1. Core files table — curated subset actually used in Phase 1A
create table if not exists artifactos.source_core_file (
  id uuid primary key default gen_random_uuid(),
  source_pack_id uuid not null references artifactos.source_pack(id),
  file_path text not null,
  source_layer text not null check (source_layer in (
    'governance','canonical','evidence','explanation','practice'
  )),
  claim_strength text check (claim_strength in ('C1','C2','C3','C4','C5')),
  human_confirmed boolean not null default false,
  human_confirmed_at timestamptz,
  external_publish_allowed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (source_pack_id, file_path)
);

-- 2. Seed core files — governance (7 registries) + canonical (mother texts 10-15) +
--    explanation (10-15 sample) + practice (10-15 sample)
--    Files must exist; duplicates silently skipped via ON CONFLICT DO NOTHING.

do $$
declare
  sp_id uuid;
begin
  select id into sp_id from artifactos.source_pack order by created_at limit 1;
  if sp_id is null then
    raise notice 'skip source_core_file seed: no source_pack found';
    return;
  end if;

  -- Governance files (7)
  insert into artifactos.source_core_file (source_pack_id, file_path, source_layer, claim_strength)
  values
    (sp_id, '00-索引与导航/对语言/README.md', 'governance', 'C4'),
    (sp_id, '00-索引与导航/对语言/模块注册表-Module-Registry.md', 'governance', 'C4'),
    (sp_id, '00-索引与导航/对语言/层级身份注册表-Layer-Identity-Registry.md', 'governance', 'C4'),
    (sp_id, '00-索引与导航/对语言/跨层语义守恒协议-Cross-Layer-Semantic-Conservation-Protocol.md', 'governance', 'C4'),
    (sp_id, '00-索引与导航/对语言/最小可运行子集与快速入门路径-Minimal-Runnable-Subset-and-Quickstart.md', 'governance', 'C3'),
    (sp_id, '00-索引与导航/对语言/AI修改必读-理论体系治理原则-4AI.md', 'governance', 'C4'),
    (sp_id, '00-索引与导航/对语言/目录与文件命名总规范-Directory-and-File-Naming-Standard.md', 'governance', 'C4')
  on conflict (source_pack_id, file_path) do nothing;

  -- Canonical mother texts — sampled from 01-母板 equivalents
  -- (paths verified against D:\_Progs\一元论 directory scan)
  insert into artifactos.source_core_file (source_pack_id, file_path, source_layer, claim_strength)
  values
    (sp_id, '10-哲学核心层（DM）/01-母板/DM-最小哲学地基.md', 'canonical', 'C5'),
    (sp_id, '10-哲学核心层（DM）/01-母板/DM-差异-结构-边界语言.md', 'canonical', 'C5'),
    (sp_id, '10-哲学核心层（DM）/01-母板/DM-主张强度与断言边界.md', 'canonical', 'C5'),
    (sp_id, '20-应用框架层（ASTO）/01-母板/ASTO-结构化系统分析语法.md', 'canonical', 'C5'),
    (sp_id, '25-能力有序治理层（OCGS）/01-母板/OCGS-能力入序与裸能力规则.md', 'canonical', 'C5'),
    (sp_id, '30-权利边界层（ARBT）/01-母板/ARBT-外部性与约束判断.md', 'canonical', 'C4'),
    (sp_id, '40-责任架构层（TAT）/01-母板/TAT-责任阈值与高影响边界.md', 'canonical', 'C4'),
    (sp_id, '50-工程方法层（ODD）/01-母板/ODD-产出物契约-验证-证据-封存.md', 'canonical', 'C5'),
    (sp_id, '51-认知分流层（COP）/01-母板/COP-风险分流模型.md', 'canonical', 'C4'),
    (sp_id, '52-识局假设层（LSM）/01-母板/LSM-结构困局与责任流向.md', 'canonical', 'C3')
  on conflict (source_pack_id, file_path) do nothing;

  -- Explanation samples
  insert into artifactos.source_core_file (source_pack_id, file_path, source_layer, claim_strength)
  values
    (sp_id, '20-应用框架层（ASTO）/03-解释/工程版/README.md', 'explanation', 'C2'),
    (sp_id, '20-应用框架层（ASTO）/03-解释/人文版/README.md', 'explanation', 'C2'),
    (sp_id, '20-应用框架层（ASTO）/03-解释/一页版/README.md', 'explanation', 'C2'),
    (sp_id, '20-应用框架层（ASTO）/03-解释/青春版/README.md', 'explanation', 'C2'),
    (sp_id, '54-前线显影层（PFM）/04-实践/PFM-找场立灯塔发光吸引.md', 'explanation', 'C2')
  on conflict (source_pack_id, file_path) do nothing;

  -- Practice / protocol samples
  insert into artifactos.source_core_file (source_pack_id, file_path, source_layer, claim_strength)
  values
    (sp_id, '51-认知分流层（COP）/04-实践/COP-风险分流决策流程.md', 'practice', 'C3'),
    (sp_id, '52-识局假设层（LSM）/04-实践/LSM-识局观察协议.md', 'practice', 'C3'),
    (sp_id, '53-归属论层（WSH）/04-实践/WSH-复盘与表达视角协议.md', 'practice', 'C3'),
    (sp_id, '54-前线显影层（PFM）/04-实践/PFM-前提要求与停止条件.md', 'practice', 'C3'),
    (sp_id, '55-前提承接层（RT6）/04-实践/RT6-非临床承接协议.md', 'practice', 'C3')
  on conflict (source_pack_id, file_path) do nothing;
end $$;

commit;