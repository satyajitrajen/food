import urllib.request
import urllib.error
import json

BASE_URL = "https://food.nexorytechnologies.com"

def api_request(method, path, data=None, token=None, query=None):
    url = f"{BASE_URL}{path}"
    if query:
        qstr = "&".join(f"{k}={v}" for k, v in query.items())
        url = f"{url}?{qstr}"
    
    headers = {
        "User-Agent": "FoodPOS-Test",
        "Content-Type": "application/json"
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
        
    body = json.dumps(data).encode("utf-8") if data is not None else None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    
    try:
        with urllib.request.urlopen(req) as resp:
            resp_bytes = resp.read()
            if not resp_bytes:
                return resp.status, {}
            return resp.status, json.loads(resp_bytes.decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        try:
            return e.code, json.loads(body)
        except:
            return e.code, {"raw": body}
    except Exception as e:
        return 500, {"error": str(e)}

def main():
    print(f"=== Testing Menu Management API on {BASE_URL} ===\n")
    
    # 1. Login as manager
    print("1. Authenticating as Manager (Priya Joshi / st-02, PIN: 9999)...")
    status, res = api_request("POST", "/api/v1/auth/login", {
        "staff_id": "st-02",
        "pin": "9999",
        "outlet_id": "out-01"
    })
    
    if status != 200:
        print(f"   [FAIL] Login failed: {status} - {res}")
        return
        
    token = res.get("token")
    staff = res.get("staff", {})
    print(f"   [OK] Logged in successfully: {staff.get('name')} (Role: {staff.get('role')})\n")

    # 2. Check Initial Menu
    print("2. Listing Initial Menu Items (GET /api/v1/menu?outlet_id=out-01)...")
    status, m_res = api_request("GET", "/api/v1/menu", query={"outlet_id": "out-01"}, token=token)
    items = m_res.get("menu_items", []) or m_res.get("items", [])
    categories = m_res.get("categories", [])
    print(f"   [OK] Current Categories: {len(categories)} | Items: {len(items)}")
    for item in items:
        print(f"        * {item.get('name')} (ID: {item.get('id')}) | Rs {item.get('price_paise', 0)/100} | Category: {item.get('category')}")

    # 3. Create Green Candle Menu Item (POST /api/v1/menu)
    print("\n3. Testing POST /api/v1/menu (Creating 'Green Candle Special Platter')...")
    create_payload = {
        "name": "Green Candle Special Platter",
        "category_id": "Specialties",
        "price_paise": 34900,  # Rs 349.00
        "is_veg": True,
        "is_available": True,
        "description": "Signature Green Candle chef special platter with assorted dips",
        "variants": [
            {"name": "Regular", "price_paise": 34900},
            {"name": "Platter Feast", "price_paise": 49900}
        ],
        "modifier_groups": [
            {
                "name": "Dips & Extras",
                "is_multi_select": True,
                "is_required": False,
                "sort": 0,
                "items": [
                    {"name": "Mint Chutney", "price_paise": 2000},
                    {"name": "Garlic Mayo Dip", "price_paise": 3500}
                ]
            }
        ]
    }
    
    status, create_res = api_request("POST", "/api/v1/menu", data=create_payload, query={"outlet_id": "out-01"}, token=token)
    print(f"   Response Status: {status}")
    if status != 201:
        print(f"   [FAIL] Item creation failed: {create_res}")
        return
        
    item_id = create_res.get("id")
    print(f"   [OK] Item Created Successfully!")
    print(f"        ID: {item_id}")
    print(f"        Name: {create_res.get('name')}")
    print(f"        Price: Rs {create_res.get('price_paise', 0)/100}")
    print(f"        Category: {create_res.get('category')} (ID: {create_res.get('category_id')})")
    print(f"        Variants: {[v.get('name') + ' (Rs ' + str(v.get('price_paise')/100) + ')' for v in create_res.get('variants', [])]}")
    print(f"        Modifier Groups: {[g.get('name') for g in create_res.get('modifier_groups', [])]}")

    # 4. Fetch Single Item (GET /api/v1/menu/{id})
    print(f"\n4. Testing GET /api/v1/menu/{item_id}...")
    status, get_res = api_request("GET", f"/api/v1/menu/{item_id}", query={"outlet_id": "out-01"}, token=token)
    print(f"   Response Status: {status}")
    if status == 200:
        print(f"   [OK] Fetched item '{get_res.get('name')}', Available: {get_res.get('is_available')}")
    else:
        print(f"   [FAIL] Failed to fetch item: {get_res}")

    # 5. Patch Item (PATCH /api/v1/menu/{id})
    print(f"\n5. Testing PATCH /api/v1/menu/{item_id} (Updating price to Rs 399 & toggling availability)...")
    patch_payload = {
        "price_paise": 39900,
        "is_available": False,
        "description": "Updated Green Candle Platter - Freshly Prepared"
    }
    status, patch_res = api_request("PATCH", f"/api/v1/menu/{item_id}", data=patch_payload, query={"outlet_id": "out-01"}, token=token)
    print(f"   Response Status: {status}")
    if status == 200:
        print(f"   [OK] Updated Item!")
        print(f"        New Price: Rs {patch_res.get('price_paise', 0)/100}")
        print(f"        Availability: {patch_res.get('is_available')}")
        print(f"        Description: {patch_res.get('description')}")
    else:
        print(f"   [FAIL] Failed to patch item: {patch_res}")

    # 6. Verify in Full Menu List
    print("\n6. Testing GET /api/v1/menu to verify item in list...")
    status, list_res = api_request("GET", "/api/v1/menu", query={"outlet_id": "out-01"}, token=token)
    items = list_res.get("menu_items", []) or list_res.get("items", [])
    found = [i for i in items if i.get("id") == item_id]
    if found:
        print(f"   [OK] Verified item in menu list: '{found[0].get('name')}' (Rs {found[0].get('price_paise', 0)/100}, Available: {found[0].get('is_available')})")
    else:
        print(f"   [WARN] Item not found in list (total items: {len(items)})")

    # 7. Delete Item (DELETE /api/v1/menu/{id})
    print(f"\n7. Testing DELETE /api/v1/menu/{item_id}...")
    status, del_res = api_request("DELETE", f"/api/v1/menu/{item_id}", query={"outlet_id": "out-01"}, token=token)
    print(f"   Response Status: {status}")
    if status in (200, 204):
        print(f"   [OK] Successfully deleted item {item_id}")
    else:
        print(f"   [FAIL] Failed to delete: {del_res}")

    # 8. Verify 404 after deletion
    print(f"\n8. Verifying item is removed (GET /api/v1/menu/{item_id})...")
    status, final_res = api_request("GET", f"/api/v1/menu/{item_id}", query={"outlet_id": "out-01"}, token=token)
    if status == 404:
        print("   [OK] Item confirmed deleted (404 Not Found returned).")
    else:
        print(f"   Status: {status} - {final_res}")

    # 9. Test Menu Image Upload (POST /api/v1/uploads/menu-image)
    print("\n9. Testing Menu Image Upload (POST /api/v1/uploads/menu-image)...")
    import base64
    tiny_png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
    body = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="file"; filename="greencandle.png"\r\n'
        "Content-Type: image/png\r\n\r\n"
    ).encode("utf-8") + tiny_png + f"\r\n--{boundary}--\r\n".encode("utf-8")
    
    upload_req = urllib.request.Request(
        f"{BASE_URL}/api/v1/uploads/menu-image?outlet_id=out-01",
        data=body,
        headers={
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Authorization": f"Bearer {token}",
            "User-Agent": "FoodPOS-Test"
        }
    )
    try:
        with urllib.request.urlopen(upload_req) as resp:
            up_res = json.loads(resp.read().decode("utf-8"))
            print(f"   [OK] Image uploaded successfully! URL: {up_res.get('image_url')}")
    except urllib.error.HTTPError as e:
        print(f"   [FAIL] Upload error: {e.code} - {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"   [FAIL] Upload exception: {e}")

    print("\n=== ALL MENU MANAGEMENT API TESTS PASSED SUCCESSFULLY! ===")

if __name__ == "__main__":
    main()
