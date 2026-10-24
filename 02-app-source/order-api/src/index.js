const express = require("express");
const { Pool } = require("pg");

const app = express();
app.use(express.json());
app.disable("x-powered-by");

const port = Number(process.env.PORT || 8083);
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

async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS orders (
      id SERIAL PRIMARY KEY,
      user_id TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      status TEXT NOT NULL DEFAULT 'created',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);
}

app.get("/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", service: "order-api" });
  } catch (err) {
    res.status(503).json({ status: "degraded", error: err.message });
  }
});

app.post("/api/orders", async (req, res, next) => {
  try {
    const { userId, productId, quantity = 1 } = req.body;
    if (!userId || !Number.isInteger(productId) || !Number.isInteger(quantity) || quantity < 1) {
      return res.status(400).json({ error: "userId, integer productId and positive quantity required" });
    }
    const { rows } = await pool.query(
      "INSERT INTO orders (user_id, product_id, quantity) VALUES ($1,$2,$3) RETURNING *",
      [userId, productId, quantity]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    next(err);
  }
});

app.get("/api/orders/:id", async (req, res, next) => {
  try {
    const { rows } = await pool.query("SELECT * FROM orders WHERE id = $1", [req.params.id]);
    if (rows.length === 0) return res.status(404).json({ error: "not found" });
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

app.get("/api/orders", async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      "SELECT * FROM orders WHERE user_id = $1 ORDER BY id DESC LIMIT 50",
      [req.query.userId || ""]
    );
    res.json(rows);
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(JSON.stringify({ level: "error", service: "order-api", message: err.message }));
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
  app.listen(port, () => console.log(`order-api listening on ${port}`));
}

process.on("SIGTERM", async () => {
  await pool.end();
  process.exit(0);
});

start();
