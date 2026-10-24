// Worst Market: static store with a cart and simulated orders.
// All dynamic content passes through esc() before reaching the DOM. No network or backend.
(function () {
  "use strict";

  const CART_KEY = "wm-cart";
  const ORDERS_KEY = "wm-orders-v2";
  try { localStorage.removeItem("wm-orders"); } catch (_) { /* storage not available */ }
  const view = document.getElementById("main");
  const money = (n) => "$" + n.toFixed(2);

  function esc(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  // localStorage may be unavailable (private mode, blocked cookies).
  function load(key, fallback) {
    try {
      const raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (_) {
      return fallback;
    }
  }

  function save(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (_) {
      /* No storage: the cart still works during the visit. */
    }
  }

  let cart = load(CART_KEY, []).filter((line) => CATALOG.some((p) => p.id === line.id));

  function findProduct(id) {
    return CATALOG.find((p) => p.id === id);
  }

  function cartCount() {
    return cart.reduce((sum, line) => sum + line.qty, 0);
  }

  function updateBadge() {
    document.getElementById("cart-count").textContent = String(cartCount());
  }

  function setCart(next) {
    cart = next;
    save(CART_KEY, cart);
    updateBadge();
  }

  function totals() {
    const subtotal = cart.reduce((sum, line) => sum + findProduct(line.id).price * line.qty, 0);
    const shipping = subtotal === 0 || subtotal >= FREE_SHIPPING_FROM ? 0 : SHIPPING_FLAT;
    const tax = subtotal * TAX_RATE;
    return { subtotal, shipping, tax, total: subtotal + shipping + tax };
  }

  function productCard(p) {
    return `
      <a class="card product-card" href="#/product/${esc(p.id)}">
        <div class="thumb ${esc(p.tone)}" aria-hidden="true">${esc(p.name.charAt(0))}</div>
        <div class="product-meta">
          <span class="tag">${esc(p.category)}</span>
          <b>${esc(p.name)}</b>
          <small>${esc(p.summary)}</small>
        </div>
        <div class="price">${money(p.price)}</div>
      </a>`;
  }

  function renderHome() {
    const featured = CATALOG.slice(0, 3).map(productCard).join("");
    view.innerHTML = `
      <section class="hero">
        <div class="hero-in">
          <div class="eyebrow">Nationwide shipping · 30-day returns</div>
          <h1>The essentials for home, office and the road</h1>
          <p>Products curated by our team, with warranty and customer support.</p>
          <a class="button" href="#/catalog">View catalog</a>
        </div>
      </section>
      <h2 class="section-title">Featured</h2>
      <div class="grid-products">${featured}</div>
      <p class="notice-inline">This store is a simulation. You can browse the catalog, build a cart and complete a test order.</p>`;
  }

  function renderCatalog(params) {
    const q = (params.get("q") || "").trim().toLowerCase();
    const cat = params.get("cat") || "";
    const categories = [...new Set(CATALOG.map((p) => p.category))];
    const items = CATALOG.filter((p) => {
      const matchesText = !q || (p.name + " " + p.summary).toLowerCase().includes(q);
      const matchesCat = !cat || p.category === cat;
      return matchesText && matchesCat;
    });
    const options = categories
      .map((c) => `<option value="${esc(c)}"${c === cat ? " selected" : ""}>${esc(c)}</option>`)
      .join("");
    view.innerHTML = `
      <h1 class="page-title">Catalog</h1>
      <form class="filters" id="filters" role="search">
        <label>Search <input type="search" name="q" value="${esc(q)}" placeholder="e.g. lamp"></label>
        <label>Category
          <select name="cat"><option value="">All</option>${options}</select>
        </label>
        <button class="button" type="submit">Filter</button>
      </form>
      <p class="muted">${items.length} product(s)</p>
      <div class="grid-products">${items.map(productCard).join("") || '<p class="muted">No products match that filter.</p>'}</div>`;
    document.getElementById("filters").addEventListener("submit", (event) => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      const next = new URLSearchParams();
      if (form.get("q")) next.set("q", String(form.get("q")));
      if (form.get("cat")) next.set("cat", String(form.get("cat")));
      const query = next.toString();
      location.hash = "#/catalog" + (query ? "?" + query : "");
    });
  }

  function renderProduct(id) {
    const p = findProduct(id);
    if (!p) return renderNotFound();
    view.innerHTML = `
      <nav class="crumbs"><a href="#/catalog">Catalog</a> / ${esc(p.category)}</nav>
      <div class="product-detail card">
        <div class="thumb large ${esc(p.tone)}" aria-hidden="true">${esc(p.name.charAt(0))}</div>
        <div>
          <span class="tag">${esc(p.category)}</span>
          <h1>${esc(p.name)}</h1>
          <p class="price big">${money(p.price)}</p>
          <p>${esc(p.description)}</p>
          <p class="muted">${esc(p.summary)} · ${p.stock > 10 ? "In stock" : "Last units"}</p>
          <form id="add-form" class="add-form">
            <label>Quantity <input type="number" name="qty" min="1" max="10" value="1"></label>
            <button class="button" type="submit">Add to cart</button>
          </form>
          <p class="status" id="status" aria-live="polite"></p>
        </div>
      </div>`;
    document.getElementById("add-form").addEventListener("submit", (event) => {
      event.preventDefault();
      const qty = Math.min(10, Math.max(1, parseInt(new FormData(event.currentTarget).get("qty"), 10) || 1));
      const exists = cart.some((line) => line.id === p.id);
      const next = exists
        ? cart.map((line) => (line.id === p.id ? { ...line, qty: Math.min(10, line.qty + qty) } : line))
        : [...cart, { id: p.id, qty }];
      setCart(next);
      document.getElementById("status").textContent = `Added: ${qty} × ${p.name}.`;
    });
  }

  function renderCart() {
    if (cart.length === 0) {
      view.innerHTML = `
        <h1 class="page-title">Cart</h1>
        <div class="card empty"><p>Your cart is empty.</p><a class="button" href="#/catalog">Browse products</a></div>`;
      return;
    }
    const rows = cart
      .map((line) => {
        const p = findProduct(line.id);
        return `
          <div class="cart-row" data-id="${esc(p.id)}">
            <div class="thumb small ${esc(p.tone)}" aria-hidden="true">${esc(p.name.charAt(0))}</div>
            <div class="cart-name"><a href="#/product/${esc(p.id)}">${esc(p.name)}</a><small>${money(p.price)} each</small></div>
            <div class="qty">
              <button type="button" data-act="dec" aria-label="Remove one">−</button>
              <span>${line.qty}</span>
              <button type="button" data-act="inc" aria-label="Add one">+</button>
            </div>
            <div class="price">${money(p.price * line.qty)}</div>
            <button type="button" class="link" data-act="remove">Remove</button>
          </div>`;
      })
      .join("");
    const t = totals();
    view.innerHTML = `
      <h1 class="page-title">Cart</h1>
      <div class="cart-layout">
        <section class="card" id="cart-lines">${rows}</section>
        <aside class="card summary">
          <h2>Summary</h2>
          <div><span>Subtotal</span><span>${money(t.subtotal)}</span></div>
          <div><span>Shipping</span><span>${t.shipping === 0 ? "Free" : money(t.shipping)}</span></div>
          <div><span>Estimated tax (13%)</span><span>${money(t.tax)}</span></div>
          <div class="total"><span>Total</span><span>${money(t.total)}</span></div>
          <a class="button wide" href="#/checkout">Continue to payment</a>
          <p class="muted small">Free shipping from ${money(FREE_SHIPPING_FROM)}.</p>
        </aside>
      </div>`;
    document.getElementById("cart-lines").addEventListener("click", (event) => {
      const button = event.target.closest("button[data-act]");
      if (!button) return;
      const id = button.closest(".cart-row").dataset.id;
      const next = cart
        .map((line) => {
          if (line.id !== id) return line;
          if (button.dataset.act === "inc") return { ...line, qty: Math.min(10, line.qty + 1) };
          if (button.dataset.act === "dec") return { ...line, qty: line.qty - 1 };
          return null;
        })
        .filter((line) => line && line.qty > 0);
      setCart(next);
      renderCart();
    });
  }

  function renderCheckout() {
    if (cart.length === 0) {
      location.hash = "#/cart";
      return;
    }
    const t = totals();
    view.innerHTML = `
      <h1 class="page-title">Checkout</h1>
      <div class="cart-layout">
        <form class="card form" id="checkout" novalidate>
          <h2>Shipping details</h2>
          <p class="notice-inline">Use fictional data. The order is local and simulated: do not enter real personal or payment information.</p>
          <label>Full name <input name="name" autocomplete="name" required maxlength="80"></label>
          <label>Email <input type="email" name="email" autocomplete="email" required maxlength="120"></label>
          <label>Address <input name="address" autocomplete="street-address" required maxlength="160"></label>
          <label>City <input name="city" autocomplete="address-level2" required maxlength="80"></label>
          <h2>Payment</h2>
          <fieldset class="methods">
            <label><input type="radio" name="method" value="simulated" checked> Simulated payment (nothing is charged)</label>
            <label><input type="radio" name="method" value="transfer"> Bank transfer (simulated)</label>
          </fieldset>
          <p class="muted small">We do not request card details in this demonstration.</p>
          <p class="error" id="form-error" role="alert"></p>
          <button class="button wide" type="submit">Confirm order for ${money(t.total)}</button>
        </form>
        <aside class="card summary">
          <h2>Your order</h2>
          ${cart.map((line) => `<div><span>${esc(line.qty)} × ${esc(findProduct(line.id).name)}</span><span>${money(findProduct(line.id).price * line.qty)}</span></div>`).join("")}
          <div><span>Shipping</span><span>${t.shipping === 0 ? "Free" : money(t.shipping)}</span></div>
          <div class="total"><span>Total</span><span>${money(t.total)}</span></div>
        </aside>
      </div>`;
    document.getElementById("checkout").addEventListener("submit", (event) => {
      event.preventDefault();
      placeOrder(new FormData(event.currentTarget));
    });
  }

  function placeOrder(form) {
    const error = document.getElementById("form-error");
    const fields = ["name", "email", "address", "city"].map((key) => String(form.get(key) || "").trim());
    if (fields.some((value) => value === "")) {
      error.textContent = "Fill in all shipping fields.";
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fields[1])) {
      error.textContent = "Check the email address.";
      return;
    }
    const code = "WM-" + Math.random().toString(36).slice(2, 8).toUpperCase();
    const t = totals();
    const orders = load(ORDERS_KEY, []);
    // Only persists the data needed to show the receipt; never the form information.
    orders.unshift({
      code,
      date: new Date().toISOString(),
      lines: cart.map((line) => ({ id: line.id, qty: line.qty })),
      total: t.total,
    });
    save(ORDERS_KEY, orders.slice(0, 20));
    setCart([]);
    location.hash = "#/order/" + code;
  }

  function renderOrder(code) {
    const order = load(ORDERS_KEY, []).find((o) => o.code === code);
    if (!order) return renderNotFound("We couldn't find that order in this browser.");
    const lines = order.lines
      .map((line) => {
        const p = findProduct(line.id);
        return p ? `<div><span>${esc(line.qty)} × ${esc(p.name)}</span><span>${money(p.price * line.qty)}</span></div>` : "";
      })
      .join("");
    view.innerHTML = `
      <div class="card confirm">
        <div class="eyebrow">Order confirmed</div>
        <h1>Thanks for trying Worst Market</h1>
        <p>Order code: <b>${esc(order.code)}</b></p>
        <p class="muted">This order is a simulation and does not generate charges or store personal data.</p>
        <div class="summary">${lines}<div class="total"><span>Total</span><span>${money(order.total)}</span></div></div>
        <a class="button" href="#/catalog">Keep shopping</a>
      </div>`;
  }

  // Conceptual storyboard. It does not generate or send an exploitation request.
  const SCENARIOS = {
    vulnerable: {
      label: "Vulnerable runtime (conceptual)",
      steps: [
        { title: "HTTP request", detail: "The request reaches the web server. In these CVEs, processing happens inside the PHP runtime; application validation may not run first." },
        { title: "Affected PHP runtime", detail: "CVE-2026-109618: an out-of-memory error path can leave internal state inconsistent. CVE-2026-109619: freed internal state may still be referenced." },
        { title: "In-process execution", detail: "On an affected installation, the reported result is remote code execution. The immediate scope depends on the process configuration and permissions." },
        { title: "Container boundary", detail: "Without additional isolation, the process could access the files and resources available to its user and its network." },
      ],
      outcome: "Storyboard finished. No exploitation traffic was sent and no payload was executed.",
    },
  };

  function renderSecurity() {
    const vulnerableRuntime = window.MN_DEMO_MODE === "vulnerable-runtime";
    const scopeNote = window.MN_ACTIVE_PROFILE || "Active profile: PHP 8.5.11 without runtime hardening. The walkthrough does not send an exploitation request or run a payload.";
    view.innerHTML = `
      <h1 class="page-title">Security demo: PHP CVEs</h1>
      <div class="card">
        <p><code>CVE-2026-109618</code> and <code>CVE-2026-109619</code> are PHP runtime flaws that may allow remote code execution on affected installations. The flaw can occur before the application processes the request.</p>
        <p class="notice-inline"><b>Scope of this demo:</b> ${esc(scopeNote)} The walkthroughs are an educational storyboard; they do not send attack requests or execute code.</p>
        <p class="muted" id="scenario-label"></p>
        <button class="button" id="run-scenario" type="button">Walk through scenario</button>
        <ol class="steps" id="steps"></ol>
        <p class="status" id="scenario-status" aria-live="polite"></p>
        <div class="cve-recommendation"><b>Primary mitigation</b><p>Update PHP to a fixed version per the official advisory. Container restrictions reduce the potential impact, but do not fix the vulnerability.</p><a href="https://www.php.net/archive/2026.php" target="_blank" rel="noreferrer">PHP security advisory</a></div>
      </div>`;
    let selected = "vulnerable";
    const renderSteps = () => {
      const scenario = SCENARIOS[selected];
      document.getElementById("scenario-label").textContent = scenario.label;
      document.getElementById("steps").innerHTML = scenario.steps.map(
        (step, i) => `
          <li class="step" data-index="${i}">
            <span class="step-num">${i + 1}</span>
            <div><b>${esc(step.title)}</b><p>${esc(step.detail)}</p></div>
            <span class="step-state">Pending</span>
          </li>`
      ).join("");
      document.getElementById("scenario-status").textContent = "";
    };
    document.getElementById("run-scenario").addEventListener("click", () => runScenario(SCENARIOS[selected]));
    renderSteps();
  }

  function runScenario(scenario) {
    const items = [...document.querySelectorAll("#steps .step")];
    const status = document.getElementById("scenario-status");
    const button = document.getElementById("run-scenario");
    button.disabled = true;
    items.forEach((item) => {
      item.classList.remove("done");
      item.querySelector(".step-state").textContent = "Pending";
    });
    status.textContent = "";
    items.forEach((item, i) => {
      setTimeout(() => {
        item.classList.add("done");
        item.querySelector(".step-state").textContent = "Done";
        if (i === items.length - 1) {
          status.textContent = scenario.outcome;
          button.disabled = false;
        }
      }, 600 * (i + 1));
    });
  }

  function renderNotFound(message) {
    view.innerHTML = `
      <div class="card empty">
        <h1>Page not found</h1>
        <p>${esc(message || "The address you are looking for does not exist.")}</p>
        <a class="button" href="#/">Back to home</a>
      </div>`;
  }

  function route() {
    const raw = location.hash.replace(/^#/, "") || "/";
    const [pathPart, queryPart] = raw.split("?");
    const parts = pathPart.split("/").filter(Boolean);
    const params = new URLSearchParams(queryPart || "");
    updateBadge();
    window.scrollTo(0, 0);

    if (parts.length === 0) return renderHome();
    if (parts[0] === "catalog") return renderCatalog(params);
    if (parts[0] === "product" && parts[1]) return renderProduct(decodeURIComponent(parts[1]));
    if (parts[0] === "cart") return renderCart();
    if (parts[0] === "checkout") return renderCheckout();
    if (parts[0] === "order" && parts[1]) return renderOrder(decodeURIComponent(parts[1]));
    if (parts[0] === "security") return renderSecurity();
    return renderNotFound();
  }

  window.addEventListener("hashchange", route);
  route();
})();
