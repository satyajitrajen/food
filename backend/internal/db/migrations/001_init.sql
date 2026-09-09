-- FoodPOS initial schema. Money is stored as INTEGER paise (1 INR = 100 paise).
CREATE TABLE IF NOT EXISTS outlets (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    address    TEXT NOT NULL DEFAULT '',
    terminal   TEXT NOT NULL DEFAULT 'POS-01',
    gstin      TEXT NOT NULL DEFAULT '',
    fssai      TEXT NOT NULL DEFAULT '',
    phone      TEXT NOT NULL DEFAULT '',
    is_online  INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS staff (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('admin','manager','cashier','waiter')),
    pin_hash    TEXT NOT NULL,
    avatar_url  TEXT NOT NULL DEFAULT '',
    mobile      TEXT NOT NULL DEFAULT '',
    is_active   INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS tables (
    id                   TEXT PRIMARY KEY,
    outlet_id            TEXT NOT NULL REFERENCES outlets(id),
    table_number         TEXT NOT NULL,
    seats                INTEGER NOT NULL,
    floor                TEXT NOT NULL,
    status               TEXT NOT NULL CHECK (status IN ('available','occupied','reserved','billing','cleaning')),
    active_order_id      TEXT,
    current_amount       INTEGER NOT NULL DEFAULT 0,
    running_minutes      INTEGER NOT NULL DEFAULT 0,
    guest_count          INTEGER NOT NULL DEFAULT 0,
    assigned_waiter_id   TEXT,
    merged_with_table_id TEXT,
    UNIQUE (outlet_id, table_number)
);

CREATE TABLE IF NOT EXISTS menu_categories (
    id        TEXT PRIMARY KEY,
    outlet_id TEXT NOT NULL REFERENCES outlets(id),
    name      TEXT NOT NULL,
    sort      INTEGER NOT NULL DEFAULT 0,
    UNIQUE (outlet_id, name)
);

CREATE TABLE IF NOT EXISTS menu_items (
    id            TEXT PRIMARY KEY,
    outlet_id     TEXT NOT NULL REFERENCES outlets(id),
    category_id   TEXT NOT NULL REFERENCES menu_categories(id),
    name          TEXT NOT NULL,
    description   TEXT NOT NULL DEFAULT '',
    price_paise   INTEGER NOT NULL,
    is_veg        INTEGER NOT NULL DEFAULT 1,
    image_url     TEXT NOT NULL DEFAULT '',
    is_bestseller INTEGER NOT NULL DEFAULT 0,
    is_available  INTEGER NOT NULL DEFAULT 1,
    sort          INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS product_variants (
    id          TEXT PRIMARY KEY,
    menu_item_id TEXT NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    price_paise INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS modifier_groups (
    id              TEXT PRIMARY KEY,
    menu_item_id    TEXT NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    is_multi_select INTEGER NOT NULL DEFAULT 0,
    is_required     INTEGER NOT NULL DEFAULT 0,
    sort            INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS modifier_items (
    id         TEXT PRIMARY KEY,
    group_id   TEXT NOT NULL REFERENCES modifier_groups(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    price_paise INTEGER NOT NULL DEFAULT 0,
    sort       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS orders (
    id                 TEXT PRIMARY KEY,
    outlet_id          TEXT NOT NULL REFERENCES outlets(id),
    order_number       TEXT NOT NULL,
    type               TEXT NOT NULL CHECK (type IN ('dine_in','takeaway','delivery')),
    status             TEXT NOT NULL CHECK (status IN ('received','preparing','ready','served','billing','completed','cancelled')),
    table_id           TEXT REFERENCES tables(id),
    table_number       TEXT,
    customer_name      TEXT,
    customer_phone     TEXT,
    delivery_address   TEXT,
    waiter_id          TEXT,
    waiter_name        TEXT,
    guest_count        INTEGER NOT NULL DEFAULT 1,
    order_note         TEXT,
    subtotal_paise     INTEGER NOT NULL DEFAULT 0,
    discount_percent   REAL NOT NULL DEFAULT 0,
    discount_paise     INTEGER NOT NULL DEFAULT 0,
    discount_reason    TEXT,
    tax_percent        REAL NOT NULL DEFAULT 5.0,
    tax_paise          INTEGER NOT NULL DEFAULT 0,
    service_paise      INTEGER NOT NULL DEFAULT 0,
    packaging_paise    INTEGER NOT NULL DEFAULT 0,
    delivery_paise     INTEGER NOT NULL DEFAULT 0,
    grand_total_paise  INTEGER NOT NULL DEFAULT 0,
    invoice_number     TEXT,
    paid_at            TEXT,
    payment_method     TEXT,
    paid_paise         INTEGER NOT NULL DEFAULT 0,
    change_paise       INTEGER NOT NULL DEFAULT 0,
    idempotency_key    TEXT UNIQUE,
    created_at         TEXT NOT NULL,
    updated_at         TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_orders_outlet_status ON orders(outlet_id, status);
CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at);

CREATE TABLE IF NOT EXISTS order_items (
    id           TEXT PRIMARY KEY,
    order_id     TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id TEXT NOT NULL REFERENCES menu_items(id),
    variant_id   TEXT,
    quantity     INTEGER NOT NULL DEFAULT 1,
    unit_paise   INTEGER NOT NULL,
    total_paise  INTEGER NOT NULL,
    note         TEXT,
    is_kot_sent  INTEGER NOT NULL DEFAULT 0,
    is_cancelled INTEGER NOT NULL DEFAULT 0,
    cancel_reason TEXT
);

CREATE TABLE IF NOT EXISTS order_item_modifiers (
    order_item_id  TEXT NOT NULL REFERENCES order_items(id) ON DELETE CASCADE,
    modifier_item_id TEXT NOT NULL,
    name           TEXT NOT NULL,
    price_paise    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (order_item_id, modifier_item_id)
);

CREATE TABLE IF NOT EXISTS kots (
    id          TEXT PRIMARY KEY,
    outlet_id   TEXT NOT NULL,
    kot_number  TEXT NOT NULL,
    order_id    TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    status      TEXT NOT NULL CHECK (status IN ('new','preparing','ready','served','cancelled')),
    waiter_id   TEXT,
    waiter_name TEXT,
    table_number TEXT,
    order_type  TEXT NOT NULL,
    note        TEXT,
    created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS kot_items (
    kot_id        TEXT NOT NULL REFERENCES kots(id) ON DELETE CASCADE,
    order_item_id TEXT NOT NULL,
    name          TEXT NOT NULL,
    quantity      INTEGER NOT NULL,
    PRIMARY KEY (kot_id, order_item_id)
);

CREATE TABLE IF NOT EXISTS shifts (
    id              TEXT PRIMARY KEY,
    outlet_id       TEXT NOT NULL,
    staff_id        TEXT NOT NULL,
    staff_name      TEXT NOT NULL,
    started_at      TEXT NOT NULL,
    closed_at       TEXT,
    opening_paise   INTEGER NOT NULL DEFAULT 0,
    opening_notes   TEXT,
    cash_sales      INTEGER NOT NULL DEFAULT 0,
    upi_sales       INTEGER NOT NULL DEFAULT 0,
    card_sales      INTEGER NOT NULL DEFAULT 0,
    refunds_cash    INTEGER NOT NULL DEFAULT 0,
    refunds_digital INTEGER NOT NULL DEFAULT 0,
    expenses        INTEGER NOT NULL DEFAULT 0,
    cash_in         INTEGER NOT NULL DEFAULT 0,
    cash_out        INTEGER NOT NULL DEFAULT 0,
    counted_paise   INTEGER,
    closing_notes   TEXT,
    status          TEXT NOT NULL CHECK (status IN ('open','closed'))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_shifts_one_open ON shifts(outlet_id) WHERE status = 'open';

CREATE TABLE IF NOT EXISTS shift_denominations (
    shift_id TEXT NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,
    kind     TEXT NOT NULL CHECK (kind IN ('open','close')),
    d500     INTEGER NOT NULL DEFAULT 0,
    d200     INTEGER NOT NULL DEFAULT 0,
    d100     INTEGER NOT NULL DEFAULT 0,
    d50      INTEGER NOT NULL DEFAULT 0,
    d20      INTEGER NOT NULL DEFAULT 0,
    d10      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (shift_id, kind)
);

CREATE TABLE IF NOT EXISTS cash_transactions (
    id         TEXT PRIMARY KEY,
    shift_id   TEXT NOT NULL REFERENCES shifts(id),
    type       TEXT NOT NULL CHECK (type IN ('cash_in','cash_out')),
    amount     INTEGER NOT NULL,
    reason     TEXT NOT NULL,
    reference  TEXT,
    staff_id   TEXT,
    staff_name TEXT,
    ts         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS expenses (
    id           TEXT PRIMARY KEY,
    outlet_id    TEXT NOT NULL,
    title        TEXT NOT NULL,
    category     TEXT NOT NULL,
    amount       INTEGER NOT NULL CHECK (amount > 0),
    method       TEXT NOT NULL DEFAULT 'Cash',
    vendor       TEXT,
    reference    TEXT,
    note         TEXT,
    ts           TEXT NOT NULL,
    created_by   TEXT
);

CREATE TABLE IF NOT EXISTS customers (
    id                  TEXT PRIMARY KEY,
    outlet_id           TEXT NOT NULL,
    name                TEXT NOT NULL,
    phone_norm          TEXT NOT NULL,
    email               TEXT,
    address             TEXT,
    gstin               TEXT,
    notes               TEXT,
    visits              INTEGER NOT NULL DEFAULT 0,
    lifetime_spend      INTEGER NOT NULL DEFAULT 0,
    outstanding_paise   INTEGER NOT NULL DEFAULT 0,
    last_visit          TEXT,
    UNIQUE (outlet_id, phone_norm)
);

CREATE TABLE IF NOT EXISTS inventory_items (
    id          TEXT PRIMARY KEY,
    outlet_id   TEXT NOT NULL,
    name        TEXT NOT NULL,
    unit        TEXT NOT NULL,
    stock       REAL NOT NULL DEFAULT 0,
    min_stock   REAL NOT NULL DEFAULT 0,
    cost_paise  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS stock_adjustments (
    id         TEXT PRIMARY KEY,
    item_id    TEXT NOT NULL REFERENCES inventory_items(id) ON DELETE CASCADE,
    delta      REAL NOT NULL,
    reason     TEXT NOT NULL,
    staff_id   TEXT,
    staff_name TEXT,
    ts         TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS suppliers (
    id           TEXT PRIMARY KEY,
    outlet_id    TEXT NOT NULL,
    name         TEXT NOT NULL,
    mobile       TEXT NOT NULL,
    email        TEXT,
    category     TEXT,
    outstanding  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS purchases (
    id          TEXT PRIMARY KEY,
    outlet_id   TEXT NOT NULL,
    invoice_no  TEXT NOT NULL,
    supplier_id TEXT REFERENCES suppliers(id),
    supplier_name TEXT NOT NULL,
    ts          TEXT NOT NULL,
    total_paise INTEGER NOT NULL DEFAULT 0,
    status      TEXT NOT NULL DEFAULT 'paid' CHECK (status IN ('paid','pending')),
    summary     TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS settings (
    outlet_id            TEXT PRIMARY KEY REFERENCES outlets(id),
    restaurant_name      TEXT NOT NULL DEFAULT '',
    gst_percent          REAL NOT NULL DEFAULT 5.0,
    is_gst_inclusive     INTEGER NOT NULL DEFAULT 0,
    service_percent      REAL NOT NULL DEFAULT 5.0,
    packaging_paise      INTEGER NOT NULL DEFAULT 2500,
    delivery_paise       INTEGER NOT NULL DEFAULT 4000,
    auto_print_kot       INTEGER NOT NULL DEFAULT 1,
    allow_reprint        INTEGER NOT NULL DEFAULT 1,
    billing_printer      TEXT NOT NULL DEFAULT '',
    kitchen_printer      TEXT NOT NULL DEFAULT '',
    bar_printer          TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS audit_log (
    id         TEXT PRIMARY KEY,
    ts         TEXT NOT NULL,
    staff_id   TEXT,
    action     TEXT NOT NULL,
    entity     TEXT NOT NULL,
    entity_id  TEXT NOT NULL,
    meta       TEXT NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS idempotency_keys (
    key           TEXT PRIMARY KEY,
    response_code INTEGER NOT NULL,
    response_body TEXT NOT NULL,
    created_at    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS counters (
    outlet_id TEXT NOT NULL,
    kind      TEXT NOT NULL CHECK (kind IN ('order','kot','invoice')),
    value     INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (outlet_id, kind)
);
