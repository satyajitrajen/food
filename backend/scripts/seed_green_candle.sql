-- Hotel Green Candle — Complete Menu Seed (Page 1)
-- Outlet: out-green-candle | Org: org-01 (adjust org_id as needed)
-- Run: psql $DATABASE_URL -f seed_green_candle.sql
-- Or: go run backend/scripts/seed_green_candle.go

-- 1) Outlet (idempotent)
INSERT INTO outlets (id, org_id, name, address, terminal, gstin, fssai, phone, is_online)
VALUES ('out-green-candle', 'org-01', 'Hotel Green Candle', 'Hotel Green Candle, Main Road, Maharashtra', 'POS-GC-01', '27AAAAA0000A1Z5', '11521000000125', '+91 98765 43212', 1)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, address=EXCLUDED.address, terminal=EXCLUDED.terminal, phone=EXCLUDED.phone;

-- 2) Categories for this outlet (idempotent by outlet_id + name)
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-01', 'out-green-candle', 'अरख्खा मसूर स्पेशल', 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-02', 'out-green-candle', 'इंडियन व्हेज स्पेशल', 1) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-03', 'out-green-candle', 'काजू स्पेशल', 2) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-04', 'out-green-candle', 'थंडाई स्पेशल', 3) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-05', 'out-green-candle', 'दाल फ्राय स्पेशल', 4) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-06', 'out-green-candle', 'पापड स्पेशल', 5) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-07', 'out-green-candle', 'राईस स्पेशल', 6) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-08', 'out-green-candle', 'रोटी स्पेशल', 7) ON CONFLICT DO NOTHING;
INSERT INTO menu_categories (id, outlet_id, name, sort) VALUES ('cat-gc-09', 'out-green-candle', 'व्हेज स्पेशल', 8) ON CONFLICT DO NOTHING;

-- Map category name -> id for inserts (use subquery)

-- 3) Menu items + variants
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-01', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='अरख्खा मसूर स्पेशल'), 'स्पेशल अरख्खा मसूर', 'Hotel Green Candle special Arakha Masoor', 10000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-01-half', 'gc-01', 'Half', 6000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-01-full', 'gc-01', 'Full', 10000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-02', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='अरख्खा मसूर स्पेशल'), 'स्पेशल अरख्खा मसूर तेज', 'Spicy Arakha Masoor - extra tart', 11000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-02-half', 'gc-02', 'Half', 7000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-02-full', 'gc-02', 'Full', 11000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-03', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='अरख्खा मसूर स्पेशल'), 'अरख्खा मसूर लसूण तडका', 'Arakha Masoor with garlic tadka', 12000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-03-half', 'gc-03', 'Half', 7000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-03-full', 'gc-03', 'Full', 12000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-04', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='दाल फ्राय स्पेशल'), 'दाल फ्राय', 'Dal Fry - lentils tempered with spices', 10000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-04-half', 'gc-04', 'Half', 6000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-04-full', 'gc-04', 'Full', 10000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-05', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='दाल फ्राय स्पेशल'), 'दाल तडका', 'Dal Tadka with ghee & garlic', 11000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-05-half', 'gc-05', 'Half', 7000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-05-full', 'gc-05', 'Full', 11000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-06', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर मसाला', 'Paneer cubes in rich masala gravy', 18000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-07', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर तवा', 'Paneer Tawa - semi-dry tawa preparation', 23000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-08', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर पसंदा', 'Paneer Pasanda - stuffed paneer in cashew gravy', 24000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-09', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर बटर मसाला', 'Creamy butter masala with paneer', 25000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-10', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर कढाई', 'Kadhai Paneer with capsicum & onions', 19000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-11', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर टिक्का मसाला', 'Grilled paneer tikka in masala gravy', 24000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-12', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पनीर भुर्जी', 'Scrambled paneer with spices', 19000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-13', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'मटर पनीर', 'Green peas & paneer in tomato gravy', 23000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-14', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'पालक पनीर', 'Paneer in smooth spinach gravy', 22000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-15', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='इंडियन व्हेज स्पेशल'), 'काजू पनीर मसाला', 'Cashew & paneer in rich gravy', 22000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-16', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='काजू स्पेशल'), 'काजू मसाला', 'Cashew masala curry', 19000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-17', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='काजू स्पेशल'), 'काजू करी', 'Kaju Curry - creamy cashew gravy', 19000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-18', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='काजू स्पेशल'), 'काजू कुर्मा', 'Mild Kaju Kurma with cashew paste', 21000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-19', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='काजू स्पेशल'), 'काजू कढाई', 'Kadhai style cashew with bell peppers', 23000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-20', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'ग्रीन कँडल स्पेशल', 'Signature Green Candle house special veg platter', 29900, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 1, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-21', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'मिक्स व्हेज', 'Mixed vegetables in masala gravy', 17000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-22', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'व्हेज कोल्हापुरी', 'Kolhapuri style spicy veg', 18000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-23', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'व्हेज रसा', 'Light veg rassa / curry', 8000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-24', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'व्हेज तवा', 'Veg Tawa - tawa fried veg', 23000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-25', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'गोभी मसाला', 'Gobi Masala - cauliflower in gravy', 22000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-26', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'आलू मटर मसाला', 'Potato & peas masala', 22000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-27', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'व्हेज पतियाला', 'Veg Patiala - rich royal gravy', 28000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-28', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'शेव भाजी', 'Shev Bhaji - sev in spicy gravy', 16000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-29', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='व्हेज स्पेशल'), 'दुधातील शेव भाजी', 'Shev Bhaji in milk/white gravy', 18000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-30', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'प्लेन राईस', 'Steamed plain rice', 8000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-30-half', 'gc-30', 'Half', 4000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-30-full', 'gc-30', 'Full', 8000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-31', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'जीरा राईस', 'Jeera rice - cumin tempered basmati', 9000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-31-half', 'gc-31', 'Half', 5000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-31-full', 'gc-31', 'Full', 9000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-32', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'घी राईस', 'Ghee Rice - basmati with ghee', 13000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-33', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'खुशका राईस', 'Khushka rice - lightly spiced', 10000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-33-half', 'gc-33', 'Half', 7000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-33-full', 'gc-33', 'Full', 10000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-34', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'व्हेज पुलाव', 'Veg Pulao with vegetables', 15000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-35', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'पनीर पुलाव', 'Paneer Pulao with paneer cubes', 17000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-36', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'व्हेज बिर्याणी', 'Veg Biryani - dum cooked', 21000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-37', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'दाल खिचडी', 'Dal Khichdi comfort rice & lentils', 11000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-38', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='राईस स्पेशल'), 'कढी राईस', 'Kadhi chawal', 12000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-39', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'गव्हाची रोटी', 'Wheat roti - plain or butter', 2500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-39-sadhi', 'gc-39', 'साधी', 2000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-39-butter', 'gc-39', 'बटर', 2500, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-40', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'तंदूर रोटी', 'Tandoor baked roti', 2500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-40-sadhi', 'gc-40', 'साधी', 2000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-40-butter', 'gc-40', 'बटर', 2500, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-41', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'नान रोटी', 'Soft Naan', 4500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-42', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'कुलचा', 'Kulcha - leavened bread', 3500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-42-regular', 'gc-42', 'रेग्युलर', 3000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-42-butter', 'gc-42', 'बटर', 3500, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-43', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'लच्छा पराठा', 'Layered laccha paratha', 6000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-44', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'व्हेज पराठा', 'Stuffed veg paratha', 10500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-45', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'आलू पराठा', 'Aloo paratha with curd/pickle', 9000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-46', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'तवा पराठा', 'Tawa Paratha', 4500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-46-sadhi', 'gc-46', 'साधी', 4000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-46-butter', 'gc-46', 'बटर', 4500, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-47', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='रोटी स्पेशल'), 'गार्लिक नान', 'Garlic butter naan', 7000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-48', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='थंडाई स्पेशल'), 'सोलकढी', 'Solkadhi - kokum + coconut milk cooler', 8000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-48-glass', 'gc-48', '1 Glass', 2000, 0) ON CONFLICT DO NOTHING;
INSERT INTO product_variants (id, menu_item_id, name, price_paise, seq) VALUES ('v-gc-48-liter', 'gc-48', '1 Liter', 8000, 0) ON CONFLICT DO NOTHING;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-49', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='थंडाई स्पेशल'), 'बटर मिल्क', 'Chaas / Buttermilk - 1 Glass', 3000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-50', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='थंडाई स्पेशल'), 'मिनरल वॉटर', 'Mineral Water bottle', 2000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-51', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='थंडाई स्पेशल'), 'दही', 'Curd / Dahi bowl', 2000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-52', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'फ्राय पापड', 'Fried papad', 2000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-53', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'रोस्ट पापड', 'Roasted papad', 2000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-54', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'मसाला पापड', 'Masala Papad with chutney & onion', 3500, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-55', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'फ्रेंच फ्राय', 'French Fries', 11000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-56', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'मसाला फ्रेंच फ्राय', 'Masala French Fries', 12000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;
INSERT INTO menu_items (id, outlet_id, category_id, name, description, price_paise, is_veg, image_url, is_bestseller, is_available, sort)
VALUES ('gc-57', 'out-green-candle', (SELECT id FROM menu_categories WHERE outlet_id='out-green-candle' AND name='पापड स्पेशल'), 'लसूण फ्राय', 'Garlic Fry', 11000, 1, 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=300', 0, 1, 0)
ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description, price_paise=EXCLUDED.price_paise, is_veg=EXCLUDED.is_veg, image_url=EXCLUDED.image_url, is_bestseller=EXCLUDED.is_bestseller;

-- 4) Staff for Green Candle (idempotent)
INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active, is_protected) VALUES ('st-gc-01', 'org-01', 'out-green-candle', 'Green Candle Manager', 'manager', '$2a$10$placeholder', 1, 0) ON CONFLICT (id) DO NOTHING; -- pin 7777 (hash via auth.Manager)
INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active, is_protected) VALUES ('st-gc-02', 'org-01', 'out-green-candle', 'Green Candle Cashier', 'cashier', '$2a$10$placeholder', 1, 0) ON CONFLICT (id) DO NOTHING; -- pin 4444
INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active, is_protected) VALUES ('st-gc-03', 'org-01', 'out-green-candle', 'Green Candle Waiter', 'waiter', '$2a$10$placeholder', 1, 0) ON CONFLICT (id) DO NOTHING; -- pin 1212
INSERT INTO staff (id, org_id, outlet_id, name, role, pin_hash, is_active, is_protected) VALUES ('st-gc-04', 'org-01', 'out-green-candle', 'Green Candle Kitchen', 'kitchen', '$2a$10$placeholder', 1, 0) ON CONFLICT (id) DO NOTHING; -- pin 3434
-- NOTE: Replace placeholder hashes with real bcrypt via `go run` seeder or set via API /auth.

-- 5) Settings row for outlet
INSERT INTO settings (outlet_id, restaurant_name, gst_percent, is_gst_inclusive, packaging_paise, delivery_paise, auto_print_kot, allow_reprint, sections)
VALUES ('out-green-candle', 'Hotel Green Candle', 5.0, 0, 0, 0, 1, 1, '["Ground Floor","First Floor","Outdoor"]')
ON CONFLICT (outlet_id) DO UPDATE SET restaurant_name=EXCLUDED.restaurant_name;

-- 6) Tables for Green Candle (12 tables across 3 floors)
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-01', 'out-green-candle', 'GC-01', 2, 'Ground Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-02', 'out-green-candle', 'GC-02', 4, 'Ground Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-03', 'out-green-candle', 'GC-03', 4, 'Ground Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-04', 'out-green-candle', 'GC-04', 6, 'Ground Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-05', 'out-green-candle', 'GC-05', 4, 'Ground Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-06', 'out-green-candle', 'GC-06', 4, 'First Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-07', 'out-green-candle', 'GC-07', 2, 'First Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-08', 'out-green-candle', 'GC-08', 6, 'First Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-09', 'out-green-candle', 'GC-09', 8, 'First Floor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-10', 'out-green-candle', 'GC-10', 4, 'Outdoor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-11', 'out-green-candle', 'GC-11', 2, 'Outdoor', 'available') ON CONFLICT (id) DO NOTHING;
INSERT INTO tables (id, outlet_id, table_number, seats, floor, status) VALUES ('t-gc-12', 'out-green-candle', 'GC-12', 4, 'Outdoor', 'available') ON CONFLICT (id) DO NOTHING;