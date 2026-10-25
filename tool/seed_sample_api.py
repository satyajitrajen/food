#!/usr/bin/env python3
"""Load sample data into an outlet through the public API (no direct DB).

Signs in as a manager/admin staff member (PIN prompted, never an argument),
then creates a sample menu, tables and two staff (waiter + kitchen) through
the same endpoints the app uses. Safe to re-run: existing menu items and
tables (matched by name / number) are skipped.

Usage:
  python3 tool/seed_sample_api.py --staff st-2563-a552aa --outlet out-d10f-c1d45e
  python3 tool/seed_sample_api.py --base http://localhost:8080 --staff ... --outlet ...
"""

import argparse
import getpass
import json
import secrets
import sys
import urllib.error
import urllib.request
import uuid

MENU = [
    # (category, name, description, veg, bestseller, price_rupees or {variant: rupees})
    ("Starters", "Paneer Tikka", "Char-grilled cottage cheese with peppers", True, True, 220),
    ("Starters", "Veg Spring Rolls", "Crisp rolls with stir-fried vegetables", True, False, 160),
    ("Starters", "Chicken 65", "Spicy deep-fried chicken, curry leaves", False, True, 240),
    ("Starters", "Masala Papad", "Roasted papad with onion-tomato topping", True, False, 60),
    ("Main Course", "Paneer Butter Masala", "Paneer in rich tomato-butter gravy", True, True, {"Half": 150, "Full": 260}),
    ("Main Course", "Dal Tadka", "Yellow lentils tempered with ghee and garlic", True, False, {"Half": 90, "Full": 160}),
    ("Main Course", "Butter Chicken", "Tandoori chicken in creamy makhani gravy", False, True, {"Half": 190, "Full": 340}),
    ("Main Course", "Veg Kolhapuri", "Mixed vegetables in spicy Kolhapuri masala", True, False, 210),
    ("Breads", "Butter Roti", "Whole-wheat tandoor roti with butter", True, False, 25),
    ("Breads", "Garlic Naan", "Leavened bread with garlic and coriander", True, True, 60),
    ("Breads", "Laccha Paratha", "Layered flaky paratha", True, False, 50),
    ("Rice", "Jeera Rice", "Basmati rice tempered with cumin", True, False, 120),
    ("Rice", "Veg Biryani", "Dum-cooked basmati with vegetables and raita", True, False, {"Half": 140, "Full": 230}),
    ("Rice", "Chicken Biryani", "Hyderabadi-style dum biryani with raita", False, True, {"Half": 180, "Full": 300}),
    ("South Indian", "Masala Dosa", "Crisp dosa with potato bhaji, sambar, chutney", True, True, 110),
    ("South Indian", "Idli Sambar", "Two steamed idlis with sambar and chutney", True, False, 70),
    ("South Indian", "Medu Vada", "Crisp lentil fritters with sambar", True, False, 80),
    ("Beverages", "Masala Chai", "Spiced Indian tea", True, False, 25),
    ("Beverages", "Cold Coffee", "Chilled blended coffee", True, False, 90),
    ("Beverages", "Fresh Lime Soda", "Sweet or salted", True, False, 60),
    ("Beverages", "Mineral Water", "1 litre bottle", True, False, 20),
    ("Desserts", "Gulab Jamun", "Two warm jamuns in sugar syrup", True, False, 60),
    ("Desserts", "Kulfi", "Malai kulfi on a stick", True, False, 70),
]

TABLES = [  # (number, seats, floor)
    ("T1", 2, "Ground"), ("T2", 2, "Ground"), ("T3", 4, "Ground"), ("T4", 4, "Ground"),
    ("T5", 4, "Ground"), ("T6", 6, "Ground"), ("F1", 4, "Family"), ("F2", 8, "Family"),
]

STAFF = [("Ravi (Waiter)", "waiter"), ("Suresh (Kitchen)", "kitchen")]


class Api:
    def __init__(self, base):
        self.base = base.rstrip("/")
        self.token = None

    def call(self, method, path, body=None, idempotent=False):
        req = urllib.request.Request(self.base + path, method=method)
        req.add_header("Content-Type", "application/json")
        if self.token:
            req.add_header("Authorization", "Bearer " + self.token)
        if idempotent:
            req.add_header("Idempotency-Key", str(uuid.uuid4()))
        data = json.dumps(body).encode() if body is not None else None
        try:
            with urllib.request.urlopen(req, data, timeout=30) as res:
                raw = res.read()
                return res.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {"raw": raw.decode(errors="replace")}


def items_of(resp):
    if isinstance(resp, list):
        return resp
    if isinstance(resp, dict):
        for k in ("menu_items", "tables", "staff", "items", "data"):
            if isinstance(resp.get(k), list):
                return resp[k]
    return []


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--base", default="https://food.nexorytechnologies.com")
    p.add_argument("--staff", required=True, help="manager/admin staff id")
    p.add_argument("--outlet", required=True, help="outlet id to fill")
    p.add_argument("--no-staff", action="store_true", help="skip creating waiter/kitchen staff")
    a = p.parse_args()

    api = Api(a.base)
    pin = getpass.getpass(f"PIN for {a.staff}: ")
    code, resp = api.call("POST", "/api/v1/auth/login",
                          {"staff_id": a.staff, "pin": pin, "outlet_id": a.outlet})
    if code != 200 or not (resp or {}).get("token"):
        sys.exit(f"login failed ({code}): {resp}")
    api.token = resp["token"]
    print("signed in")

    _, existing = api.call("GET", "/api/v1/menu")
    have_items = {m.get("name") for m in items_of(existing)}
    made = skipped = 0
    for cat, name, desc, veg, best, price in MENU:
        if name in have_items:
            skipped += 1
            continue
        body = {"category_id": cat, "name": name, "description": desc,
                "is_veg": veg, "is_bestseller": best, "is_available": True}
        if isinstance(price, dict):
            body["variants"] = [{"name": v, "price_paise": r * 100} for v, r in price.items()]
            body["price_paise"] = min(price.values()) * 100
        else:
            body["price_paise"] = price * 100
        c, r = api.call("POST", "/api/v1/menu", body)
        if c in (200, 201):
            made += 1
        else:
            print(f"  menu '{name}' failed ({c}): {r}")
    print(f"menu: {made} created, {skipped} already there")

    _, existing = api.call("GET", "/api/v1/tables")
    have_tables = {t.get("table_number") for t in items_of(existing)}
    made = skipped = 0
    for num, seats, floor in TABLES:
        if num in have_tables:
            skipped += 1
            continue
        c, r = api.call("POST", "/api/v1/tables",
                        {"table_number": num, "seats": seats, "floor": floor}, idempotent=True)
        if c in (200, 201):
            made += 1
        else:
            print(f"  table {num} failed ({c}): {r}")
    print(f"tables: {made} created, {skipped} already there")

    if not a.no_staff:
        _, existing = api.call("GET", "/api/v1/staff/all?outlet_id=" + a.outlet)
        have_staff = {s.get("name") for s in items_of(existing)}
        for name, role in STAFF:
            if name in have_staff:
                print(f"staff: {name} already there")
                continue
            new_pin = f"{secrets.randbelow(9000) + 1000}"
            c, r = api.call("POST", "/api/v1/staff",
                            {"name": name, "role": role, "pin": new_pin, "outlet_id": a.outlet})
            if c in (200, 201):
                print(f"staff: {name} ({role}) created, PIN {new_pin}")
            else:
                print(f"  staff '{name}' failed ({c}): {r}")


if __name__ == "__main__":
    main()
