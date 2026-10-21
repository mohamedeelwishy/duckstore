/**
 * Duck Store — Backend API
 * ---------------------------------------------------------------------------
 * Runs in the `backend` namespace. Owns SQLite database and serves JSON.
 */

const express = require("express");
const fs = require("fs");
const path = require("path");
const { DatabaseSync } = require("node:sqlite");

const PORT = Number(process.env.PORT || 3000);
const DB_PATH = process.env.DB_PATH || "/data/duckstore.db";
const SCHEMA_PATH = process.env.SCHEMA_PATH || path.join(__dirname, "schema.sql");

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const db = new DatabaseSync(DB_PATH);
db.exec("PRAGMA foreign_keys = ON");

function seedIfEmpty() {
  const { n } = db
    .prepare("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name='products'")
    .get();

  if (n === 0) {
    db.exec(fs.readFileSync(SCHEMA_PATH, "utf8"));
    console.log(`[db] seeded a fresh database at ${DB_PATH}`);
  } else {
    console.log(`[db] existing database found at ${DB_PATH}, leaving it alone`);
  }
}
seedIfEmpty();

const toCard = (r) => ({
  id: r.id,
  slug: r.slug,
  name: r.name,
  tagline: r.tagline,
  badge: r.badge,
  theme: r.theme,
  body: r.body_color,
  bg: r.bg_color,
  outline: r.outline_color || null,
  price: r.price_display,
  priceCents: r.price_cents,
  stock: r.stock,
  availability: r.availability,
});

const qAllCards = db.prepare("SELECT * FROM v_product_cards ORDER BY id");
const qCard = db.prepare("SELECT * FROM v_product_cards WHERE id = ?");
const qProduct = db.prepare("SELECT * FROM products WHERE id = ? AND is_active = 1");
const qFeatures = db.prepare(
  "SELECT label FROM product_features WHERE product_id = ? ORDER BY position"
);
const qRelated = db.prepare(
  "SELECT * FROM v_product_cards WHERE id != ? ORDER BY RANDOM() LIMIT 4"
);
const qCount = db.prepare("SELECT COUNT(*) AS n FROM products WHERE is_active = 1");
const qStats = db.prepare("SELECT * FROM v_order_totals ORDER BY order_id DESC LIMIT 10");

const insOrder = db.prepare("INSERT INTO orders (customer_id, status) VALUES (NULL, 'pending')");
const insItem = db.prepare(`
  INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents)
  SELECT ?, id, ?, price_cents FROM products WHERE id = ?
`);
const qOrderTotal = db.prepare("SELECT * FROM v_order_totals WHERE order_id = ?");

const app = express();
app.use(express.json());

app.use((req, res, next) => {
  const started = Date.now();
  res.on("finish", () =>
    console.log(`[api] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - started}ms)`)
  );
  next();
});

app.get("/api/health", (req, res) => {
  try {
    res.json({ status: "ok", ducks: qCount.get().n, db: DB_PATH });
  } catch (err) {
    res.status(503).json({ status: "degraded", error: err.message });
  }
});

app.get("/api/ducks", (req, res) => {
  res.json(qAllCards.all().map(toCard));
});

app.get("/api/ducks/:id", (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: "id must be an integer" });

  const product = qProduct.get(id);
  if (!product) return res.status(404).json({ error: "duck not found" });

  const card = qCard.get(id);
  res.json({
    ...toCard(card),
    description: product.description,
    features: qFeatures.all(id).map((r) => r.label),
  });
});

app.get("/api/ducks/:id/related", (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isInteger(id)) return res.status(400).json({ error: "id must be an integer" });
  res.json(qRelated.all(id).map(toCard));
});

app.post("/api/orders", (req, res) => {
  const productId = Number(req.body?.productId);
  const quantity = Number(req.body?.quantity ?? 1);

  if (!Number.isInteger(productId)) return res.status(400).json({ error: "productId must be an integer" });
  if (!Number.isInteger(quantity) || quantity < 1) return res.status(400).json({ error: "quantity must be >= 1" });

  const product = qProduct.get(productId);
  if (!product) return res.status(404).json({ error: "duck not found" });

  try {
    db.exec("BEGIN");
    const { lastInsertRowid } = insOrder.run();
    insItem.run(lastInsertRowid, quantity, productId);
    db.exec("COMMIT");

    const total = qOrderTotal.get(lastInsertRowid);
    res.status(201).json({
      orderId: Number(lastInsertRowid),
      product: product.name,
      quantity,
      totalCents: total.total_cents,
      total: (total.total_cents / 100).toFixed(2),
    });
  } catch (err) {
    db.exec("ROLLBACK");
    console.error("[api] order failed:", err.message);
    res.status(500).json({ error: "could not place order" });
  }
});

app.get("/api/stats", (req, res) => {
  res.json(qStats.all());
});

app.use((req, res) => res.status(404).json({ error: "no such endpoint" }));

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`[api] duck-api listening on 0.0.0.0:${PORT}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    console.log(`[api] ${signal} received, shutting down`);
    server.close(() => {
      db.close();
      process.exit(0);
    });
  });
}
