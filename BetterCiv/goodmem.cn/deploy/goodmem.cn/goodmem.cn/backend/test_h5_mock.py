import json
from pathlib import Path

from fastapi.testclient import TestClient

import main


def check(name: str, ok: bool, detail: str = "") -> tuple[bool, str]:
    mark = "[PASS]" if ok else "[FAIL]"
    line = f"{mark} {name}"
    if not ok and detail:
        line += f" -> {detail}"
    print(line)
    return ok, line


def main_test() -> int:
    passed = 0
    failed = 0

    with TestClient(main.app) as client:
        route_cases = [
            ("/", "index"),
            ("/break", "break"),
            ("/break?view=pay&sku=system", "break pay"),
            ("/break?view=post&sku=archive", "break post"),
            ("/return", "return"),
            ("/return?view=pay&sku=annual", "return pay"),
            ("/return?view=post&sku=monthly", "return post"),
            ("/wsh.html", "wsh html"),
            ("/static/wsh-config.js", "wsh config"),
            ("/reader.html", "reader"),
            ("/static/wsm-config.js", "config"),
        ]

        for path, label in route_cases:
            response = client.get(path)
            ok, _ = check(f"GET {label} -> 200", response.status_code == 200, str(response.status_code))
            passed += int(ok)
            failed += int(not ok)

        index_html = client.get("/break?view=pay&sku=system").text
        index_checks = [
            ("pay page has 5-question copy", "5题，先看你现在最像哪种锅�? in index_html),
            ("pay page has equal-SKU copy", "三档等权陈列" in index_html),
            ("pay page has payment flow section", "付款后流�? in index_html),
            ("pay page has sticky pay bar", "sticky-pay-bar" in index_html),
            ("pay page has formal payment wording", "微信 H5 支付" in index_html),
            ("pay page has review path section", "申报展示路径" in index_html),
        ]
        for name, ok in index_checks:
            ok, _ = check(name, ok)
            passed += int(ok)
            failed += int(not ok)

        reader_html = client.get("/reader.html").text
        reader_checks = [
            ("reader page has neutral title", "思维越狱 | 阅读入口" in reader_html),
            ("reader page no prototype wording", "原型" not in reader_html and "占位" not in reader_html),
        ]
        for name, ok in reader_checks:
            ok, _ = check(name, ok)
            passed += int(ok)
            failed += int(not ok)

        wsh_html = client.get("/return?view=pay&sku=annual").text
        wsh_checks = [
            ("wsh page has discomfort copy", "你不是完全崩�? in wsh_html),
            ("wsh page has current deviation report copy", "当下偏移报告" in wsh_html),
            ("wsh page has annual target copy", "年度靶心建立" in wsh_html),
            ("wsh page has monthly review copy", "月度纠偏" in wsh_html),
        ]
        for name, ok in wsh_checks:
            ok, _ = check(name, ok)
            passed += int(ok)
            failed += int(not ok)

        wsh_config = client.get("/static/wsh-config.js").text
        wsh_config_checks = [
            ("wsh config has reset package copy", "小步回正�? in wsh_config),
            ("wsh config has annual target package copy", "年度靶心建立" in wsh_config),
            ("wsh config has monthly review package copy", "月度纠偏" in wsh_config),
        ]
        for name, ok in wsh_config_checks:
            ok, _ = check(name, ok)
            passed += int(ok)
            failed += int(not ok)

        config_js = client.get("/static/wsm-config.js").text
        config_checks = [
            ("config has cleaned path wording", "属于你的起始路径" in config_js),
            ("config has cleaned base wording", "长期回看型基站入�? in config_js),
            ("config has no prototype wording", "原型" not in config_js),
        ]
        for name, ok in config_checks:
            ok, _ = check(name, ok)
            passed += int(ok)
            failed += int(not ok)

        tier_cases = [
            ("emergency", 29900),
            ("system", 39900),
            ("archive", 99900),
        ]
        for tier, expected_amount in tier_cases:
            response = client.post(
                "/api/v1/pay/prepay",
                json={"product_tier": tier, "novel_key": "mindbreak"},
            )
            body = response.json()
            checks = [
                (f"prepay {tier} -> 200", response.status_code == 200, str(response.status_code)),
                (f"prepay {tier} code success", body.get("code") == "SUCCESS", json.dumps(body, ensure_ascii=False)),
                (f"prepay {tier} amount ok", body.get("amount") == expected_amount, str(body.get("amount"))),
                (f"prepay {tier} tier echo ok", body.get("product_tier") == tier, body.get("product_tier", "")),
                (f"prepay {tier} order id exists", bool(body.get("out_trade_no")), json.dumps(body, ensure_ascii=False)),
                (
                    f"prepay {tier} pay package exists",
                    body.get("pay_params", {}).get("package", "").startswith("prepay_id="),
                    json.dumps(body.get("pay_params", {}), ensure_ascii=False),
                ),
            ]
            for name, ok, detail in checks:
                ok, _ = check(name, ok, detail)
                passed += int(ok)
                failed += int(not ok)

        custom_order = "ORDER_TEST_SYSTEM_001"
        response = client.post(
            "/api/v1/pay/prepay",
            json={
                "product_tier": "system",
                "novel_key": "mindbreak",
                "out_trade_no": custom_order,
            },
        )
        body = response.json()
        custom_checks = [
            ("prepay custom order -> 200", response.status_code == 200, str(response.status_code)),
            ("prepay custom order echoed", body.get("out_trade_no") == custom_order, body.get("out_trade_no", "")),
        ]
        for name, ok, detail in custom_checks:
            ok, _ = check(name, ok, detail)
            passed += int(ok)
            failed += int(not ok)

        bad_response = client.post(
            "/api/v1/pay/prepay",
            json={"product_tier": "bad-tier", "novel_key": "mindbreak"},
        )
        bad_body = bad_response.json()
        bad_checks = [
            ("prepay invalid tier -> 400", bad_response.status_code == 400, str(bad_response.status_code)),
            ("prepay invalid tier detail", bad_body.get("detail") == "Invalid product tier", json.dumps(bad_body, ensure_ascii=False)),
        ]
        for name, ok, detail in bad_checks:
            ok, _ = check(name, ok, detail)
            passed += int(ok)
            failed += int(not ok)

    print(f"\nTotal: {passed + failed} | PASS: {passed} | FAIL: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main_test())
