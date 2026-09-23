#!/bin/bash
# Seed Hotel Green Candle menu via live API
# Usage: ./tool/seed_green_candle_api.sh [BASE_URL] [STAFF_ID] [PIN] [OUTLET_ID]
# Defaults: BASE_URL=https://food.nexorytechnologies.com, STAFF_ID=st-gc-01, PIN=7777, OUTLET_ID=out-green-candle
# For local dev: ./tool/seed_green_candle_api.sh http://localhost:8080 st-02 9999 out-green-candle
set -e

BASE_URL="${1:-https://food.nexorytechnologies.com}"
STAFF_ID="${2:-st-02}"
PIN="${3:-9999}"
OUTLET_ID="${4:-out-green-candle}"

if [ -z "$BASE_URL" ]; then echo "BASE_URL required"; exit 1; fi

echo "=== Hotel Green Candle — API Seeder ==="
echo "Base: $BASE_URL"
echo "Outlet: $OUTLET_ID"
echo "Staff: $STAFF_ID"
echo ""

# 1) Login to get token
echo "→ Logging in as $STAFF_ID ..."
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"staff_id\":\"$STAFF_ID\",\"pin\":\"$PIN\",\"outlet_id\":\"$OUTLET_ID\"}" || true)

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('token','') or d.get('data',{}).get('token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ] || [ "$TOKEN" = "" ]; then
  echo "Login failed. Response:"
  echo "$LOGIN_RESP"
  echo ""
  echo "Hint: For demo org, use manager admin pin. Try st-02/9999 or st-03/0000 with out-01, then create outlet first."
  echo "Creating outlet $OUTLET_ID if needed via manager..."
  # fallback: login as out-01 manager and create outlet via API if endpoint exists (manual outlet creation is via onboarding)
  exit 1
fi
echo "✓ Logged in, token acquired."

# 2) Ensure outlet exists (check via outlets list)
echo "→ Checking outlet $OUTLET_ID ..."
OUTLETS=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/outlets" || true)
echo "$OUTLETS" | head -c 500
echo ""

# 3) Seed menu from JSON
JSON_FILE="assets/green_candle_menu.json"
if [ ! -f "$JSON_FILE" ]; then
  JSON_FILE="/root/food/assets/green_candle_menu.json"
fi
if [ ! -f "$JSON_FILE" ]; then
  echo "Missing $JSON_FILE"
  exit 1
fi

echo "→ Seeding $(python3 -c "import json; print(len(json.load(open('$JSON_FILE'))))") menu items..."
COUNT=0
FAILED=0

python3 << PY
import json, subprocess, shlex, os, sys
json_path = "$JSON_FILE"
base = "$BASE_URL"
token = "$TOKEN"
outlet = "$OUTLET_ID"

items = json.load(open(json_path, encoding="utf-8"))
import urllib.request, urllib.error
for it in items:
    payload = {
        "category_id": it["category_id"],
        "name": it["name"],
        "description": it["description"],
        "price_paise": it["price_paise"],
        "is_veg": it["is_veg"],
        "is_bestseller": it["is_bestseller"],
        "image_url": it["image_url"],
    }
    if "variants" in it:
        payload["variants"] = it["variants"]
    # POST to /api/v1/menu?outlet_id=...
    import json as j
    data = j.dumps(payload).encode()
    req = urllib.request.Request(f"{base}/api/v1/menu?outlet_id={outlet}", data=data, headers={"Content-Type":"application/json", "Authorization": f"Bearer {token}"}, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode()
            print(f"  ✓ {it['name']} ({it['category_id']}) → {resp.status}")
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"  ✗ {it['name']} → {e.code} {body[:200]}")
        # try to check if already exists (409?) then PATCH?
    except Exception as e:
        print(f"  ✗ {it['name']} → {e}")

PY

echo ""
echo "=== Done. Verify at $BASE_URL/m/$OUTLET_ID (customer menu) and $BASE_URL/api/v1/menu?outlet_id=$OUTLET_ID ==="
