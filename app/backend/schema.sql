PRAGMA foreign_keys = ON;

BEGIN TRANSACTION;

DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
DROP TABLE IF EXISTS product_features;
DROP TABLE IF EXISTS products;

DROP VIEW IF EXISTS v_product_cards;
DROP VIEW IF EXISTS v_order_totals;

CREATE TABLE products (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    slug            TEXT    NOT NULL UNIQUE,
    name            TEXT    NOT NULL,
    tagline         TEXT,
    description     TEXT,
    price_cents     INTEGER NOT NULL CHECK (price_cents >= 0),
    badge           TEXT,
    theme           TEXT    NOT NULL,
    body_color      TEXT    NOT NULL,
    bg_color        TEXT    NOT NULL,
    outline_color   TEXT,
    stock           INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    is_active       INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE product_features (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    product_id  INTEGER NOT NULL,
    label       TEXT    NOT NULL,
    position    INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
);

CREATE TABLE customers (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    email         TEXT    NOT NULL UNIQUE,
    full_name     TEXT,
    password_hash TEXT,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE orders (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_id  INTEGER,
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')),
    placed_at    TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL
);

CREATE TABLE order_items (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id          INTEGER NOT NULL,
    product_id        INTEGER NOT NULL,
    quantity          INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents  INTEGER NOT NULL CHECK (unit_price_cents >= 0),
    FOREIGN KEY (order_id)   REFERENCES orders(id)   ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
    UNIQUE (order_id, product_id)
);

CREATE INDEX idx_features_product   ON product_features (product_id, position);
CREATE INDEX idx_orders_customer    ON orders           (customer_id);
CREATE INDEX idx_orders_status      ON orders           (status, placed_at);
CREATE INDEX idx_items_order        ON order_items      (order_id);
CREATE INDEX idx_items_product      ON order_items      (product_id);
CREATE INDEX idx_products_active    ON products         (is_active);

CREATE VIEW v_product_cards AS
SELECT
    p.id,
    p.slug,
    p.name,
    p.tagline,
    p.badge,
    p.theme,
    p.body_color,
    p.bg_color,
    p.outline_color,
    p.price_cents,
    PRINTF('%.2f', p.price_cents / 100.0) AS price_display,
    p.stock,
    CASE WHEN p.stock > 0 THEN 'in_stock' ELSE 'sold_out' END AS availability
FROM products p
WHERE p.is_active = 1;

CREATE VIEW v_order_totals AS
SELECT
    o.id            AS order_id,
    o.status,
    o.placed_at,
    c.email         AS customer_email,
    COUNT(oi.id)                            AS line_count,
    COALESCE(SUM(oi.quantity), 0)           AS total_ducks,
    COALESCE(SUM(oi.quantity * oi.unit_price_cents), 0) AS total_cents
FROM orders o
LEFT JOIN customers   c  ON c.id = o.customer_id
LEFT JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.id, o.status, o.placed_at, c.email;

INSERT INTO products
    (id, slug, name, tagline, price_cents, badge, theme, body_color, bg_color, outline_color, stock, description)
VALUES
(1, 'classic-duck', 'Classic Duck', 'The original. The legend.',
 999, 'Bestseller', 'classic', '#FFD93D', '#FFF3C4', NULL, 120,
 'The one that started it all. A perfectly round, unapologetically yellow bath companion with a squeak that has soothed generations. Hand-finished, BPA-free, and scientifically proven to improve your debugging skills by at least 40%.'),

(2, 'ninja-duck', 'Ninja Duck', 'You won''t hear it coming.',
 1499, 'Stealth', 'ninja', '#3A4250', '#DCE5EE', NULL, 45,
 'Trained in the ancient art of silent floating. Comes with a matte black hood and a tiny katana (not sharp, we checked twice). Ideal for late-night bath sessions and covert code reviews.'),

(3, 'pirate-duck', 'Pirate Duck', 'Arrr you ready to float?',
 1350, 'Crew Favorite', 'pirate', '#FFD93D', '#FFE0CC', NULL, 60,
 'Captain of the bathtub seas. Sports an eye patch, a tiny tricorn hat, and a treasure map to the soap dish. Warning: may attempt to commandeer other ducks in your collection.'),

(4, 'batman-duck', 'Batman Duck', 'The duck Gotham deserves.',
 1999, 'Limited', 'caped', '#FFD93D', '#D8DEE6', NULL, 18,
 'Brooding, caped, and mysteriously wealthy. This duck patrols the porcelain streets at night and never squeaks about its secret identity. Cape is fully waterproof.'),

(5, 'astronaut-duck', 'Astronaut Duck', 'One small quack for duckkind.',
 1725, 'New', 'astronaut', '#FFFFFF', '#BCE2F7', '#C2D6E4', 34,
 'Zero-gravity certified and ready for the bathtub void. Its bubble helmet keeps the shampoo out while it explores the outer rim of your tub. Comes with a tiny flag to plant on the soap.'),

(6, 'chef-duck', 'Chef Duck', 'Bon apppe-quack!',
 1275, 'Tasty', 'chef', '#FFD93D', '#F3EADB', NULL, 72,
 'Michelin-star energy in a bath toy. Wears a starched toque and carries a whisk that is far too small to be useful. Will judge your bubble-to-water ratio, silently but firmly.'),

(7, 'rockstar-duck', 'Rockstar Duck', 'Turn the squeak up to 11.',
 1600, 'Loud', 'rockstar', '#FFD93D', '#EEDCFB', NULL, 0,
 'Sunglasses on, guitar strapped, attitude permanently set to maximum. The loudest squeak in our entire catalogue, tuned to a perfect A minor. Neighbours not included.'),

(8, 'detective-duck', 'Detective Duck', 'Every bug leaves a clue.',
 1550, 'Debugger', 'detective', '#FFD93D', '#D9EFE3', NULL, 88,
 'The official rubber duck of rubber-duck debugging. Wears a tweed cap, holds a magnifying glass, and listens patiently while you explain your code out loud until you find the bug yourself.');

INSERT INTO product_features (product_id, label, position) VALUES
(1, 'Original squeak engine',   1),
(1, 'Floats perfectly level',   2),
(1, 'BPA-free vinyl',           3),
(1, 'Ages 0 to 99',             4),
(2, 'Matte stealth coating',    1),
(2, 'Silent-mode squeak',       2),
(2, 'Includes foam katana',     3),
(2, 'Shadow-approved',          4),
(3, 'Removable tricorn hat',    1),
(3, 'Hand-painted eye patch',   2),
(3, 'Treasure map included',    3),
(3, 'Salt-water tested',        4),
(4, 'Detachable cape',          1),
(4, 'Glow-in-the-dark belt',    2),
(4, 'Brooding facial expression', 3),
(4, 'Collector''s edition',     4),
(5, 'Clear bubble helmet',      1),
(5, 'Reflective space suit',    2),
(5, 'Mini flag included',       3),
(5, 'Survives cold water',      4),
(6, 'Starched chef toque',      1),
(6, 'Tiny whisk accessory',     2),
(6, 'Judges your technique',    3),
(6, 'Dishwasher safe',          4),
(7, 'Extra-loud squeak',        1),
(7, 'Mini electric guitar',     2),
(7, 'Tiny sunglasses',          3),
(7, 'Tour-tested durability',   4),
(8, 'Magnifying glass',         1),
(8, 'Tweed detective cap',      2),
(8, 'Infinite patience',        3),
(8, 'Solves bugs by listening', 4);

INSERT INTO customers (id, email, full_name) VALUES
(1, 'mohamed@example.com', 'Mohamed Elwishy'),
(2, 'guest@example.com',   'Guest Shopper');

INSERT INTO orders (id, customer_id, status) VALUES
(1, 1, 'paid'),
(2, 2, 'pending');

INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents) VALUES
(1, 1, 2,  999),
(1, 4, 1, 1999),
(2, 8, 1, 1550);

COMMIT;
