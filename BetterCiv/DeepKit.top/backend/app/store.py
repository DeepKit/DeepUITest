from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from .security import new_id, token_hash


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: Optional[datetime]) -> str:
    if not dt:
        return ""
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def out_trade_no() -> str:
    return "DK" + now_utc().strftime("%Y%m%d%H%M%S") + new_id("").replace("_", "")[:10].upper()


class StoreError(Exception):
    pass


class NotFound(StoreError):
    pass


class Conflict(StoreError):
    pass


class MemoryStore:
    """Contract smoke store. Production must use PostgreSQL."""

    def __init__(self) -> None:
        self.users: dict[str, dict[str, Any]] = {}
        self.identities: dict[tuple[str, str, str], str] = {}
        self.refresh_tokens: dict[str, dict[str, Any]] = {}
        self.products: dict[tuple[str, str], dict[str, Any]] = {}
        self.orders: dict[str, dict[str, Any]] = {}
        self.orders_by_out_trade_no: dict[str, str] = {}
        self.payments: dict[str, dict[str, Any]] = {}
        self.payment_by_order: dict[str, str] = {}
        self.notifications: set[str] = set()
        self.entitlements: dict[str, dict[str, Any]] = {}
        self.consume_results: dict[str, dict[str, Any]] = {}
        self.snapshots: dict[str, dict[str, Any]] = {}
        self.seed_products()

    def seed_products(self) -> None:
        rows = [
            ("deepclip", "deepclip_pro_month", "DeepClip Pro Monthly", 1900, "deepclip.pro", 31, -1),
            ("deeplaunch", "deeplaunch_pro_year", "DeepLaunch Pro Year", 9800, "deeplaunch.pro", 365, -1),
            ("deeplaunch", "deeplaunch_pro_lifetime", "DeepLaunch Pro Lifetime", 19800, "deeplaunch.pro", 0, -1),
            ("deepdev", "deepdev_pro_month", "DeepDev Pro Monthly", 20800, "deepdev.pro", 31, -1),
            ("deepstory", "deepstory_pro_month", "DeepStory Pro Monthly", 52000, "deepstory.pro", 31, -1),
            ("deepshine", "deepshine_pro_month", "DeepShine Pro Monthly", 166600, "deepshine.pro", 31, -1),
            ("deepcompare", "deepcompare_desktop_lifetime", "DeepCompare Desktop Lifetime", 299900, "deepcompare.pro", 0, -1),
            ("deepllm", "deepllm_pro_10_ports_month", "DeepLLM Pro 10 Ports Monthly", 50000, "deepllm.pro", 31, 10),
        ]
        for app_id, product_id, name, amount, code, duration, quota in rows:
            self.products[(app_id, product_id)] = {
                "app_id": app_id,
                "product_id": product_id,
                "name": name,
                "description": "",
                "amount_minor": amount,
                "currency": "CNY",
                "entitlement_code": code,
                "entitlement_duration_days": duration,
                "initial_quota": quota,
                "is_active": True,
            }

    def ensure_user(
        self,
        provider: str,
        provider_user_id: str,
        app_id: str,
        union_id: str = "",
        display_name: str = "",
        email: str = "",
        phone: str = "",
    ) -> dict[str, Any]:
        key = (provider, provider_user_id, app_id)
        user_id = self.identities.get(key)
        timestamp = iso(now_utc())
        if not user_id:
            user_id = new_id("usr")
            self.users[user_id] = {
                "user_id": user_id,
                "display_name": display_name,
                "email": email,
                "phone": phone,
                "is_active": True,
                "created_at": timestamp,
                "updated_at": timestamp,
            }
            self.identities[key] = user_id
        return self.users[user_id]

    def get_user(self, user_id: str) -> dict[str, Any]:
        user = self.users.get(user_id)
        if not user:
            raise NotFound("User not found")
        return user

    def update_user_phone(self, user_id: str, phone: str) -> dict[str, Any]:
        user = self.users.get(user_id)
        if not user:
            raise NotFound("User not found")
        user["phone"] = phone
        user["updated_at"] = iso(now_utc())
        return user

    def save_refresh_token(self, raw_token: str, user_id: str, app_id: str, device_id: str, expires_at: datetime) -> None:
        self.refresh_tokens[token_hash(raw_token)] = {
            "user_id": user_id,
            "app_id": app_id,
            "device_id": device_id,
            "expires_at": expires_at,
            "revoked_at": None,
        }

    def use_refresh_token(self, raw_token: str) -> dict[str, Any]:
        row = self.refresh_tokens.get(token_hash(raw_token))
        if not row or row["revoked_at"] or row["expires_at"] <= now_utc():
            raise NotFound("Refresh token invalid")
        return row

    def revoke_refresh_token(self, raw_token: str) -> None:
        row = self.refresh_tokens.get(token_hash(raw_token))
        if row:
            row["revoked_at"] = now_utc()

    def list_products(self, app_id: str) -> list[dict[str, Any]]:
        return [p for p in self.products.values() if p["app_id"] == app_id and p["is_active"]]

    def create_order(self, user_id: str, app_id: str, product_id: str) -> dict[str, Any]:
        self.get_user(user_id)
        product = self.products.get((app_id, product_id))
        if not product or not product["is_active"]:
            raise NotFound("Product not found")
        order_id = new_id("ord")
        trade_no = out_trade_no()
        row = {
            "order_id": order_id,
            "user_id": user_id,
            "app_id": app_id,
            "product_id": product_id,
            "out_trade_no": trade_no,
            "title": product["name"],
            "amount_minor": product["amount_minor"],
            "currency": product["currency"],
            "status": "created",
            "created_at": iso(now_utc()),
            "paid_at": "",
        }
        self.orders[order_id] = row
        self.orders_by_out_trade_no[trade_no] = order_id
        return row

    def get_order(self, order_id: str) -> dict[str, Any]:
        order = self.orders.get(order_id)
        if not order:
            raise NotFound("Order not found")
        return order

    def create_payment(self, order_id: str, provider: str, channel: str, raw_payload: str = "") -> dict[str, Any]:
        order = self.get_order(order_id)
        existing_id = self.payment_by_order.get(order_id)
        if existing_id:
            return self.payments[existing_id]
        payment_id = new_id("pay")
        payment = {
            "payment_id": payment_id,
            "order_id": order_id,
            "provider": provider,
            "channel": channel,
            "provider_trade_no": "",
            "prepay_id": "",
            "status": "pending",
            "raw_payload": raw_payload,
            "created_at": iso(now_utc()),
            "paid_at": "",
        }
        self.payments[payment_id] = payment
        self.payment_by_order[order_id] = payment_id
        order["status"] = "paying"
        return payment

    def update_payment_intent(self, payment_id: str, prepay_id: str, raw_payload: str) -> None:
        payment = self.payments.get(payment_id)
        if payment:
            payment["prepay_id"] = prepay_id
            payment["raw_payload"] = raw_payload

    def confirm_payment(
        self,
        provider: str,
        out_trade_no_value: str,
        provider_trade_no: str,
        amount_minor: int,
        currency: str,
        raw_payload: str,
        notification_key: str,
    ) -> dict[str, Any]:
        order_id = self.orders_by_out_trade_no.get(out_trade_no_value)
        if not order_id:
            raise NotFound("Order not found")
        order = self.orders[order_id]
        if order["amount_minor"] != amount_minor or order["currency"] != currency:
            raise Conflict("Payment amount or currency mismatch")
        if notification_key in self.notifications:
            return order
        self.notifications.add(notification_key)
        payment = self.create_payment(order_id, provider, "manual" if provider == "manual" else "native", raw_payload)
        paid_at = iso(now_utc())
        payment["status"] = "paid"
        payment["provider_trade_no"] = provider_trade_no
        payment["paid_at"] = paid_at
        order["status"] = "paid"
        order["paid_at"] = paid_at
        self._grant_entitlement(order)
        return order

    def _grant_entitlement(self, order: dict[str, Any]) -> None:
        for row in self.entitlements.values():
            if row["source_order_id"] == order["order_id"]:
                return
        product = self.products[(order["app_id"], order["product_id"])]
        valid_from = now_utc()
        days = int(product["entitlement_duration_days"])
        valid_until = None if days <= 0 else valid_from + timedelta(days=days)
        entitlement_id = new_id("ent")
        self.entitlements[entitlement_id] = {
            "entitlement_id": entitlement_id,
            "user_id": order["user_id"],
            "app_id": order["app_id"],
            "product_id": order["product_id"],
            "code": product["entitlement_code"],
            "status": "active",
            "valid_from": iso(valid_from),
            "valid_until": iso(valid_until),
            "remaining_quota": product["initial_quota"],
            "source_order_id": order["order_id"],
        }

    def list_entitlements(self, user_id: str, app_id: str) -> list[dict[str, Any]]:
        return [
            e for e in self.entitlements.values()
            if e["user_id"] == user_id and e["app_id"] == app_id and e["status"] == "active"
        ]

    def consume_entitlement(
        self,
        user_id: str,
        app_id: str,
        code: str,
        feature_code: str,
        quantity: int,
        request_id: str,
    ) -> dict[str, Any]:
        if request_id and request_id in self.consume_results:
            return self.consume_results[request_id]
        candidates = [
            e for e in self.entitlements.values()
            if e["user_id"] == user_id and e["app_id"] == app_id and e["code"] == code and e["status"] == "active"
        ]
        if not candidates:
            raise NotFound("Entitlement not found")
        entitlement = candidates[0]
        remaining = int(entitlement["remaining_quota"])
        if remaining >= 0:
            if remaining < quantity:
                raise Conflict("Insufficient entitlement quota")
            remaining -= quantity
            entitlement["remaining_quota"] = remaining
            if remaining == 0:
                entitlement["status"] = "consumed"
        result = {
            "success": True,
            "entitlement_code": code,
            "remaining_quota": entitlement["remaining_quota"],
            "consumed_quantity": quantity,
            "server_time": iso(now_utc()),
        }
        if request_id:
            self.consume_results[request_id] = result
        return result

    def save_license_snapshot(self, snapshot: dict[str, Any]) -> None:
        self.snapshots[snapshot["snapshot_id"]] = snapshot

    def update_manifest(self, app_id: str, current_version: str, channel: str) -> dict[str, Any]:
        return {
            "app_id": app_id,
            "current_version": current_version,
            "channel": channel,
            "latest_version": current_version,
            "min_version": "0.0.0",
            "manifest_url": "",
            "package_url": "",
            "package_hash": "",
            "signature": "",
            "force_update": False,
            "release_notes": "",
        }
