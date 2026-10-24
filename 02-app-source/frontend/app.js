const USER_ID = "demo";

const $ = (id) => document.getElementById(id);

function setStatus(message, isError = false) {
  const el = $("status");
  el.textContent = message;
  el.className = isError ? "error" : "";
}

async function api(path, options) {
  const res = await fetch(path, {
    headers: { "content-type": "application/json" },
    ...options,
  });
  if (!res.ok) throw new Error(`${options?.method || "GET"} ${path} -> ${res.status}`);
  return res.status === 204 ? null : res.json();
}

async function loadProducts() {
  const products = await api("/api/products");
  $("products").innerHTML = products
    .map(
      (p) => `
        <article class="card">
          <h3>${p.name}</h3>
          <p>${p.description}</p>
          <p class="price">$${(p.price_cents / 100).toFixed(2)}</p>
          <button data-product="${p.id}" type="button">Add to cart</button>
          <button data-order="${p.id}" type="button" class="secondary">Place order</button>
        </article>`
    )
    .join("");
  $("products").querySelectorAll("button[data-product]").forEach((btn) => {
    btn.addEventListener("click", () => addToCart(Number(btn.dataset.product)));
  });
  $("products").querySelectorAll("button[data-order]").forEach((btn) => {
    btn.addEventListener("click", () => placeOrder(Number(btn.dataset.order)));
  });
}

async function loadCart() {
  const cart = await api(`/api/cart/${USER_ID}`);
  $("cart").textContent = JSON.stringify(cart, null, 2);
}

async function loadOrders() {
  const orders = await api(`/api/orders?userId=${USER_ID}`);
  $("orders").textContent = orders.length ? JSON.stringify(orders, null, 2) : "No orders yet";
}

async function addToCart(productId) {
  try {
    await api(`/api/cart/${USER_ID}/items`, {
      method: "POST",
      body: JSON.stringify({ productId, quantity: 1 }),
    });
    await loadCart();
    setStatus(`Added product ${productId} to cart`);
  } catch (err) {
    setStatus(err.message, true);
  }
}

async function placeOrder(productId) {
  try {
    await api("/api/orders", {
      method: "POST",
      body: JSON.stringify({ userId: USER_ID, productId, quantity: 1 }),
    });
    await loadOrders();
    setStatus(`Order placed for product ${productId}`);
  } catch (err) {
    setStatus(err.message, true);
  }
}

$("clear-cart").addEventListener("click", async () => {
  try {
    await api(`/api/cart/${USER_ID}`, { method: "DELETE" });
    await loadCart();
    setStatus("Cart cleared");
  } catch (err) {
    setStatus(err.message, true);
  }
});

(async function init() {
  try {
    await Promise.all([loadProducts(), loadCart(), loadOrders()]);
    setStatus("Ready");
  } catch (err) {
    setStatus(err.message, true);
  }
})();

