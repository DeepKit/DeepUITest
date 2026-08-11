from __future__ import annotations

import json
from datetime import datetime, timedelta
from typing import Any, Optional

from .security import new_id, token_hash
from .store import Conflict, NotFound, iso, now_utc, out_trade_no


def _jsonb(value: str | dict[str, Any]) -> Any:
    from psycopg.types.json import Jsonb

    if isinstance(value, dict):
        return Jsonb(value)
    if not value:
        return Jsonb({})
    try:
        return Jsonb(json.loads(value))
    except json.JSONDecodeError:
        return Jsonb({"raw": value})


def _public(row: Optional[dict[str, Any]]) -> dict[str, Any]:
    if not row:
        return {}
    result: dict[str, Any] = {}
    for key, value in row.items():
        if isinstance(value, datetime):
            result[key] = iso(value)
        else:
            result[key] = value
    return result


class PostgresStore:
    def __init__(self, database_url: str) -> None:
        from psycopg.rows import dict_row
        from psycopg_pool import ConnectionPool

        self.pool = ConnectionPool(database_url, min_size=1, max_size=10, kwargs={"row_factory": dict_row})

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
        with self.pool.connection() as conn:
            with conn.transaction():
                identity = conn.execute(
                    """
                    SELECT user_id FROM identities
                    WHERE provider=%s AND provider_user_id=%s AND app_id=%s
                    """,
                    (provider, provider_user_id, app_id),
                ).fetchone()
                if identity:
                    return self.get_user(identity["user_id"])
                user_id = new_id("usr")
                user = conn.execute(
                    """
                    INSERT INTO users(user_id, display_name, email, phone, is_active)
                    VALUES (%s, %s, %s, %s, true)
                    RETURNING *
                    """,
                    (user_id, display_name, email, phone),
                ).fetchone()
                conn.execute(
                    """
                    INSERT INTO identities(identity_id, user_id, provider, provider_user_id, app_id, union_id)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    """,
                    (new_id("idt"), user_id, provider, provider_user_id, app_id, union_id),
                )
                return _public(user)

    def get_user(self, user_id: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            row = conn.execute("SELECT * FROM users WHERE user_id=%s AND is_active=true", (user_id,)).fetchone()
        if not row:
            raise NotFound("User not found")
        return _public(row)

    def update_user_phone(self, user_id: str, phone: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            row = conn.execute(
                """
                UPDATE users SET phone=%s, updated_at=now()
                WHERE user_id=%s AND is_active=true
                RETURNING *
                """,
                (phone, user_id),
            ).fetchone()
        if not row:
            raise NotFound("User not found")
        return _public(row)

    def save_refresh_token(self, raw_token: str, user_id: str, app_id: str, device_id: str, expires_at: datetime) -> None:
        with self.pool.connection() as conn:
            conn.execute(
                """
                INSERT INTO refresh_tokens(refresh_token_id, token_hash, user_id, app_id, device_id, expires_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (new_id("rft"), token_hash(raw_token), user_id, app_id, device_id, expires_at),
            )

    def use_refresh_token(self, raw_token: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            row = conn.execute(
                """
                SELECT user_id, app_id, device_id FROM refresh_tokens
                WHERE token_hash=%s AND revoked_at IS NULL AND expires_at > now()
                """,
                (token_hash(raw_token),),
            ).fetchone()
        if not row:
            raise NotFound("Refresh token invalid")
        return _public(row)

    def revoke_refresh_token(self, raw_token: str) -> None:
        with self.pool.connection() as conn:
            conn.execute(
                "UPDATE refresh_tokens SET revoked_at=now() WHERE token_hash=%s",
                (token_hash(raw_token),),
            )

    def list_products(self, app_id: str) -> list[dict[str, Any]]:
        with self.pool.connection() as conn:
            rows = conn.execute(
                """
                SELECT app_id, product_id, name, description, amount_minor, currency,
                       entitlement_code, entitlement_duration_days, initial_quota, is_active
                FROM products
                WHERE app_id=%s AND is_active=true
                ORDER BY product_id
                """,
                (app_id,),
            ).fetchall()
        return [_public(row) for row in rows]

    def create_order(self, user_id: str, app_id: str, product_id: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            with conn.transaction():
                product = conn.execute(
                    """
                    SELECT * FROM products
                    WHERE app_id=%s AND product_id=%s AND is_active=true
                    """,
                    (app_id, product_id),
                ).fetchone()
                if not product:
                    raise NotFound("Product not found")
                order_id = new_id("ord")
                trade_no = out_trade_no()
                row = conn.execute(
                    """
                    INSERT INTO orders(order_id, user_id, app_id, product_id, out_trade_no,
                                       title, amount_minor, currency, status)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'created')
                    RETURNING *
                    """,
                    (
                        order_id,
                        user_id,
                        app_id,
                        product_id,
                        trade_no,
                        product["name"],
                        product["amount_minor"],
                        product["currency"],
                    ),
                ).fetchone()
        return _public(row)

    def get_order(self, order_id: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            row = conn.execute("SELECT * FROM orders WHERE order_id=%s", (order_id,)).fetchone()
        if not row:
            raise NotFound("Order not found")
        return _public(row)

    def create_payment(self, order_id: str, provider: str, channel: str, raw_payload: str = "") -> dict[str, Any]:
        with self.pool.connection() as conn:
            with conn.transaction():
                existing = conn.execute("SELECT * FROM payments WHERE order_id=%s", (order_id,)).fetchone()
                if existing:
                    return _public(existing)
                payment = conn.execute(
                    """
                    INSERT INTO payments(payment_id, order_id, provider, channel, status, raw_payload)
                    VALUES (%s, %s, %s, %s, 'pending', %s)
                    RETURNING *
                    """,
                    (new_id("pay"), order_id, provider, channel, _jsonb(raw_payload)),
                ).fetchone()
                conn.execute("UPDATE orders SET status='paying', updated_at=now() WHERE order_id=%s", (order_id,))
        return _public(payment)

    def update_payment_intent(self, payment_id: str, prepay_id: str, raw_payload: str) -> None:
        with self.pool.connection() as conn:
            conn.execute(
                """
                UPDATE payments
                SET prepay_id=%s, raw_payload=%s, updated_at=now()
                WHERE payment_id=%s
                """,
                (prepay_id, _jsonb(raw_payload), payment_id),
            )

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
        with self.pool.connection() as conn:
            with conn.transaction():
                order = conn.execute(
                    "SELECT * FROM orders WHERE out_trade_no=%s FOR UPDATE",
                    (out_trade_no_value,),
                ).fetchone()
                if not order:
                    raise NotFound("Order not found")
                if int(order["amount_minor"]) != amount_minor or order["currency"] != currency:
                    raise Conflict("Payment amount or currency mismatch")
                existing_notice = conn.execute(
                    "SELECT notification_id FROM payment_notifications WHERE notification_key=%s",
                    (notification_key,),
                ).fetchone()
                if existing_notice:
                    return _public(order)
                conn.execute(
                    """
                        INSERT INTO payment_notifications(notification_id, provider, notification_key,
                            out_trade_no, provider_trade_no, amount_minor, currency, verified, processed, raw_payload)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, true, false, %s)
                    """,
                    (
                        new_id("ntf"),
                        provider,
                        notification_key,
                        out_trade_no_value,
                        provider_trade_no,
                        amount_minor,
                        currency,
                        _jsonb(raw_payload),
                    ),
                )
                payment = conn.execute("SELECT * FROM payments WHERE order_id=%s", (order["order_id"],)).fetchone()
                if not payment:
                    payment = conn.execute(
                        """
                        INSERT INTO payments(payment_id, order_id, provider, channel, status, raw_payload)
                        VALUES (%s, %s, %s, 'native', 'pending', %s)
                        RETURNING *
                        """,
                        (new_id("pay"), order["order_id"], provider, _jsonb(raw_payload)),
                    ).fetchone()
                conn.execute(
                    """
                    UPDATE payments
                    SET status='paid', provider_trade_no=%s, paid_at=now(), updated_at=now()
                    WHERE payment_id=%s
                    """,
                    (provider_trade_no, payment["payment_id"]),
                )
                order = conn.execute(
                    """
                    UPDATE orders SET status='paid', paid_at=now(), updated_at=now()
                    WHERE order_id=%s
                    RETURNING *
                    """,
                    (order["order_id"],),
                ).fetchone()
                self._grant_entitlement(conn, order)
                conn.execute(
                    """
                    UPDATE payment_notifications
                    SET processed=true, processed_at=now()
                    WHERE notification_key=%s
                    """,
                    (notification_key,),
                )
        return _public(order)

    def _grant_entitlement(self, conn: Any, order: dict[str, Any]) -> None:
        existing = conn.execute(
            "SELECT entitlement_id FROM entitlements WHERE source_order_id=%s",
            (order["order_id"],),
        ).fetchone()
        if existing:
            return
        product = conn.execute(
            "SELECT * FROM products WHERE app_id=%s AND product_id=%s",
            (order["app_id"], order["product_id"]),
        ).fetchone()
        if not product:
            raise NotFound("Product not found")
        valid_from = now_utc()
        days = int(product["entitlement_duration_days"])
        valid_until = None if days <= 0 else valid_from + timedelta(days=days)
        conn.execute(
            """
            INSERT INTO entitlements(entitlement_id, user_id, app_id, product_id, code,
                status, valid_from, valid_until, remaining_quota, source_order_id)
            VALUES (%s, %s, %s, %s, %s, 'active', %s, %s, %s, %s)
            """,
            (
                new_id("ent"),
                order["user_id"],
                order["app_id"],
                order["product_id"],
                product["entitlement_code"],
                valid_from,
                valid_until,
                product["initial_quota"],
                order["order_id"],
            ),
        )

    def list_entitlements(self, user_id: str, app_id: str) -> list[dict[str, Any]]:
        with self.pool.connection() as conn:
            rows = conn.execute(
                """
                SELECT * FROM entitlements
                WHERE user_id=%s AND app_id=%s AND status='active'
                  AND (valid_until IS NULL OR valid_until > now())
                ORDER BY valid_until NULLS LAST, created_at
                """,
                (user_id, app_id),
            ).fetchall()
        return [_public(row) for row in rows]

    def consume_entitlement(
        self,
        user_id: str,
        app_id: str,
        code: str,
        feature_code: str,
        quantity: int,
        request_id: str,
    ) -> dict[str, Any]:
        if request_id:
            with self.pool.connection() as conn:
                existing = conn.execute(
                    "SELECT response_json FROM entitlement_consumptions WHERE request_id=%s",
                    (request_id,),
                ).fetchone()
            if existing:
                return existing["response_json"]
        with self.pool.connection() as conn:
            with conn.transaction():
                entitlement = conn.execute(
                    """
                    SELECT * FROM entitlements
                    WHERE user_id=%s AND app_id=%s AND code=%s AND status='active'
                      AND (valid_until IS NULL OR valid_until > now())
                    ORDER BY valid_until NULLS LAST, created_at
                    LIMIT 1
                    FOR UPDATE
                    """,
                    (user_id, app_id, code),
                ).fetchone()
                if not entitlement:
                    raise NotFound("Entitlement not found")
                remaining = int(entitlement["remaining_quota"])
                if remaining >= 0:
                    if remaining < quantity:
                        raise Conflict("Insufficient entitlement quota")
                    remaining -= quantity
                    status = "consumed" if remaining == 0 else "active"
                    conn.execute(
                        """
                        UPDATE entitlements SET remaining_quota=%s, status=%s, updated_at=now()
                        WHERE entitlement_id=%s
                        """,
                        (remaining, status, entitlement["entitlement_id"]),
                    )
                result = {
                    "success": True,
                    "entitlement_code": code,
                    "remaining_quota": remaining,
                    "consumed_quantity": quantity,
                    "server_time": iso(now_utc()),
                }
                if request_id:
                    conn.execute(
                        """
                        INSERT INTO entitlement_consumptions(consumption_id, request_id, user_id, app_id,
                            entitlement_id, entitlement_code, feature_code, quantity, remaining_quota,
                            idempotency_key, response_json)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (request_id) DO NOTHING
                        """,
                        (
                            new_id("con"),
                            request_id,
                            user_id,
                            app_id,
                            entitlement["entitlement_id"],
                            code,
                            feature_code,
                            quantity,
                            remaining,
                            request_id,
                            _jsonb(result),
                        ),
                    )
        return result

    def save_license_snapshot(self, snapshot: dict[str, Any]) -> None:
        with self.pool.connection() as conn:
            conn.execute(
                """
                INSERT INTO license_snapshots(snapshot_id, user_id, app_id, device_id,
                    issued_at, expires_at, entitlement_summary, payload, payload_json,
                    signature, key_id, schema_version, revocation_version)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    snapshot["snapshot_id"],
                    snapshot["payload"]["user_id"],
                    snapshot["payload"]["app_id"],
                    snapshot["payload"]["device_id"],
                    snapshot["issued_at"],
                    snapshot["expires_at"],
                    _jsonb({"entitlements": snapshot["payload"].get("entitlements", [])}),
                    _jsonb(snapshot["payload"]),
                    _jsonb(snapshot["payload"]),
                    snapshot["signature"],
                    snapshot["key_id"],
                    snapshot["schema_version"],
                    snapshot["revocation_version"],
                ),
            )

    def update_manifest(self, app_id: str, current_version: str, channel: str) -> dict[str, Any]:
        with self.pool.connection() as conn:
            row = conn.execute(
                """
                SELECT app_id, %s AS current_version, channel, latest_version, min_version,
                       manifest_url, package_url, package_hash, signature, force_update, release_notes
                FROM update_manifests
                WHERE app_id=%s AND channel=%s
                """,
                (current_version, app_id, channel),
            ).fetchone()
        if row:
            return _public(row)
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
