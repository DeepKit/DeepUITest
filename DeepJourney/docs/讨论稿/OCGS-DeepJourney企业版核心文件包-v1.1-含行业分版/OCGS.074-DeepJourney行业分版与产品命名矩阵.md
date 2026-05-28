# OCGS.074-DeepJourney行业分版与产品命名矩阵

> 文档性质：行业分版与命名体系补充  
> 所属产品线：OCGS / DeepJourney 企业专家能力化产品线  
> 版本：v0.1  
> 重要修正：DeepJourney 是母平台名，不同行业落地时应使用不同产品名与行业话术。  
> 边界说明：本文件不讨论 DeepLaunch / ShineOps；本文件只讨论 OCGS 企业旅程产品线的行业分版。

---

## 0. 为什么必须做行业分版

DeepJourney 企业版的底层能力是通用的：

```text
宝物定义
场域识别
门禁倒推
业务旅程包
图卡说明书
前台 Coach
Studio 编排
风险确认
迷路恢复
执行留痕
版本管理
```

但是不同行业的用户不会用同一种语言理解它。

如果统一叫：

```text
DeepJourney 企业版
```

在产品内部是可以的，但对外销售时会显得太抽象。

企业客户真正关心的不是“旅程包”这个概念，而是：

```text
政务关心：窗口新人能不能办业务、少投诉；
税务关心：政策变更后前台能不能少答错；
银行关心：柜员能不能合规办理、少风险；
医院关心：导诊 / 医保 / 收费流程能不能少问人；
客服中心关心：新人客服能不能按专家路径处理问题；
HR 关心：入转调离流程能不能标准化；
制造业关心：质检 / 设备 / 工艺操作能不能按标准执行；
软件厂商关心：客户不会用系统时能不能被图卡带起来。
```

因此：

> **DeepJourney 应作为母平台名；行业落地应使用行业化产品名。**

---

## 1. 总体命名原则

### 1.1 母平台名

```text
DeepJourney
深旅 / 深程 / 深导 / 深行
```

建议内部统一使用：

```text
DeepJourney
```

中文对内可以称：

```text
深旅
```

但对外行业分版不一定露出 DeepJourney 母名，可以采用：

```text
行业名 + Journey
行业名 + Coach
行业名 + Studio
```

或中文两字品牌。

---

### 1.2 行业版命名结构

建议采用三层命名：

```text
母平台：
  DeepJourney

行业产品：
  DeepTax / DeepGov / DeepBank / DeepMed / DeepService ...

组件：
  Studio / Coach / JourneyPackage
```

例如：

```text
DeepTax Studio
DeepTax Coach
DeepTax JourneyPackage
```

中文：

```text
深税 Studio
深税 Coach
深税业务旅程包
```

---

### 1.3 中文命名风格

中文名建议尽量两字，便于传播：

```text
深税
深政
深银
深医
深客
深人
深教
深检
深店
深保
深法
深园
```

注意：

```text
1. “深”保留 OCGS / Deep 系列感；
2. 第二个字表示行业；
3. 不同行业不要都叫 DeepJourney 企业版；
4. 对外材料中行业名优先，DeepJourney 可作为技术底座说明。
```

---

## 2. 行业产品名总表

| 行业 | 推荐中文名 | 推荐英文名 | 对外一句话 |
|---|---|---|---|
| 政务服务 | 深政 | DeepGov Journey | 让窗口新人按专家路径办事，少问人、少出错、少投诉 |
| 税务服务 | 深税 | DeepTax Journey | 把税务专家经验变成前台可执行的业务旅程 |
| 银行柜面 | 深银 | DeepBank Journey | 让柜员按合规旅程办理业务，降低差错和风险 |
| 保险服务 | 深保 | DeepInsurance Journey | 把核保、理赔、客服流程变成可执行旅程 |
| 医疗导诊 / 医保 | 深医 | DeepMed Journey | 让导诊、医保、收费人员按图卡处理复杂流程 |
| 企业客服 | 深客 | DeepService Journey | 让新人客服按专家路径接待客户、处理售后 |
| HR / 人事行政 | 深人 | DeepHR Journey | 把入转调离、材料审核、员工服务变成标准旅程 |
| 教育 / 教务 | 深教 | DeepEdu Journey | 把教务咨询、报名、学籍、缴费流程变成图卡旅程 |
| 制造 / 质检 | 深检 | DeepQuality Journey | 把质检、巡检、设备操作标准化为可执行检查旅程 |
| 门店 / 零售 | 深店 | DeepStore Journey | 让门店新人按标准流程接待、售后、盘点、开闭店 |
| 园区 / 物业 | 深园 | DeepPark Journey | 把园区服务、物业报修、访客、设备巡检变成旅程 |
| 法务 / 合规 | 深法 | DeepCompliance Journey | 把合规判断、材料检查、风险确认变成受控旅程 |
| 软件厂商客户成功 | 深用 | DeepUse Journey | 让客户不会用系统时，按图卡完成真实任务 |
| 通用企业内训 | 深训 | DeepTraining Journey | 把培训内容转成现场可用的业务陪跑旅程 |
| 通用业务办理 | 深办 | DeepProcess Journey | 把复杂业务办理过程转成标准旅程包 |

---

## 3. 母平台与行业版关系

### 3.1 平台层

```text
DeepJourney Platform
  ├─ Studio 编排中心
  ├─ Coach 前台助手
  ├─ JourneyPackage Runtime
  ├─ OCGS Gate Runtime
  ├─ RiskPolicy Engine
  ├─ LostRecovery Engine
  └─ Trace / Audit Engine
```

这是技术和产品底座。

---

### 3.2 行业版层

```text
DeepGov Journey
DeepTax Journey
DeepBank Journey
DeepMed Journey
DeepService Journey
DeepHR Journey
...
```

行业版不是重新开发一套系统，而是：

```text
1. 复用 DeepJourney 平台；
2. 使用行业词典；
3. 使用行业模板；
4. 使用行业旅程包；
5. 使用行业风险规则；
6. 使用行业案例；
7. 使用行业销售话术。
```

---

### 3.3 组件层

每个行业版可以拆为：

```text
行业 Studio：
  给专家 / 管理员编排旅程包。

行业 Coach：
  给前台 / 新人 / 一线员工使用。

行业 JourneyPackage：
  标准业务旅程包。

行业 Template Library：
  行业模板库。

行业 RiskPolicy：
  行业风险策略。
```

例如税务版：

```text
DeepTax Studio
DeepTax Coach
DeepTax JourneyPackage
DeepTax Template Library
DeepTax RiskPolicy
```

中文：

```text
深税 Studio
深税 Coach
深税业务旅程包
深税模板库
深税风险策略
```

---

## 4. 各行业版定位细化

## 4.1 深政 DeepGov Journey

### 目标场景

```text
政务大厅
便民服务中心
行政审批窗口
社区服务中心
政务热线
```

### 核心痛点

```text
1. 新人窗口人员不熟业务；
2. 政策变化快；
3. 群众问题复杂；
4. 投诉风险高；
5. 老员工被反复打扰；
6. 不同窗口回答不一致。
```

### 产品定位

> **深政，是面向政务窗口的一线业务旅程系统，把政策、材料、系统操作和标准话术变成可执行图卡，让新人也能按专家路径办事。**

### 典型旅程包

```text
1. 居民证件办理旅程；
2. 社保咨询旅程；
3. 材料预审旅程；
4. 政策咨询分流旅程；
5. 行政审批材料检查旅程；
6. 投诉接待旅程。
```

---

## 4.2 深税 DeepTax Journey

### 目标场景

```text
税务局窗口
税务咨询热线
企业办税服务厅
税务代理机构
```

### 核心痛点

```text
1. 政策复杂；
2. 表单多；
3. 新人容易答错；
4. 企业客户问题细；
5. 政策更新后培训滞后；
6. 高风险答复需要留痕。
```

### 产品定位

> **深税，把税务专家经验封装成办税业务旅程包，让新员工按图卡完成咨询、材料审核和系统操作。**

### 典型旅程包

```text
1. 发票核验旅程；
2. 企业新办税务登记旅程；
3. 申报异常处理旅程；
4. 税收优惠资格判断旅程；
5. 材料补正旅程；
6. 政策咨询标准答复旅程。
```

---

## 4.3 深银 DeepBank Journey

### 目标场景

```text
银行柜台
客户经理
远程银行客服
普惠金融服务
```

### 核心痛点

```text
1. 合规要求高；
2. 业务办理步骤多；
3. 客户材料判断复杂；
4. 风险提示必须准确；
5. 新柜员压力大；
6. 留痕要求高。
```

### 产品定位

> **深银，是面向银行柜面与客户服务的一线业务旅程系统，让柜员按合规门禁办理业务，降低差错和风险。**

### 典型旅程包

```text
1. 开户材料审核旅程；
2. 客户身份核验旅程；
3. 产品适当性提示旅程；
4. 反洗钱异常提醒旅程；
5. 账户变更业务旅程；
6. 客户投诉处理旅程。
```

---

## 4.4 深保 DeepInsurance Journey

### 目标场景

```text
保险客服
理赔初审
核保辅助
代理人培训
客户服务中心
```

### 产品定位

> **深保，把核保、理赔、保全、客服等复杂规则转成标准业务旅程，帮助新人按专家路径判断和处理客户问题。**

### 典型旅程包

```text
1. 理赔材料初审旅程；
2. 保单变更旅程；
3. 客户咨询分类旅程；
4. 核保问题收集旅程；
5. 续保提醒旅程；
6. 投诉处理旅程。
```

---

## 4.5 深医 DeepMed Journey

### 目标场景

```text
医院导诊
医保窗口
收费窗口
检查预约
患者咨询
```

### 产品定位

> **深医，把导诊、医保、收费、检查预约等复杂路径变成可执行图卡，让窗口和导诊人员少问人、少带错路。**

### 典型旅程包

```text
1. 初诊导诊旅程；
2. 医保报销咨询旅程；
3. 检查预约旅程；
4. 收费异常处理旅程；
5. 患者材料补正旅程；
6. 科室分流旅程。
```

---

## 4.6 深客 DeepService Journey

### 目标场景

```text
企业客服中心
售后服务
在线客服
电话客服
工单中心
```

### 产品定位

> **深客，把专家客服的判断路径、话术和处理步骤变成可执行旅程，让新人客服也能稳定接待客户。**

### 典型旅程包

```text
1. 售后问题分类旅程；
2. 退款退货判断旅程；
3. 物流异常处理旅程；
4. 客户投诉安抚旅程；
5. 工单升级旅程；
6. 高风险客户话术旅程。
```

---

## 4.7 深人 DeepHR Journey

### 目标场景

```text
HR 共享服务中心
员工服务台
人事行政
入职 / 离职 / 调岗
```

### 产品定位

> **深人，把入转调离、材料审核、员工咨询、行政流程变成标准旅程，让 HR 新人按图卡处理员工服务。**

### 典型旅程包

```text
1. 新员工入职材料检查旅程；
2. 离职手续旅程；
3. 调岗流程旅程；
4. 社保公积金咨询旅程；
5. 合同续签旅程；
6. 证明开具旅程。
```

---

## 4.8 深检 DeepQuality Journey

### 目标场景

```text
制造业质检
设备巡检
工艺执行
安全检查
现场作业
```

### 产品定位

> **深检，把质检、巡检、设备操作和安全检查标准变成可执行检查旅程，降低新人漏检和误操作。**

### 典型旅程包

```text
1. 入库质检旅程；
2. 设备点检旅程；
3. 安全巡检旅程；
4. 工艺参数检查旅程；
5. 异常上报旅程；
6. 返工判断旅程。
```

---

## 4.9 深用 DeepUse Journey

### 目标场景

```text
软件厂商
SaaS 客户成功
企业软件培训
复杂后台系统
```

### 产品定位

> **深用，把软件功能使用过程变成图卡说明书，让客户不会用系统时也能按图完成真实任务。**

它与“善用”接近，但偏企业版 / 厂商版。

典型旅程包：

```text
1. 创建第一条客户记录；
2. 导入数据；
3. 配置权限；
4. 生成报表；
5. 创建审批流；
6. 完成首次发布。
```

---

## 5. 行业版命名规则建议

### 5.1 对内命名

使用统一母平台：

```text
DeepJourney
```

对象命名：

```text
DeepJourney.Studio
DeepJourney.Coach
DeepJourney.Package
DeepJourney.Runtime
```

行业字段：

```text
industry = gov | tax | bank | insurance | med | service | hr | quality | use
```

---

### 5.2 对外命名

按行业命名：

```text
深政
深税
深银
深保
深医
深客
深人
深检
深用
```

英文：

```text
DeepGov
DeepTax
DeepBank
DeepInsurance
DeepMed
DeepService
DeepHR
DeepQuality
DeepUse
```

---

### 5.3 版本命名

```text
深税 Coach
深税 Studio
深税旅程包
深税模板库
```

不要对外只说：

```text
DeepJourney 企业版
```

应说：

```text
深税：税务一线业务旅程系统
```

或：

```text
深政：政务窗口专家能力旅程系统
```

---

## 6. 行业版与销售话术

### 6.1 通用母话术

> **把专家经验变成一线员工可执行的业务旅程。**

### 6.2 政务话术

> **让窗口新人按图办事，少问人、少跑错、少投诉。**

### 6.3 税务话术

> **政策变了不用反复培训，前台按最新旅程接待和办理。**

### 6.4 银行话术

> **让柜员按合规门禁办业务，关键风险有确认，执行过程可留痕。**

### 6.5 客服话术

> **把金牌客服的判断路径变成新人也能使用的接待旅程。**

### 6.6 软件厂商话术

> **客户不会用系统时，不再只发文档和视频，而是给他一套可播放的任务图卡。**

---

## 7. 行业模板库

每个行业版应有自己的 Template Library。

### 7.1 深税模板库

```text
发票核验模板
材料补正模板
政策咨询模板
异常申报模板
优惠资格判断模板
```

### 7.2 深政模板库

```text
材料预审模板
窗口接待模板
政策分流模板
投诉处理模板
审批补正模板
```

### 7.3 深客模板库

```text
售后分类模板
退款判断模板
物流异常模板
投诉安抚模板
工单升级模板
```

### 7.4 深用模板库

```text
首次配置模板
数据导入模板
权限设置模板
报表生成模板
审批流创建模板
```

---

## 8. 行业版数据字段差异

虽然底层 Schema 一致，但行业字段不同。

### 8.1 税务版额外字段

```text
policy_version
taxpayer_type
invoice_type
declaration_period
risk_basis
```

### 8.2 政务版额外字段

```text
service_item_code
material_list_version
citizen_type
approval_level
complaint_risk
```

### 8.3 银行版额外字段

```text
customer_risk_level
kyc_status
product_type
compliance_rule_version
audit_required
```

### 8.4 客服版额外字段

```text
customer_level
issue_category
sla_level
emotion_level
ticket_priority
```

### 8.5 软件厂商版额外字段

```text
software_version
module_key
target_screen
user_role
feature_flag
```

---

## 9. 行业版落地优先级建议

### 第一优先：深用 / DeepUse

原因：

```text
1. 与善用和软件图卡说明书最接近；
2. 不需要复杂行业合规；
3. 可先服务自己的软件；
4. 易做 Demo；
5. 可转向软件厂商客户成功场景。
```

### 第二优先：深客 / DeepService

原因：

```text
1. 客服场景高频；
2. 新人培训痛点明显；
3. 话术和分支容易结构化；
4. 可展示“专家能力复制”。
```

### 第三优先：深税 / DeepTax 或 深政 / DeepGov

原因：

```text
1. 价值高；
2. 但销售门槛和合规门槛高；
3. 适合作为中后期样板。
```

### 第四优先：深检 / DeepQuality

原因：

```text
1. 现场执行强；
2. 可与图卡、检查表结合；
3. 但需要行业素材和客户场景。
```

---

## 10. 与原文件的修正关系

此前文件中使用：

```text
DeepJourney 企业版
```

作为统一产品名。

本文件修正为：

```text
DeepJourney 是母平台名；
具体行业应使用行业分版名。
```

因此后续文档中应这样写：

```text
DeepJourney 平台：
  通用底座。

深税 / DeepTax：
  税务行业版。

深政 / DeepGov：
  政务行业版。

深客 / DeepService：
  客服行业版。

深用 / DeepUse：
  软件厂商 / 软件使用行业版。
```

---

## 11. 新增到 OCGS 核心产品线总览中的分类

OCGS 核心产品线应改为：

```text
OCGS 方法论 / 内核
  ├─ OCGS-se
  ├─ OCGS-Delphi
  ├─ DeepJourney Platform
  │    ├─ 深用 DeepUse
  │    ├─ 深客 DeepService
  │    ├─ 深政 DeepGov
  │    ├─ 深税 DeepTax
  │    ├─ 深银 DeepBank
  │    ├─ 深医 DeepMed
  │    ├─ 深人 DeepHR
  │    └─ 深检 DeepQuality
  └─ DeepUITest
```

---

## 12. 一句话总结

> DeepJourney 不应只作为一个泛泛的企业版产品名对外销售。它应作为 OCGS 企业旅程平台的母名，而在各行业落地时使用不同的行业产品名，如深税、深政、深客、深用、深银、深医、深检等。底层 Schema、Studio、Coach、OCGS Runtime 是统一的，但行业词典、旅程模板、风险规则、销售话术和产品命名必须行业化。
