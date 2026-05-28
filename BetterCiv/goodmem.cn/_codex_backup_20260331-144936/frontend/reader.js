// reader.js

const API_BASE = '/api/v1'; // 根据实际部署修改
let jwtToken = null;
let clientUUID = localStorage.getItem('goodmem_uuid');
let passcode = localStorage.getItem('goodmem_token');
let uiConfig = {};
let globalCashbackStatus = 'NONE';

// C-003 Fix: 持久化到 sessionStorage，刷新不丢失
let openedArticles = new Set(JSON.parse(sessionStorage.getItem('goodmem_opened') || '[]'));

if (!clientUUID) {
    clientUUID = 'uuid_' + Math.random().toString(36).substr(2, 9);
    localStorage.setItem('goodmem_uuid', clientUUID);
}

// 1. 初始�?async function init() {
    if (!passcode) {
        alert("未检测到秘钥�?);
        window.location.href = '/';
        return;
    }
    await loadUIConfig();
    // C-004 Fix: 优先使用首页缓存�?JWT，避免重�?auth 消耗限流配�?    const cachedJwt = sessionStorage.getItem('goodmem_jwt');
    const cachedCashback = sessionStorage.getItem('goodmem_cashback');
    if (cachedJwt) {
        jwtToken = cachedJwt;
        globalCashbackStatus = cachedCashback || 'NONE';
        sessionStorage.removeItem('goodmem_jwt'); // 一次性消费，后续由心跳续�?        sessionStorage.removeItem('goodmem_cashback');
        if (globalCashbackStatus === 'NONE') {
            const btn = document.getElementById('btn-persistent-cashback');
            if (btn) btn.style.display = 'block';
        }
    } else {
        const ok = await authenticate();
        if (!ok) return;
    }
    await loadTOC();
    renderWatermark();
    startHeartbeat();
    renderCOP();
    // 默认不直接写死，加载返回列表中第一�?}

// C-005 Fix: TOC 现在携带 cop_type，存�?map �?COP 精确高亮
let articleCopTypeMap = {}; // { article_id: cop_type }

// 加载目录�?async function loadTOC() {
    try {
        const urlParams = new URLSearchParams(window.location.search);
        const novelKey = urlParams.get('book') || 'mindbreak';
        const res = await fetch(`${API_BASE}/articles?novel_key=${novelKey}`, {
            headers: { 'Authorization': `Bearer ${jwtToken}` }
        });
        if (!res.ok) { handleErrorState(res.status); return; }
        const list = await res.json();
        articleCopTypeMap = {};
        const container = document.getElementById('article-list');
        container.innerHTML = '';
        list.forEach((item, index) => {
            const li = document.createElement('li');
            li.className = 'nav-item';
            li.dataset.articleId = item.id;
            li.dataset.copType = item.cop_type || '';
            li.innerText = item.title;
            articleCopTypeMap[item.id] = item.cop_type || null;
            li.onclick = () => {
                document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
                li.classList.add('active');
                loadArticle(item.id);
            };
            container.appendChild(li);
            // 默认加载第一�?            if (index === 0) {
                li.classList.add('active');
                loadArticle(item.id);
            }
        });
    } catch(e) {
        console.error("加载目录树失�?, e);
    }
}

// 2. 加载 UI 配置
async function loadUIConfig() {
    try {
        const res = await fetch(`${API_BASE}/config/ui-strings`);
        uiConfig = await res.json();
    } catch(e) {
        console.error("加载UI配置失败", e);
    }
}

function showAlert(msg) {
    const dialog = document.getElementById('alert-modal');
    document.getElementById('alert-msg').innerText = msg;
    dialog.showModal();
}

// 3. 握手�?JWT �?C-001 Fix: 明确返回 true/false 控制 init 流程
async function authenticate() {
    try {
        const res = await fetch(`${API_BASE}/auth`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({ passcode, client_uuid: clientUUID })
        });

        // C-001 Fix: 402 警告后显示提示，但仍需判断后续流程
        if (res.status === 402) {
            alert(uiConfig.warning_msg || "系统警告：频繁切换设�?);
            // 402 时后端仍不能正常完成 auth，停止初始化
            handleErrorState(res.status);
            return false;
        }

        const data = await res.json();
        if (res.ok) {
            jwtToken = data.access_token;
            globalCashbackStatus = data.cashback_status || 'NONE';
            if (globalCashbackStatus === 'NONE') {
                const btn = document.getElementById('btn-persistent-cashback');
                if (btn) btn.style.display = 'block';
            }
            return true;
        } else {
            handleErrorState(res.status);
            return false;
        }
    } catch(e) {
        console.error(e);
        return false;
    }
}

// 4. 心跳引擎
function startHeartbeat() {
    setInterval(async () => {
        if (!jwtToken) return;
        try {
            const res = await fetch(`${API_BASE}/heartbeat`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${jwtToken}`
                },
                body: JSON.stringify({ client_uuid: clientUUID })
            });

            if (res.ok) {
                const data = await res.json();
                jwtToken = data.access_token; // 更新 60 秒的短效 JWT
            } else {
                handleErrorState(res.status);
            }
        } catch(e) {}
    }, 30000); // 30秒发一�?}

function handleErrorState(status) {
    jwtToken = null; // 切断后续请求许可
    document.getElementById('article-body').innerHTML = ''; // 物理清空正文
    if (status === 401) {
        showAlert(uiConfig.kicked_msg || "您被挤下�?);
    } else if (status === 403) {
        showAlert(uiConfig.banned_msg || "账号已被销�?);
    } else {
        showAlert("系统异常认证失败�?);
    }
}

// 5. CRC32 简单实�?(完整性容�?
function crc32(str) {
    let crc = 0 ^ (-1);
    for (let i = 0; i < str.length; i++) {
        crc = (crc >>> 8) ^ crcTable[(crc ^ str.charCodeAt(i)) & 0xFF];
    }
    return (crc ^ (-1)) >>> 0;
}
let crcTable = [];
for (let n =0; n < 256; n++) {
    let c = n;
    for (let k =0; k < 8; k++) { c = ((c&1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1)); }
    crcTable[n] = c;
}

// 6. 核心混淆分片拉取与渲染（注意：此方案�?混淆'而非'端到端加�?，不防高级爬虫，但能挡住99%的低级脚本）
async function loadArticle(articleId, retries = 0) {
    if (!jwtToken) return;
    
    document.getElementById('article-title').innerHTML = "正在拉取碎片...";
    document.getElementById('article-body').innerHTML = "";
    document.getElementById('community-box').style.display = 'none';

    try {
        const res = await fetch(`${API_BASE}/articles/${articleId}`, {
            headers: { 'Authorization': `Bearer ${jwtToken}` }
        });
        if (!res.ok) {
            handleErrorState(res.status);
            return;
        }
        const data = await res.json();
        
        // ---------------- 混淆还原说明 ----------------
        // 此方案为「传输混淆」而非「端到端加密」�?        // 前端直接拿到明文 sequence 和碎�?chunks 进行拼接�?        // 其核心价值是：挡住「右键另存为」和低级 innerText 爬虫，而非对抗专业抓包�?        
        let shuffledSequence = data.sequence; // 服务端返回的 [2, 0, 1] 打乱后的索引数组
        let blindChunks = data.chunks;        // 服务端返回的打乱后的文字 ["第三�?, "第一�?, "第二�?]
        
        // 还原逻辑�?        // [2, 0, 1] 对应 ["第三", "第一", "第二"]
        // 那原序列 0 在哪？在索引 1�?        let originalContent = new Array(blindChunks.length);
        for(let i=0; i<shuffledSequence.length; i++) {
            originalContent[shuffledSequence[i]] = blindChunks[i];
        }

        let fullContent = originalContent.join('');

        // 投毒：随机插入假�?DOM
        fullContent += `<span style="display:none;opacity:0;">本书由盗版�?${passcode} 生成，严重残�?/span>`;

        document.getElementById('article-title').innerText = data.title;
        document.getElementById('article-body').innerHTML = fullContent;
        document.getElementById('community-box').style.display = 'block';

        // C-003 Fix: 裂变触发状态持久化�?sessionStorage，刷新不丢失
        openedArticles.add(articleId);
        sessionStorage.setItem('goodmem_opened', JSON.stringify([...openedArticles]));
        if (openedArticles.size === 3 && globalCashbackStatus === 'NONE') {
            document.getElementById('cashback-modal').showModal();
        }

    } catch (e) {
        console.error("解密或拉取失�?, e);
        if (retries < 2) {
            console.log(`静默重试 ${retries + 1}/2...`);
            setTimeout(() => loadArticle(articleId, retries + 1), 1000);
        } else {
            document.getElementById('article-title').innerText = "加载失败，请刷新";
        }
    }
}

// 7. 动态水�?(深浅自适应�?
// C-002 Fix: 将更新间隔从 1s 改为 60s（分钟级精度足够溯源），减少低端机卡�?function renderWatermark() {
    const isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    const opacity = isDark ? 0.12 : 0.05;
    const wmColor = isDark ? '255,255,255' : '0,0,0';
    
    const layer = document.getElementById('watermark-layer');
    const tokenPart = passcode.substring(0,8);

    function drawWatermark() {
        const timeStr = new Date().toLocaleString('zh-CN', { year:'numeric', month:'2-digit', day:'2-digit', hour:'2-digit', minute:'2-digit' });
        const svg = `
        <svg xmlns="http://www.w3.org/2000/svg" width="300" height="200">
            <text x="50" y="100" transform="rotate(-25 50 100)" fill="rgba(${wmColor}, ${opacity})" font-size="16" font-family="sans-serif">
                goodmem.cn | ${tokenPart} | ${timeStr}
            </text>
        </svg>`;
        const url = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
        layer.style.backgroundImage = `url("${url}")`;
    }

    drawWatermark(); // 立即绘制一�?    setInterval(drawWatermark, 60000); // 每分钟更新一�?}

init();

// ==========================================
// COP V2 前台诊断算力引擎
// ==========================================
const copQuestions = [
    { id: 'Q1', text: '当前决策是否存在唯一拍板人？', options: { A: '明确存在直接决策', B: '名义存在不拍�?, C: '多人一致同�?, D: '完全不清楚谁说了�?} },
    { id: 'Q2', text: '当前推进卡住的核心表现是�?, options: { A: '大家都同意但结果�?, B: '两方互相等待优先', C: '需求不断增加无边界', D: '已投入很多继续加�?} },
    { id: 'Q3', text: '团队中是否允许明确反对？', options: { A: '公开反对不影�?, B: '私下说公开犹豫', C: '很少有人反对', D: '基本不可能反�?} },
    { id: 'Q4', text: '是否存在“必须先拿到对方条件”的依赖�?, options: { A: '无依�?, B: '单向依赖', C: '双向依赖', D: '多方循环依赖'} },
    { id: 'Q5', text: '决策是否受“已投入资源”影响？', options: { A: '完全不考虑', B: '有一点影�?, C: '明显影响', D: '为了不亏才继�?} },
    { id: 'Q6', text: '能否看到大量失败案例�?, options: { A: '清楚看到', B: '偶尔看到', C: '大多数是成功', D: '几乎全是成功'} },
    { id: 'Q7', text: '策略是否可能被“利用规则套利”？', options: { A: '基本不可�?, B: '有一定风�?, C: '很容易利�?, D: '已经被利�?} },
    { id: 'Q8', text: '是否存在明确“停止条件”？', options: { A: '有清晰停止线', B: '模糊标准', C: '基本�?, D: '一直在拖延'} },
    { id: 'Q9', text: '是否存在“外部强制约束”？', options: { A: '强约�?, B: '有但不稳�?, C: '基本�?, D: '自由但混�?} }
];

const copWeights = {
  "Q1": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":2,"B":1,"C":0,"D":0}, "C": {"A":2,"B":3,"C":0,"D":0}, "D": {"A":3,"B":2,"C":0,"D":0} },
  "Q2": { "A": {"A":4,"B":0,"C":0,"D":0}, "B": {"A":0,"B":4,"C":0,"D":0}, "C": {"A":0,"B":0,"C":4,"D":0}, "D": {"A":0,"B":0,"C":0,"D":4} },
  "Q3": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":1,"B":0,"C":0,"D":0}, "C": {"A":2,"B":0,"C":0,"D":0}, "D": {"A":3,"B":0,"C":0,"D":0} },
  "Q4": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":0,"B":1,"C":0,"D":0}, "C": {"A":0,"B":3,"C":0,"D":0}, "D": {"A":0,"B":4,"C":0,"D":0} },
  "Q5": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":0,"B":0,"C":0,"D":1}, "C": {"A":0,"B":0,"C":0,"D":2}, "D": {"A":0,"B":0,"C":0,"D":4} },
  "Q6": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":0,"B":0,"C":0,"D":0}, "C": {"A":0,"B":0,"C":0,"D":1}, "D": {"A":0,"B":0,"C":0,"D":2} },
  "Q7": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":0,"B":0,"C":1,"D":0}, "C": {"A":0,"B":0,"C":2,"D":0}, "D": {"A":0,"B":0,"C":3,"D":0} },
  "Q8": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":0,"B":0,"C":1,"D":0}, "C": {"A":0,"B":0,"C":3,"D":0}, "D": {"A":0,"B":0,"C":4,"D":0} },
  "Q9": { "A": {"A":0,"B":0,"C":0,"D":0}, "B": {"A":1,"B":1,"C":0,"D":0}, "C": {"A":2,"B":2,"C":0,"D":0}, "D": {"A":3,"B":2,"C":0,"D":0} }
};

function renderCOP() {
    const c = document.getElementById('cop-questions-container');
    if (!c) return;
    let html = '';
    copQuestions.forEach((q, i) => {
        html += `<div class="cop-question" style="margin-bottom:15px; background:rgba(128,128,128,0.05); padding:15px; border-radius:4px;">
            <strong style="display:block;margin-bottom:10px;color:#fff;">Q${i+1}. ${q.text}</strong>
            <div class="cop-options">`;
        for(const k in q.options) {
            html += `<label style="display:inline-block; margin-right:10px; margin-bottom:5px; font-size:0.9rem;">
                <input type="radio" name="${q.id}" value="${k}"> ${q.options[k]}
            </label>`;
        }
        html += `</div></div>`;
    });
    c.innerHTML = html;
}

function submitCOP() {
    let unans = false;
    let answers = {};
    copQuestions.forEach(q => {
        const input = document.querySelector(`input[name="${q.id}"]:checked`);
        if(!input) unans = true;
        else answers[q.id] = input.value;
    });
    
    if(unans) { alert("诊断终端错误：输入样本不足，请答完所�?道题�?); return; }
    
    // 1. 累加权重
    let score = {A:0, B:0, C:0, D:0};
    for(const q in answers) {
        let sel = answers[q];
        let w = copWeights[q][sel];
        for(let t in score) { score[t] += w[t]; }
    }
    
    // 2. 冲突解决与强制覆�?    let primary = Object.keys(score).reduce((a,b)=>score[a]>score[b]?a:b);
    if(answers['Q4'] === 'D') primary = 'B';
    else if(answers['Q5'] === 'D' && answers['Q2'] === 'D') primary = 'D';
    else if(answers['Q2'] === 'A' && ['C','D'].includes(answers['Q3'])) primary = 'A';
    
    // 3. 计算离散摩擦风险
    let total = score.A + score.B + score.C + score.D;
    let prob = total > 0 ? (score[primary]/total).toFixed(2) : 0;
    let risk = prob > 0.6 ? '🔴 重度高危' : (prob > 0.4 ? '🟡 中度摩擦' : '🟢 低感量耗散');
    
    const TypeNames = {A: '共识幻觉�?, B: '死锁�?, C: '阈值失效型', D: '沉没成本�?};
    
    // 4. 输出诊疗�?    const resBox = document.getElementById('cop-result');
    resBox.style.display = 'block';
    resBox.innerHTML = `
        <h3 style="margin-top:0; color:#f8c102;">🧾 LMM 结构诊断核批报告</h3>
        <div style="font-size:1.1rem; margin-bottom:5px;"><strong>主结构判定：</strong> Type ${primary} (${TypeNames[primary]})</div>
        <div style="font-size:1.1rem; margin-bottom:5px;"><strong>系统摩擦值：</strong> ${prob} (${risk})</div>
        <div style="margin-top:15px; color:#aaa; font-size:0.9rem;">指令下达：系统已截获您的组织弱点，并在左侧列�?strong style="color:#f8c102"> 强行点亮 </strong>破局方案。请即刻阅览，切断感染源�?/div>
    `;
    
    // C-005 Fix: 使用后端 cop_type 精确匹配（入库时已标注），不再依赖标题正�?    document.querySelectorAll('#article-list .nav-item').forEach(li => {
        li.style.borderLeft = '';
        li.style.backgroundColor = '';
        li.style.color = '';

        const itemCopType = li.dataset.copType; // �?data-cop-type 属性读�?        if (itemCopType && itemCopType === primary) {
            li.style.borderLeft = '4px solid #f8c102';
            li.style.backgroundColor = 'rgba(248,193,2,0.1)';
            li.style.color = '#f8c102';
        }
    });
}

// ==========================================
// Phase 5: 强制退单凭证接�?(无客服自动化流转)
// ==========================================
// 延迟助手
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function submitCashback() {
    const fileInput = document.getElementById('proof-file');
    const statusBox = document.getElementById('upload-status');
    const btn = document.getElementById('btn-upload');
    
    if (!fileInput.files.length) {
        alert("系统拒绝空节点，请上传火种播报截图�?);
        return;
    }
    
    btn.disabled = true;
    btn.innerText = "[ 系统接入�?.. ]";
    statusBox.style.display = 'block';
    statusBox.style.color = '#fff';
    statusBox.innerHTML = "> 截取物理凭证...";

    const formData = new FormData();
    formData.append('file', fileInput.files[0]);

    try {
        // 先静默向后端发图
        const uploadPromise = fetch(`${API_BASE}/cashback/upload_proof`, {
            method: 'POST',
            headers: { 'Authorization': `Bearer ${jwtToken}` },
            body: formData
        });

        // 强行施加威压动画阻塞
        await sleep(800);
        statusBox.innerHTML += "<br>> 凭证已捕获。正在执�?[256-SHA] 逆向洗写...";
        await sleep(1500);

        statusBox.innerHTML += "<br>> 激�?NLP 探针... 提取公域曝光度特�?..";
        await sleep(1800);

        statusBox.innerHTML += "<br>> <span style='color:#0f0'>痛点匹配成功</span>。您已被释放结构性死锁�?;
        await sleep(1000);

        // 此时等待真实后端响应（通常早已完成�?        const res = await uploadPromise;
        const data = await res.json();

        if (res.ok) {
            statusBox.style.color = '#0f0';
            statusBox.innerHTML += `<br><br>> [Transaction Success] <br>> ${data.message}`;
            globalCashbackStatus = 'REFUNDED_300';
            const btnP = document.getElementById('btn-persistent-cashback');
            if (btnP) btnP.style.display = 'none'; // 物理抹除常驻入口
            setTimeout(() => { document.getElementById('cashback-modal').close(); }, 5000);
        } else {
            statusBox.style.color = 'red';
            statusBox.innerHTML += `<br><br>> [Transaction Failed] <br>> ${data.detail}`;
            btn.disabled = false;
            btn.innerText = "[ 重新强制注入 ]";
        }
    } catch (e) {
        statusBox.style.color = 'red';
        statusBox.innerHTML = "> 致命错误: 无法桥接至主服务器�?;
        btn.disabled = false;
        btn.innerText = "[ 重试连接 ]";
    }
}
