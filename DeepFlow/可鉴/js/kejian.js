/* ============================================================
   可鉴 · 决策操作系统 — 核心逻辑
   每个决策，可见，可鉴。
   - 四角色并行推演（coach/critic/mirror/observer）
   - 聚合（aggregator）→ 胶片（film_generator）
   - 降级状态可见（degraded 展示，不假绿）
   ============================================================ */

"use strict";

const SKILLS_API = "http://127.0.0.1:8001";
const EXECUTE_URL = SKILLS_API + "/skills/execute";
const LLM_CHAT_URL = SKILLS_API + "/llm/chat";
const LLM_CHAT_STREAM_URL = SKILLS_API + "/llm/chat/stream";
const REQUEST_TIMEOUT_MS = 300000; // 5 分钟（LLM 调用可达 2-3 分钟）

// ---------- 六角色定义 ----------
const ROLES = [
  { key: "coach",     skill: "decision_coach",     zh: "决策教练",  desc: "拆解目标、路径与代价" },
  { key: "critic",    skill: "decision_critic",    zh: "批判者",    desc: "攻击假设、极限推演" },
  { key: "mirror",    skill: "decision_mirror",    zh: "反思者",    desc: "照见决策者的盲区与动机" },
  { key: "observer",  skill: "decision_observer",  zh: "观察者",    desc: "只数事实，不掺立场" },
  { key: "aggregator",skill: "decision_aggregator",zh: "聚合者",    desc: "收敛四视角的共识与分歧" },
  { key: "film",      skill: "film_generator",     zh: "胶片生成者",desc: "把过程写成可鉴的胶片" },
];

const TEMPLATES = {
  strategic:   { name: "战略决策",   hint: "扩张/新市场/产品线 — 聚焦机会成本、执行能力与可逆性", context: { decision_type: "strategic",   scope: "expansion/new-market/product" } },
  investment:  { name: "投资决策",   hint: "资本配置/风险敞口 — 聚焦回报、回本周期、最大可承受损失与退出路径", context: { decision_type: "investment",  scope: "capital-allocation/risk" } },
  personnel:   { name: "人事决策",   hint: "晋升/招聘/调整 — 聚焦公平性、示范效应与沟通成本", context: { decision_type: "personnel",   scope: "promotion/hiring/restructure" } },
  procurement: { name: "采购决策",   hint: "供应商选择/预算 — 聚焦总拥有成本、锁定风险与交付记录", context: { decision_type: "procurement", scope: "vendor-selection/budget" } },
  medical:     { name: "医疗健康",   hint: "治疗方案/手术/用药 — 聚焦诊断依据、疗效风险对比与第二诊疗意见", context: { decision_type: "medical",     scope: "treatment/surgery/medication" } },
  legal:       { name: "法律纠纷",   hint: "诉讼/和解/维权 — 聚焦证据链、成本时间线与可接受结果", context: { decision_type: "legal",       scope: "litigation/settlement" } },
  education:   { name: "教育升学",   hint: "择校/专业/留学/培训 — 聚焦长期目标、适配度与退出成本", context: { decision_type: "education",   scope: "schooling/major/study-abroad" } },
  family:      { name: "家庭重大",   hint: "买房/搬家/生育/婚姻 — 聚焦财务可持续、可逆性与成员共识", context: { decision_type: "family",      scope: "housing/relocation/family" } },
};

// ---------- 状态 ----------
let activeTemplate = "strategic";
let running = false;

// ---------- DOM ----------
const $ = (id) => document.getElementById(id);
const problemInput = $("problem-input");
const startBtn = $("start-btn");
const statusHint = $("status-hint");
const rolesSection = $("roles-section");
const roleGrid = $("role-grid");
const aggregateSection = $("aggregate-section");
const aggregateBody = $("aggregate-body");
const aggregateTag = $("aggregate-tag");
const filmSection = $("film-section");
const filmBody = $("film-body");
const rolesTag = $("roles-tag");
const shareOverlay = $("share-overlay");
const followupSection = $("followup-section");
const chatLog = $("chat-log");
const followupInput = $("followup-input");
const followupBtn = $("followup-btn");

// 追问上下文（本次治理的原问题与胶片摘要）
let followupContext = { problem: "", filmSummary: "" };
let chatHistory = []; // [{role, content}]

// ---------- 模板选择 ----------
document.querySelectorAll(".template-chip").forEach((chip) => {
  chip.addEventListener("click", () => {
    document.querySelectorAll(".template-chip").forEach((c) => c.classList.remove("active"));
    chip.classList.add("active");
    activeTemplate = chip.dataset.template;
    const hintEl = $("template-hint");
    if (hintEl && TEMPLATES[activeTemplate]) {
      hintEl.textContent = TEMPLATES[activeTemplate].hint;
    }
  });
});

// ---------- Skills 调用 ----------
async function callSkill(skillName, paramsObj) {
  // 契约: {skill_name, params, context, timeout_ms} → {skill_name, status, result, error, execution_time_ms, timestamp}
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const resp = await fetch(EXECUTE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        skill_name: skillName,
        params: paramsObj,
        context: {},
        timeout_ms: REQUEST_TIMEOUT_MS,
      }),
      signal: controller.signal,
    });
    if (!resp.ok) {
      const errText = await resp.text().catch(() => "");
      throw new Error(`HTTP ${resp.status}: ${errText.slice(0, 200)}`);
    }
    return await resp.json();
  } finally {
    clearTimeout(timer);
  }
}

// ---------- 角色卡片渲染 ----------
function renderRoleCards() {
  roleGrid.innerHTML = "";
  ROLES.forEach((role) => {
    const card = document.createElement("div");
    card.className = "role-card";
    card.id = "role-card-" + role.key;
    card.innerHTML = `
      <div class="role-head">
        <span class="role-name">${role.zh}<span class="role-zh">${role.key}</span></span>
        <span class="role-state queued" id="role-state-${role.key}">排队中</span>
      </div>
      <div class="role-body" id="role-body-${role.key}">${role.desc}</div>
      <div class="role-meta" id="role-meta-${role.key}"></div>
    `;
    roleGrid.appendChild(card);
  });
}

function setRoleState(key, state, text) {
  const el = $("role-state-" + key);
  if (!el) return;
  el.className = "role-state " + state;
  el.textContent = text;
  const card = $("role-card-" + key);
  if (card) {
    card.classList.remove("done", "degraded", "error");
    if (state === "done") card.classList.add("done");
    if (state === "degraded") card.classList.add("degraded");
    if (state === "error") card.classList.add("error");
  }
}

function setRoleBody(key, text) {
  const el = $("role-body-" + key);
  if (el) el.textContent = text;
}

function setRoleMeta(key, text) {
  const el = $("role-meta-" + key);
  if (el) el.textContent = text;
}

// ---------- 结果解析 ----------
function extractResult(payload) {
  // 契约: {skill_name, status, result, error, execution_time_ms, timestamp}
  if (!payload) return null;
  if (payload.status === "success" && payload.result) return payload.result;
  if (payload.result) return payload.result; // 容错：status 字段名差异
  return null;
}

// 各角色字段摘要（角色无关的通用总结）
const VIEW_FIELD_LABELS = {
  key_DeepInsights: "洞察",
  guiding_questions: "引导问题",
  assumptions_challenged: "被挑战假设",
  blind_spots: "盲点",
  risks: "风险",
  devil_advocate_questions: "魔鬼代言问题",
  value_conflicts: "价值冲突",
  identity_aspects: "身份因素",
  reflection_prompts: "反思引导",
  decision_patterns: "决策模式",
  objective_observations: "客观观察",
  consensus_points: "共识",
  divergence_points: "分歧",
  self_questions: "自问清单",
};

function summarizeView(view) {
  if (!view || typeof view !== "object") return "";
  const parts = [];
  for (const [field, label] of Object.entries(VIEW_FIELD_LABELS)) {
    const val = view[field];
    if (Array.isArray(val) && val.length) parts.push(label + " " + val.length + " 条");
  }
  if (Array.isArray(view.similar_cases) && view.similar_cases.length) parts.push("类似案例 " + view.similar_cases.length + " 个");
  if (typeof view.summary === "string" && view.summary) parts.push(view.summary.slice(0, 60));
  if (view.degraded) {
    parts.push("⚠ 降级: " + (view.degrade_reason || "unknown"));
  }
  return parts.join(" · ") || "已返回（空结构）";
}

// ---------- 主流程 ----------
async function startGovernance() {
  const problem = problemInput.value.trim();
  if (!problem) {
    statusHint.textContent = "请先输入您要治理的决策问题";
    return;
  }
  if (running) return;
  running = true;
  startBtn.disabled = true;
  statusHint.textContent = "";

  // 显示角色面板
  rolesSection.classList.remove("hidden");
  aggregateSection.classList.add("hidden");
  filmSection.classList.add("hidden");
  shareOverlay.classList.add("hidden");
  renderRoleCards();
  rolesTag.textContent = "可见 · 实时";
  rolesSection.scrollIntoView({ behavior: "smooth", block: "start" });

  const context = TEMPLATES[activeTemplate].context;
  const startedAt = Date.now();

  try {
    // ============ 阶段 1：四视角并行 ============
    const four = [
      { key: "coach",    skill: "decision_coach",    zh: "决策教练" },
      { key: "critic",   skill: "decision_critic",   zh: "批判者" },
      { key: "mirror",   skill: "decision_mirror",   zh: "反思者" },
      { key: "observer", skill: "decision_observer", zh: "观察者" },
    ];

    const views = {};
    await Promise.all(four.map(async (role) => {
      setRoleState(role.key, "thinking", "推演中");
      setRoleBody(role.key, "正在召集模型，展开" + role.zh + "视角……");
      const t0 = Date.now();
      try {
        const resp = await callSkill(role.skill, { problem, context });
        const view = extractResult(resp) || {};
        views[role.key] = view;
        const ms = resp.execution_time_ms || (Date.now() - t0);
        setRoleMeta(role.key, "耗时 " + (ms / 1000).toFixed(1) + "s");
        if (view.degraded) {
          setRoleState(role.key, "degraded", "已降级");
          setRoleBody(role.key, "⚠ LLM 输出未通过校验，已降级到模板。原因: " + (view.degrade_reason || "unknown"));
        } else {
          setRoleState(role.key, "done", "完成");
          setRoleBody(role.key, summarizeView(view) || "分析完成");
        }
      } catch (err) {
        views[role.key] = { degraded: true, degrade_reason: "call_failed: " + err.message };
        setRoleState(role.key, "error", "失败");
        setRoleBody(role.key, "调用失败: " + err.message);
        setRoleMeta(role.key, "");
      }
    }));

    // ============ 阶段 2：聚合 ============
    setRoleState("aggregator", "thinking", "聚合中");
    setRoleBody("aggregator", "正在把四视角揉成一份共识……");
    aggregateSection.classList.remove("hidden");
    aggregateTag.textContent = "聚合中…";
    const aggT0 = Date.now();
    let aggregated = {};
    try {
      const aggResp = await callSkill("decision_aggregator", {
        coach_view: views.coach || {},
        critic_view: views.critic || {},
        mirror_view: views.mirror || {},
        observer_view: views.observer || {},
      });
      aggregated = extractResult(aggResp) || {};
      setRoleMeta("aggregator", "耗时 " + ((aggResp.execution_time_ms || (Date.now() - aggT0)) / 1000).toFixed(1) + "s");
      if (aggregated.degraded) {
        setRoleState("aggregator", "degraded", "已降级");
        setRoleBody("aggregator", "⚠ 聚合降级: " + (aggregated.degrade_reason || "unknown"));
        aggregateTag.textContent = "已降级";
      } else {
        setRoleState("aggregator", "done", "完成");
        setRoleBody("aggregator", summarizeView(aggregated) || "聚合完成");
        aggregateTag.textContent = "完成";
      }
    } catch (err) {
      aggregated = { degraded: true, degrade_reason: "call_failed: " + err.message };
      setRoleState("aggregator", "error", "失败");
      setRoleBody("aggregator", "调用失败: " + err.message);
      aggregateTag.textContent = "失败";
    }
    renderAggregate(aggregated);

    // ============ 阶段 3：胶片 ============
    setRoleState("film", "thinking", "生成中");
    setRoleBody("film", "正在把推演过程写成可鉴的胶片……");
    const filmT0 = Date.now();
    let filmText = "";
    let filmDegraded = false;
    let film = {}; // T11: 提到 try 外，避免异常时 L318 引用未定义变量
    try {
      const filmResp = await callSkill("film_generator", {
        problem,
        aggregated: aggregated || {},
      });
      film = extractResult(filmResp) || {};
      filmText = renderFilmText(film);
      filmDegraded = !!film.degraded;
      setRoleMeta("film", "耗时 " + ((filmResp.execution_time_ms || (Date.now() - filmT0)) / 1000).toFixed(1) + "s");
      if (filmDegraded) {
        setRoleState("film", "degraded", "已降级");
        setRoleBody("film", "⚠ 胶片降级: " + (film.degrade_reason || "unknown"));
      } else {
        setRoleState("film", "done", "完成");
        setRoleBody("film", "胶片已生成");
      }
    } catch (err) {
      filmText = "胶片生成失败: " + err.message;
      filmDegraded = true;
      setRoleState("film", "error", "失败");
      setRoleBody("film", "调用失败: " + err.message);
    }

    // ============ 展示胶片 ============
    const totalSec = ((Date.now() - startedAt) / 1000).toFixed(1);
    rolesTag.textContent = "总耗时 " + totalSec + "s";
    filmSection.classList.remove("hidden");
    filmBody.innerHTML = filmText;
    if (filmDegraded) {
      const note = document.createElement("div");
      note.className = "degrade-note";
      note.textContent = "⚠ 本次治理存在降级（可见性承诺：我们不隐藏失败）。部分内容来自内置模板。";
      filmBody.parentNode.insertBefore(note, filmBody.nextSibling);
    }
    // T10: 分享卡片携带胶片对象（含视觉字段）
    renderShareCard(problem, views, aggregated, film);
    // 激活追问区：携带本次治理上下文
    followupContext = { problem, filmSummary: extractPlainText(filmText) };
    chatHistory = [{ role: "system", content: buildFollowupSystemPrompt(problem) }];
    followupSection.classList.remove("hidden");
    chatLog.innerHTML = "";
    filmSection.scrollIntoView({ behavior: "smooth", block: "start" });
    statusHint.textContent = "治理完成，总耗时 " + totalSec + "s（可见，可鉴）";
  } catch (err) {
    statusHint.textContent = "治理中断: " + err.message;
    rolesTag.textContent = "中断";
  } finally {
    running = false;
    startBtn.disabled = false;
  }
}

// ---------- 聚合渲染 ----------
// T11: 数组元素安全转文本 — 对象取常见文本字段，避免 [object Object]
function itemText(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (typeof v === "object") {
    const keys = ["risk", "description", "point", "text", "summary", "content", "insight", "question", "assumption", "blind_spot", "challenge", "divergence", "consensus"];
    for (const k of keys) {
      if (typeof v[k] === "string" && v[k]) return v[k];
    }
    try { return JSON.stringify(v); } catch (e) { return String(v); }
  }
  return String(v);
}

function renderAggregate(agg) {
  if (!agg || typeof agg !== "object") {
    aggregateBody.innerHTML = "<div class='degrade-note'>聚合结果不可用。</div>";
    return;
  }
  let html = "";
  const sections = [
    { key: "key_DeepInsights", title: "关键洞察" },
    { key: "consensus_points", title: "共识区间" },
    { key: "divergence_points", title: "分歧点" },
    { key: "risks", title: "风险" },
    { key: "self_questions", title: "自问清单" },
  ];
  sections.forEach(({ key, title }) => {
    const val = agg[key];
    if (Array.isArray(val) && val.length) {
      html += `<h4>${title}</h4><ul>` + val.map((v) => `<li>${escapeHtml(itemText(v))}</li>`).join("") + "</ul>";
    } else if (typeof val === "string" && val) {
      html += `<h4>${title}</h4><p>${escapeHtml(val)}</p>`;
    }
  });
  // 情绪摘要（对象类型，如 {primary_emotion, secondary_emotions, intensity}）
  if (agg.emotional_summary && typeof agg.emotional_summary === "object" && Object.keys(agg.emotional_summary).length) {
    const emo = agg.emotional_summary;
    const parts = [];
    if (emo.primary_emotion) parts.push("主情绪: " + emo.primary_emotion);
    if (Array.isArray(emo.secondary_emotions) && emo.secondary_emotions.length) parts.push("次级: " + emo.secondary_emotions.join(", "));
    if (emo.intensity) parts.push("强度: " + emo.intensity);
    if (parts.length) html += `<h4>情绪光谱</h4><p>${escapeHtml(parts.join(" · "))}</p>`;
  }
  // 视角摘要列表
  if (Array.isArray(agg.views) && agg.views.length) {
    html += `<h4>四视角摘要</h4><ul>` + agg.views
      .filter((v) => v && v.summary)
      .map((v) => `<li><b>${escapeHtml(v.role || "?")}</b> — ${escapeHtml(String(v.summary))}</li>`)
      .join("") + "</ul>";
  }
  if (agg.degraded) {
    html += `<div class="degrade-note">⚠ 聚合降级: ${escapeHtml(agg.degrade_reason || "unknown")}</div>`;
  }
  aggregateBody.innerHTML = html || "<p style='color:var(--text-dim)'>聚合结果为空。</p>";
}

// ---------- 分享卡片 ----------
// T10: 卡片填充核心洞察（前 2 条）+ 角色徽章 + 品牌水印
function renderShareCard(problem, views, aggregated, film) {
  $("share-card-problem").textContent = problem;
  const rolesHtml = Object.values(views)
    .filter((v) => v && v.role)
    .map((v) => `<span class="share-card-role">${escapeHtml(String(v.role))}</span>`)
    .join("");
  $("share-card-roles").innerHTML = rolesHtml || "";
  const insights = (film && Array.isArray(film.key_insights) && film.key_insights.length)
    ? film.key_insights
    : ((aggregated && Array.isArray(aggregated.key_DeepInsights)) ? aggregated.key_DeepInsights : []);
  const topInsights = insights.filter(Boolean).slice(0, 2);
  $("share-card-insights").innerHTML = topInsights.length
    ? `<div class="share-card-insight-label">核心洞察</div>` + topInsights.map((i) => `<div class="share-card-insight">${escapeHtml(String(i).slice(0, 60))}</div>`).join("")
    : "";
  const highlight = insights[0] ? String(insights[0]).slice(0, 60) : "六角色并行推演，产出可鉴的思维胶片";
  $("share-card-title").textContent = "决策思维胶片 · " + highlight;
}

// ---------- 胶片文本渲染 ----------
// 契约: {title, subtitle, key_insights, tradeoffs, emotional_spectrum, decision_readiness,
//         sections, self_questions, closing_note, disclaimer, metadata}
// T10: 视觉化渲染 — 洞察卡 / 权衡对比 / 情绪谱 / 成熟度仪表 + 文本章节
function renderFilmText(film) {
  if (!film || typeof film !== "object") return "";
  // 兼容旧式纯文本返回
  if (typeof film.film === "string") return film.film;
  if (typeof film.summary === "string" && !film.title && !film.sections) return film.summary;
  let html = "";
  if (film.title) html += `<h1>${escapeHtml(film.title)}</h1>`;
  if (film.subtitle) html += `<p style='color:var(--text-dim)'>${escapeHtml(film.subtitle)}</p>`;
  // T10: 视觉区（胶片显影）
  html += renderFilmVisual(film);
  if (Array.isArray(film.sections) && film.sections.length) {
    film.sections.forEach((sec) => {
      if (!sec || !sec.name) return;
      html += `<h2>${escapeHtml(sec.name)}</h2>`;
      if (sec.description) html += `<p style='color:var(--text-dim)'>${escapeHtml(sec.description)}</p>`;
      if (Array.isArray(sec.content) && sec.content.length) {
        html += `<ul>` + sec.content.map((c) => `<li>${escapeHtml(itemText(c))}</li>`).join("") + `</ul>`;
      } else if (typeof sec.content === "string" && sec.content) {
        html += `<p>${escapeHtml(sec.content)}</p>`;
      } else if (sec.content && typeof sec.content === "object") {
        html += `<p>${escapeHtml(JSON.stringify(sec.content, null, 2))}</p>`;
      }
    });
  }
  if (Array.isArray(film.self_questions) && film.self_questions.length) {
    html += `<h2>给你的自我提问</h2><ol>` + film.self_questions.map((q) => `<li>${escapeHtml(String(q))}</li>`).join("") + `</ol>`;
  }
  if (film.closing_note) html += `<p><strong>${escapeHtml(film.closing_note)}</strong></p>`;
  if (film.disclaimer) html += `<p style='color:var(--text-dim);font-size:12px'>${escapeHtml(film.disclaimer)}</p>`;
  if (!html) html = escapeHtml(JSON.stringify(film, null, 2));
  return html;
}

// T10: 胶片视觉区 — 洞察卡 / 权衡对比 / 情绪谱 / 成熟度仪表
function renderFilmVisual(film) {
  let html = "";
  // 核心洞察卡片
  const insights = Array.isArray(film.key_insights) ? film.key_insights.filter(Boolean) : [];
  if (insights.length) {
    html += `<div class="film-visual-block"><h3 class="visual-title">核心洞察</h3><div class="film-insight-grid">`;
    insights.forEach((ins, i) => {
      html += `<div class="film-insight-card"><span class="film-insight-num">${i + 1}</span><span class="film-insight-text">${escapeHtml(String(ins))}</span></div>`;
    });
    html += `</div></div>`;
  }
  // 关键权衡对比
  const tradeoffs = Array.isArray(film.tradeoffs) ? film.tradeoffs.filter((t) => t && t.choice) : [];
  if (tradeoffs.length) {
    html += `<div class="film-visual-block"><h3 class="visual-title">关键权衡</h3>`;
    tradeoffs.forEach((t) => {
      html += `<div class="film-tradeoff"><div class="tradeoff-choice">${escapeHtml(String(t.choice))}</div><div class="tradeoff-cols">`;
      const pros = Array.isArray(t.pros) ? t.pros : [];
      const cons = Array.isArray(t.cons) ? t.cons : [];
      html += `<div class="tradeoff-col pros"><h5>支持</h5><ul>` + (pros.length ? pros.map((p) => `<li>${escapeHtml(String(p))}</li>`).join("") : `<li style='color:var(--text-dim)'>—</li>`) + `</ul></div>`;
      html += `<div class="tradeoff-col cons"><h5>代价</h5><ul>` + (cons.length ? cons.map((c) => `<li>${escapeHtml(String(c))}</li>`).join("") : `<li style='color:var(--text-dim)'>—</li>`) + `</ul></div>`;
      html += `</div></div>`;
    });
    html += `</div>`;
  }
  // 情绪谱
  const spectrum = Array.isArray(film.emotional_spectrum) ? film.emotional_spectrum.filter((s) => s && s.emotion) : [];
  if (spectrum.length) {
    html += `<div class="film-visual-block"><h3 class="visual-title">情绪光谱</h3><div class="film-spectrum">`;
    spectrum.forEach((s) => {
      const val = (typeof s.intensity === "number" && s.intensity >= 0 && s.intensity <= 100) ? s.intensity : null;
      const bar = val === null
        ? `<span class="spectrum-bar"><span class="spectrum-fill spectrum-unknown" style="width:100%"></span></span><span class="spectrum-val">待显影</span>`
        : `<span class="spectrum-bar"><span class="spectrum-fill" style="width:${val}%"></span></span><span class="spectrum-val">${val}</span>`;
      html += `<div class="spectrum-item"><span class="spectrum-emotion">${escapeHtml(String(s.emotion))}</span>${bar}</div>`;
    });
    html += `</div></div>`;
  }
  // 决策成熟度仪表
  const readiness = film.decision_readiness;
  if (typeof readiness === "number" && readiness >= 0 && readiness <= 100) {
    html += `<div class="film-visual-block"><h3 class="visual-title">决策成熟度</h3>`;
    html += `<div class="film-readiness"><span class="readiness-bar"><span class="readiness-fill" style="width:${readiness}%"></span></span><span class="readiness-val">${readiness} / 100</span></div>`;
    html += `<p class="readiness-note" style='color:var(--text-dim)'>成熟度越高，代表决策条件越充分；它不替你做决定。</p></div>`;
  }
  return html;
}

// ---------- 追问（继续聊天） ----------
// 追问走 /llm/chat 对话式端点，带本次治理上下文，即时响应
function buildFollowupSystemPrompt(problem) {
  return [
    "你是可鉴（决策操作系统）的追问助手。你已经参与了一次六角色决策治理，",
    "现在用户基于胶片内容继续追问。请结合治理上下文回答，保持哲学中立：",
    "不替用户做决定，不直接说\"你应该\"，多用\"也许\"\"可能\"。",
    "回答要具体、可操作，可引用胶片中的洞察。",
    "原始决策问题：" + problem,
  ].join("\n");
}

function extractPlainText(html) {
  if (!html) return "";
  const div = document.createElement("div");
  div.innerHTML = html;
  return (div.textContent || "").trim().slice(0, 3000);
}

function appendChatMsg(role, text) {
  const msg = document.createElement("div");
  msg.className = "chat-msg " + (role === "user" ? "user" : "assistant");
  msg.textContent = text;
  chatLog.appendChild(msg);
  chatLog.scrollTop = chatLog.scrollHeight;
  return msg;
}

async function sendFollowup() {
  const question = followupInput.value.trim();
  if (!question || followupBtn.disabled) return;
  followupInput.value = "";
  followupBtn.disabled = true;

  appendChatMsg("user", question);
  const thinkingEl = appendChatMsg("assistant", "正在结合本次治理上下文思考……");
  thinkingEl.classList.add("thinking");

  chatHistory.push({ role: "user", content: question });
  // 上下文注入：胶片摘要放在最近一轮 user 消息后，保持模型注意力
  const contextMsg = { role: "user", content: "本次治理胶片摘要（供追问参考）：\n" + followupContext.filmSummary };
  const messages = chatHistory.slice(0, -1).concat([contextMsg, chatHistory[chatHistory.length - 1]]);
  const body = JSON.stringify({
    model: "claude-qoder-glm-5-2",
    messages,
    temperature: 0.7,
    max_tokens: 4096,
  });

  try {
    // T13: 优先流式逐字显影，失败自动降级非流式
    const answer = await streamFollowupAnswer(body, thinkingEl);
    if (!answer) throw new Error("空回复");
    thinkingEl.classList.remove("thinking");
    thinkingEl.textContent = answer;
    chatHistory.push({ role: "assistant", content: answer });
  } catch (err) {
    thinkingEl.classList.remove("thinking");
    thinkingEl.textContent = "⚠ 追问失败（服务不可达或超时）: " + err.message + "。请确认 Skills 服务在 8001 端口运行。";
  } finally {
    followupBtn.disabled = false;
    followupInput.focus();
  }
}

// T13: 流式输出 —— SSE 增量渲染；流式端点不可用或无产出时降级非流式
async function streamFollowupAnswer(body, el) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let resp;
  try {
    resp = await fetch(LLM_CHAT_STREAM_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
  // 流式端点不可用（404/5xx）→ 降级非流式
  if (!resp.ok) return await nonStreamFallback(body);

  let full = "";
  let started = false;
  let streamError = null;
  const reader = resp.body.getReader();
  const decoder = new TextDecoder("utf-8");
  let buffer = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split("\n\n"); // SSE 事件分隔
    buffer = events.pop(); // 保留尾部不完整片段
    for (const evt of events) {
      const line = evt.trim();
      if (!line.startsWith("data:")) continue;
      let obj;
      try { obj = JSON.parse(line.slice(5).trim()); } catch (e) { continue; }
      if (obj.type === "delta" && obj.content) {
        if (!started) { // 首个增量：清除思考占位，开始显影
          el.classList.remove("thinking");
          el.textContent = "";
          started = true;
        }
        full += obj.content;
        el.textContent = full;
        chatLog.scrollTop = chatLog.scrollHeight;
      } else if (obj.type === "error") {
        streamError = obj.message || "stream error";
      }
    }
  }
  // 流式无产出：降级非流式；已有部分内容则保留
  if (!full && streamError) return await nonStreamFallback(body);
  if (!full) throw new Error(streamError || "空回复");
  return full;
}

// T13: 非流式兑底（原 /llm/chat 一次性响应）
async function nonStreamFallback(body) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  let resp;
  try {
    resp = await fetch(LLM_CHAT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
  if (!resp.ok) throw new Error("HTTP " + resp.status);
  const data = await resp.json();
  return (data.content || "").trim();
}

// ---------- 事件绑定 ----------
startBtn.addEventListener("click", startGovernance);
followupBtn.addEventListener("click", sendFollowup);
followupInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    sendFollowup();
  }
});

$("share-btn").addEventListener("click", () => shareOverlay.classList.remove("hidden"));

$("close-share").addEventListener("click", () => shareOverlay.classList.add("hidden"));

$("copy-btn").addEventListener("click", async () => {
  const text = filmBody.textContent + "\n\n—— 由可鉴生成 · 每个决策，可见，可鉴。";
  try {
    await navigator.clipboard.writeText(text);
    statusHint.textContent = "胶片已复制（含品牌水印）";
  } catch (err) {
    statusHint.textContent = "复制失败: " + err.message;
  }
});

$("download-share").addEventListener("click", () => {
  const card = $("share-card");
  // 用 canvas 截图卡片，下载 PNG
  try {
    const canvas = document.createElement("canvas");
    const w = card.offsetWidth * 2, h = card.offsetHeight * 2;
    canvas.width = w; canvas.height = h;
    const ctx = canvas.getContext("2d");
    ctx.scale(2, 2);
    // 简单绘制：深色底 + 文本（避免依赖 html2canvas）
    const bg = ctx.createLinearGradient(0, 0, 0, card.offsetHeight);
    bg.addColorStop(0, "#16223f"); bg.addColorStop(1, "#0b1020");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, card.offsetWidth, card.offsetHeight);
    ctx.strokeStyle = "#d4af6a"; ctx.lineWidth = 2;
    ctx.strokeRect(1, 1, card.offsetWidth - 2, card.offsetHeight - 2);
    ctx.fillStyle = "#f0d9a8";
    ctx.font = "bold 28px sans-serif";
    ctx.fillText("可鉴", 28, 52);
    ctx.strokeStyle = "#d4af6a"; ctx.lineWidth = 1;
    ctx.strokeText("可鉴", 28, 52);
    ctx.fillStyle = "#8fa0c0"; ctx.font = "14px sans-serif";
    ctx.fillText("决策操作系统", card.offsetWidth - 150, 40);
    ctx.fillStyle = "#e8edf7"; ctx.font = "bold 20px sans-serif";
    ctx.fillText("决策思维胶片", 28, 110);
    ctx.fillStyle = "#8fa0c0"; ctx.font = "15px sans-serif";
    wrapText(ctx, $("share-card-problem").textContent || "", 28, 150, card.offsetWidth - 56, 24, 15);
    // T10: 绘制核心洞察（取自分享卡片 DOM）
    ctx.fillStyle = "#d4af6a"; ctx.font = "bold 15px sans-serif";
    ctx.fillText("核心洞察", 28, 240);
    ctx.fillStyle = "#e8edf7"; ctx.font = "14px sans-serif";
    const insights = Array.from(document.querySelectorAll("#share-card-insights .share-card-insight"))
      .map((el) => el.textContent.trim())
      .filter(Boolean);
    let iy = 272;
    insights.slice(0, 3).forEach((ins) => {
      ctx.fillStyle = "#d4af6a";
      ctx.fillText("◆", 28, iy);
      ctx.fillStyle = "#e8edf7";
      wrapText(ctx, ins, 50, iy, card.offsetWidth - 78, 24, 14);
      iy += 24;
    });
    ctx.fillStyle = "#d4af6a";
    ctx.fillText("每个决策，可见，可鉴。", 28, card.offsetHeight - 40);
    ctx.fillStyle = "#8fa0c0"; ctx.font = "13px sans-serif";
    ctx.fillText("kejian.app 邀请你体验决策操作系统", 28, card.offsetHeight - 16);
    const url = canvas.toDataURL("image/png");
    const a = document.createElement("a");
    a.href = url;
    a.download = "kejian-card.png";
    a.click();
  } catch (err) {
    statusHint.textContent = "下载失败（浏览器限制）: " + err.message;
  }
});

// ---------- 工具 ----------
function wrapText(ctx, text, x, y, maxWidth, lineHeight, fontSize) {
  ctx.font = fontSize + "px sans-serif";
  const chars = String(text).split("");
  let line = "";
  let cy = y;
  for (const ch of chars) {
    const test = line + ch;
    if (ctx.measureText(test).width > maxWidth && line) {
      ctx.fillText(line, x, cy);
      line = ch;
      cy += lineHeight;
      if (cy > y + lineHeight * 4) break;
    } else {
      line = test;
    }
  }
  if (line) ctx.fillText(line, x, cy);
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[c]));
}

// ---------- 初始化 ----------
renderRoleCards();
