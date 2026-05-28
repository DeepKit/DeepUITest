from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import app


def test_deepbase_client_contract_smoke() -> None:
    client = TestClient(app)

    login = client.post(
        "/dk/auth/login",
        json={
            "login_type": "device_anonymous",
            "app_id": "deeplaunch",
            "device_id": "smoke-device-001",
        },
    )
    assert login.status_code == 200, login.text
    session = login.json()
    token = session["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    products = client.get("/dk/commerce/products", params={"app_id": "deeplaunch"})
    assert products.status_code == 200, products.text
    product_id = products.json()["products"][0]["product_id"]

    order = client.post(
        "/dk/commerce/orders",
        headers=headers,
        json={"user_id": session["user_id"], "app_id": "deeplaunch", "product_id": product_id},
    )
    assert order.status_code == 200, order.text
    order_body = order.json()

    intent = client.post(
        "/dk/commerce/payments/intents",
        headers={**headers, "Idempotency-Key": "smoke-intent-001"},
        json={"order_id": order_body["order_id"], "provider": "manual", "channel": "manual"},
    )
    assert intent.status_code == 200, intent.text
    assert intent.json()["success"] is True

    paid = client.post(
        "/dk/commerce/payments/manual/confirm",
        headers=headers,
        json={
            "out_trade_no": order_body["out_trade_no"],
            "provider_trade_no": "manual-smoke-001",
            "amount_minor": order_body["amount_minor"],
            "currency": order_body["currency"],
        },
    )
    assert paid.status_code == 200, paid.text
    assert paid.json()["status"] == "paid"

    entitlements = client.get("/dk/commerce/entitlements", headers=headers, params={"app_id": "deeplaunch"})
    assert entitlements.status_code == 200, entitlements.text
    code = entitlements.json()["items"][0]["code"]

    consumed = client.post(
        "/dk/commerce/entitlements/consume",
        headers={**headers, "Idempotency-Key": "smoke-consume-001"},
        json={"app_id": "deeplaunch", "entitlement_code": code, "feature_code": "pro", "quantity": 1},
    )
    assert consumed.status_code == 200, consumed.text
    assert consumed.json()["success"] is True

    snapshot = client.post(
        "/dk/license/snapshot/issue",
        headers=headers,
        json={"app_id": "deeplaunch", "device_id": "smoke-device-001"},
    )
    assert snapshot.status_code == 200, snapshot.text
    assert snapshot.json()["signature"]
    assert snapshot.json()["payload"]["app_id"] == "deeplaunch"


