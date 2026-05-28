# BetterCiv 网站工程

> 三个域名的实际网站代码与部署资产
> 更新�?026-04-29

---

## 目录

```
02Business/
├── BetterCiv/
�?  ├── goodmem.cn/        �?已上线（FastAPI 后端 + H5 前端�?�?  ├── asto.cc/           🚧 待建（静态理论展示站�?�?  └── betterCiv.org/     🚧 待建（执行系统入口站�?└── DeepLaunch/               🔧 软件已有，网�?DeepLaunch.top 待建
```

---

## goodmem.cn �?前线港口（已上线�?
**定位**：思维越狱（WSM 五局诊断�? 五行和悦论（WSH 个体回归）的承接�?
**技术栈**：FastAPI + PostgreSQL + 微信支付 V3 + H5 前端

**核心功能**�?- `/break` �?WSM 五局诊断入口�?2 �?/ 9 题两种模式）
- `/reader` �?付费�?108 篇个性化文章阅读�?- `/return` �?复诊与年度回正系统（WSH�?- `/wsh` �?五行和悦论承接页
- 微信支付 V3（�?99/¥399/¥999 三档�?- JWT Token 防盗 + 设备指纹互踢 + 阅读历史追踪

**产品�?*�?| 产品 | 诊断模式 | 对应理论 |
|------|---------|---------|
| 思维越狱 | WSM 五局（water/wood/fire/earth/metal）| WSM + COP |
| 五行和悦�?| WSH 五维生命结构 | WSH（独立分支） |

**文档**：`goodmem.cn/docs/`

---

## asto.cc �?理论母库（待建）

**定位**：差异一元论的官方理论展示站

**建议技术栈**：静态站点（Astro/Hugo/Next.js），从一元论 markdown 直接渲染

**待建页面**�?- 首页（八层架构图 + Zenodo DOI 入口�?- 8 个理论层详情�?- 英文 landing page
- 作者页

**内容来源**：`D:/_Progs/一元论/` 的全�?markdown 源文�?
---

## betterCiv.org �?执行入口（待建）

**定位**：BetterCiv 执行系统的对外服务入�?
**建议技术栈**：静态首�?+ 联系表单（Webflow/WordPress/自建�?
**待建页面**�?- 首页（三大服务入口）
- 组织诊断服务�?- AI治理服务�?- 高管承接服务�?- 联系/预约

---

## 部署关系

```
用户流：
  goodmem.cn（免费自测）
    �?付费
  goodmem.cn/reader（个性化文章�?    �?企业需�?  betterCiv.org（组织诊�?AI治理�?    �?理论溯源
  asto.cc（完整八层架构）
```

---

## 当前纪律

- goodmem.cn 后端不暴�?COP 权重/判定参数
- goodmem.cn 产品文案�?`.BetterCiv/04_产品�?` 为准
- asto.cc 理论内容�?`一元论/` 仓库为准
- 三站互链但不共用视觉模版
