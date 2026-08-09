"""
可鉴 · 决策场景样本库生成器
============================
自动生成 100+ 真实决策场景，覆盖各行业/领域

输出格式：JSONL（每行一个决策问题对象）

使用方法：
    python generate_samples.py --count 100 --output samples.jsonl
"""

import argparse
import json
from typing import List, Dict
from datetime import datetime


# Template generators by domain
DOMAIN_TEMPLATES = {
    "strategic": [
        "是否要从 X 个门店扩展到 Y 个门店？预算 Z 万元，周期 N 年。",
        "是否应该进入新市场？目标城市是 {city}，预期投资 {amount} 万。",
        "产品线是否要扩张？新增 {product_type}，预计增加{n}%营收。",
        "是否要进行数字化转型？当前业务仍盈利，但增长乏力。",
        "是否要放弃传统渠道，全面转向线上销售？",
    ],
    "investment": [
        "是否接受风险投资机构的融资提议？估值 X 千万，出让 Y%股权。",
        "是否要回购股票？当前股价低位，但有资金占用风险。",
        "是否要投资自动化设备？成本 X 万，预计节省 Y%人工。",
        "是否要将闲散资金投入理财？年化收益 X%，但流动性受限。",
        "是否要购买商业地产出租？现金流稳定，但回报周期长。",
    ],
    "personnel": [
        "是否要裁掉业绩最差的团队？影响士气，但能节省成本。",
        "是否要引入外部高管？薪资高，但可能破坏内部文化。",
        "是否要全面推行远程办公？灵活性提升，但协作效率下降。",
        "是否要提高薪酬标准以保持竞争力？成本增加 X%，但留存率提升。",
        "是否要推行股权激励？绑定核心人才，但稀释股东权益。",
    ],
    "procurement": [
        "是否更换供应商？A 厂质量更好但价格高 20%。",
        "是否要建立自有供应链？初始投入大，但长期成本低。",
        "是否要集中采购以降低成本？单点故障风险增加。",
        "是否要外包非核心业务？专注主业，但质量控制难度增加。",
        "是否要采用租赁模式替代购买？减少资本支出，但总成本更高。",
    ],
    "marketing": [
        "是否要大举投入广告投放？ROI 不确定，但品牌曝光快速提升。",
        "是否要建立私域流量池？初期投入大，但用户粘性高。",
        "是否要赞助大型活动？成本高，但品牌价值提升明显。",
        "是否要采用 KOL 营销？效果难量化，但传播力强。",
        "是否要提高定价策略？利润空间增加，但销量可能下滑。",
    ],
}


def generate_problem(template: str, domain: str) -> Dict[str, str]:
    """根据模板生成具体问题"""
    import random
    from string import ascii_uppercase
    
    # Random parameter injection
    params = {
        "X": random.randint(10, 100),
        "Y": random.randint(5, 50),
        "Z": random.randint(100, 5000),
        "N": random.randint(1, 3),
        "city": random.choice(["北京", "上海", "深圳", "杭州", "成都", "广州"]),
        "amount": random.randint(500, 5000),
        "product_type": random.choice(["智能硬件", "软件服务", "内容订阅", "IoT 设备", "云服务"]),
        "n": random.randint(10, 50),
        "product_name": " ".join([random.choice(ascii_uppercase) for _ in range(3)]),
    }
    
    result = template.format(**params)
    
    return {
        "id": f"DEC-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{random.randint(1000, 9999)}",
        "domain": domain,
        "scenario": result,
        "difficulty": random.choice(["easy", "medium", "hard"]),
        "stakeholders": random.sample(["CEO", "CFO", "CTO", "CMO", "员工代表"], k=random.randint(2, 4)),
        "estimated_complexity": random.randint(1, 5),
        "recommended_template": domain
    }


def main():
    parser = argparse.ArgumentParser(description="可鉴 · 决策场景样本库生成器")
    parser.add_argument("--count", type=int, default=100, help="生成样本数量")
    parser.add_argument("--output", type=str, default="samples.jsonl", help="输出文件路径")
    parser.add_argument("--seed", type=int, default=42, help="随机种子")
    
    args = parser.parse_args()
    
    import random
    random.seed(args.seed)
    
    domains = list(DOMAIN_TEMPLATES.keys())
    all_templates = []
    for domain, templates in DOMAIN_TEMPLATES.items():
        for template in templates:
            all_templates.append((domain, template))
    
    samples = []
    for i in range(args.count):
        domain, template = all_templates[i % len(all_templates)]
        sample = generate_problem(template, domain)
        samples.append(sample)
    
    # Save to JSONL
    with open(args.output, "w", encoding="utf-8") as f:
        for sample in samples:
            f.write(json.dumps(sample, ensure_ascii=False) + "\n")
    
    # Summary
    domain_counts = {}
    difficulty_counts = {}
    for s in samples:
        domain_counts[s["domain"]] = domain_counts.get(s["domain"], 0) + 1
        difficulty_counts[s["difficulty"]] = difficulty_counts.get(s["difficulty"], 0) + 1
    
    print(f"\n{'='*60}")
    print("📦 决策样本库生成完成")
    print(f"{'='*60}")
    print(f"总数：{args.count}")
    print(f"输出：{args.output}")
    print(f"\n按领域分布:")
    for domain, count in sorted(domain_counts.items()):
        print(f"  {domain}: {count}")
    print(f"\n按难度分布:")
    for diff, count in sorted(difficulty_counts.items()):
        print(f"  {diff}: {count}")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    main()
