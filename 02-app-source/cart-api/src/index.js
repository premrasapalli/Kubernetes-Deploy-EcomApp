const express = require("express");
const { createClient } = require("redis");

const app = express();
app.use(express.json());
app.disable("x-powered-by");

const port = Number(process.env.PORT || 8082);
const redis = createClient({
  url: process.env.REDIS_URL || "redis://redis:6379",
  socket: { reconnectStrategy: (retries) => Math.min(retries * 200, 3000) },
});

redis.on("error", (err) => console.error(`redis error: ${err.message}`));

app.get("/health", async (_req, res) => {
  try {
    await redis.ping();
    res.json({ status: "ok", service: "cart-api" });
  } catch (err) {
    res.status(503).json({ status: "degraded", error: err.message });
  }
});

app.get("/api/cart/:userId", async (req, res, next) => {
  try {
    const cart = await redis.hGetAll(`cart:${req.params.userId}`);
    res.json(cart);
  } catch (err) {
    next(err);
  }
});

app.post("/api/cart/:userId/items", async (req, res, next) => {
  try {
    const { productId, quantity = 1 } = req.body;
    if (!productId || !Number.isInteger(quantity) || quantity < 1) {
      return res.status(400).json({ error: "productId and positive integer quantity required" });
    }
    await redis.hIncrBy(`cart:${req.params.userId}`, String(productId), quantity);
    res.status(201).json(await redis.hGetAll(`cart:${req.params.userId}`));
  } catch (err) {
    next(err);
  }
});

app.delete("/api/cart/:userId", async (req, res, next) => {
  try {
    await redis.del(`cart:${req.params.userId}`);
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});

app.use((err, _req, res, _next) => {
  console.error(JSON.stringify({ level: "error", service: "cart-api", message: err.message }));
  res.status(500).json({ error: "internal error" });
});

async function start() {
  for (let attempt = 1; attempt <= 30; attempt += 1) {
    try {
      await redis.connect();
      break;
    } catch (err) {
      console.error(`redis connect attempt ${attempt} failed: ${err.message}`);
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  app.listen(port, () => console.log(`cart-api listening on ${port}`));
}

process.on("SIGTERM", async () => {
  if (redis.isOpen) await redis.quit();
  process.exit(0);
});

start();
