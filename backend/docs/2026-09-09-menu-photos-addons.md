# Menu photos + editable variants & add-ons — 2026-09-09

Backend contract for menu admin (manager/admin) enhancements. Companion
Flutter changes live in the app workspace (`lib/…`).

## What changed

### 1. Menu photo upload + static media serving
- **`POST /api/v1/uploads/menu-image`** (manager/admin) — multipart form with a
  `file` field. Accepts JPEG/PNG/WebP/GIF up to 5 MB. Stores the image under
  the upload directory and returns:
  `{"image_url": "/media/menu/<id>.<ext>"}`.
- **`GET /media/*`** (public) — serves stored files straight from disk so
  `<img>` tags load them without auth.
- Upload directory config: **`FOODPOS_UPLOAD_DIR`** env, default `./uploads`
  (server ignores the endpoint when it can't write/configure the dir → 503).
- The handler only stores the file. Persisting `image_url` on the menu item
  still goes through `PATCH /menu/{id}` (offline-first outbox) so conflict
  semantics are unchanged.
- Menu items keep the existing `image_url` TEXT column; no schema change.

### 2. Category by name or id
- `POST /menu` and `PATCH /menu/{id}` now accept `category_id` as **either the
  real category id or the display name** — the admin UI only knows names
  (`"Starters"`), while the rest of the API uses ids. New store helper
  `CategoryID(outletID, nameOrID)` resolves it (400 on unknown category).

### 3. Variants & modifier groups (already supported, now verified)
- `models.MenuItemUpsert` already carried `variants[]` and
  `modifier_groups[]`; `PATCH /menu/{id}` already replaced them **only when
  explicitly provided** (partial semantics — availability toggles never wipe
  add-ons). No backend change was needed beyond the category resolver; the
  gap was the admin UI, which now sends full arrays on every save.

## API quick notes

```
POST /uploads/menu-image          (multipart; manager/admin) → {"image_url": "/media/menu/…"}
GET  /media/menu/*                (public static files)
POST /menu {category_id: "Starters"|"cat-st", ..., variants[], modifier_groups[]}
PATCH /menu/{id}                  partial; include variants[]/modifier_groups[] to replace them
```

## Tests

`menu_admin_integration_test.go` covers:
- menu create with 2 variants + a multi-select add-on group (by category name)
- PATCH replacing variants/groups, and an availability-only PATCH **not**
  wiping them
- multipart photo upload → `image_url` returned → public fetch returns the file
  with the right content type → assigning it via PATCH → cashier upload = 403

Requires PostgreSQL (see `README.md` test section); unit runs need no DB:

```powershell
go vet ./... ; go build ./... ; go test ./internal/api -run ThisTestDoesNotExist -count=1
```
