const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());
app.disable("x-powered-by");

const port = Number(process.env.PORT || 8081);
const pool = new Pool({
  host: process.env.DB_HOST || "postgres",
  port: Number(process.env.DB_PORT || 5432),
  database: process.env.DB_NAME || "retailx",
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

let ready = false;

async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS products (
      id SERIAL PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
      stock INTEGER NOT NULL DEFAULT 0
    )
  `);
  const { rows } = await pool.query("SELECT COUNT(*)::int AS count FROM products");
  if (rows[0].count === 0) {
    await pool.query(
      `INSERT INTO products (name, description, price_cents, stock) VALUES
        ('Mechanical Keyboard', 'Hot-swappable, RGB', 8999, 25),
        ('Wireless Mouse', 'Ergonomic 2.4GHz', 2999, 60),
        ('USB-C Hub', '7-in-1 aluminium', 4999, 40)`
    );
  }
  ready = true;
}

app.get("/health", async (_req, res) => {
  if (!ready) return res.status(503).json({ status: "starting" });
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", service: "product-api" });
  } catch (err) {
    res.status(503).json({ status: "degraded", error: err.message });
  }
});

app.get("/api/products", async (_req, res, next) => {
  try {
    const { rows } = await pool.query("SELECT * FROM products ORDER BY id");
    res.json(rows);
  } catch (err) {
    next(err);
  }
});

app.get("/api/products/:id", async (req, res, next) => {
  try {
    const { rows } = await pool.query("SELECT * FROM products WHERE id = $1", [req.params.id]);
    if (rows.length === 0) return res.status(404).json({ error: "not found" });
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

app.post("/api/products", async (req, res, next) => {
  try {
    const { name, description = "", priceCents, stock = 0 } = req.body;
    if (!name || !Number.isInteger(priceCents) || priceCents < 0) {
      return res.status(400).json({ error: "name and non-negative integer priceCents required" });
    }
    const { rows } = await pool.query(
      "INSERT INTO products (name, description, price_cents, stock) VALUES ($1,$2,$3,$4) RETURNING *",
      [name, description, priceCents, stock]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(JSON.stringify({ level: "error", service: "product-api", message: err.message }));
  res.status(500).json({ error: "internal error" });
});

async function start() {
  for (let attempt = 1; attempt <= 30; attempt += 1) {
    try {
      await initSchema();
      break;
    } catch (err) {
      console.error(`db init attempt ${attempt} failed: ${err.message}`);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  app.listen(port, () => console.log(`product-api listening on ${port}`));
}

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});

start();
