// Mercado Norte: tienda estática con carrito y pedidos simulados.
// Todo el contenido dinámico pasa por esc() antes de llegar al DOM. No hay red ni backend.
(function () {
  "use strict";

  const CART_KEY = "mn-cart";
  const ORDERS_KEY = "mn-orders-v2";
  try { localStorage.removeItem("mn-orders"); } catch (_) { /* almacenamiento no disponible */ }
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

  // localStorage puede no estar disponible (modo privado, cookies bloqueadas).
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
      /* Sin almacenamiento: el carrito sigue funcionando durante la visita. */
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
      <a class="card product-card" href="#/producto/${esc(p.id)}">
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
          <div class="eyebrow">Envíos a todo el país · Devoluciones en 30 días</div>
          <h1>Lo esencial para la casa, la oficina y el camino</h1>
          <p>Productos seleccionados por nuestro equipo, con garantía y atención en español.</p>
          <a class="button" href="#/catalogo">Ver catálogo</a>
        </div>
      </section>
      <h2 class="section-title">Destacados</h2>
      <div class="grid-products">${featured}</div>
      <p class="notice-inline">Esta tienda es una simulación. Puedes explorar el catálogo, armar un carrito y completar un pedido de prueba.</p>`;
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
      <h1 class="page-title">Catálogo</h1>
      <form class="filters" id="filters" role="search">
        <label>Buscar <input type="search" name="q" value="${esc(q)}" placeholder="Ej. lámpara"></label>
        <label>Categoría
          <select name="cat"><option value="">Todas</option>${options}</select>
        </label>
        <button class="button" type="submit">Filtrar</button>
      </form>
      <p class="muted">${items.length} producto(s)</p>
      <div class="grid-products">${items.map(productCard).join("") || '<p class="muted">No encontramos productos con ese filtro.</p>'}</div>`;
    document.getElementById("filters").addEventListener("submit", (event) => {
      event.preventDefault();
      const form = new FormData(event.currentTarget);
      const next = new URLSearchParams();
      if (form.get("q")) next.set("q", String(form.get("q")));
      if (form.get("cat")) next.set("cat", String(form.get("cat")));
      const query = next.toString();
      location.hash = "#/catalogo" + (query ? "?" + query : "");
    });
  }

  function renderProduct(id) {
    const p = findProduct(id);
    if (!p) return renderNotFound();
    view.innerHTML = `
      <nav class="crumbs"><a href="#/catalogo">Catálogo</a> / ${esc(p.category)}</nav>
      <div class="product-detail card">
        <div class="thumb large ${esc(p.tone)}" aria-hidden="true">${esc(p.name.charAt(0))}</div>
        <div>
          <span class="tag">${esc(p.category)}</span>
          <h1>${esc(p.name)}</h1>
          <p class="price big">${money(p.price)}</p>
          <p>${esc(p.description)}</p>
          <p class="muted">${esc(p.summary)} · ${p.stock > 10 ? "En stock" : "Últimas unidades"}</p>
          <form id="add-form" class="add-form">
            <label>Cantidad <input type="number" name="qty" min="1" max="10" value="1"></label>
            <button class="button" type="submit">Agregar al carrito</button>
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
      document.getElementById("status").textContent = `Agregado: ${qty} × ${p.name}.`;
    });
  }

  function renderCart() {
    if (cart.length === 0) {
      view.innerHTML = `
        <h1 class="page-title">Carrito</h1>
        <div class="card empty"><p>Tu carrito está vacío.</p><a class="button" href="#/catalogo">Explorar productos</a></div>`;
      return;
    }
    const rows = cart
      .map((line) => {
        const p = findProduct(line.id);
        return `
          <div class="cart-row" data-id="${esc(p.id)}">
            <div class="thumb small ${esc(p.tone)}" aria-hidden="true">${esc(p.name.charAt(0))}</div>
            <div class="cart-name"><a href="#/producto/${esc(p.id)}">${esc(p.name)}</a><small>${money(p.price)} c/u</small></div>
            <div class="qty">
              <button type="button" data-act="dec" aria-label="Quitar uno">−</button>
              <span>${line.qty}</span>
              <button type="button" data-act="inc" aria-label="Agregar uno">+</button>
            </div>
            <div class="price">${money(p.price * line.qty)}</div>
            <button type="button" class="link" data-act="remove">Quitar</button>
          </div>`;
      })
      .join("");
    const t = totals();
    view.innerHTML = `
      <h1 class="page-title">Carrito</h1>
      <div class="cart-layout">
        <section class="card" id="cart-lines">${rows}</section>
        <aside class="card summary">
          <h2>Resumen</h2>
          <div><span>Subtotal</span><span>${money(t.subtotal)}</span></div>
          <div><span>Envío</span><span>${t.shipping === 0 ? "Gratis" : money(t.shipping)}</span></div>
          <div><span>Impuesto estimado (13%)</span><span>${money(t.tax)}</span></div>
          <div class="total"><span>Total</span><span>${money(t.total)}</span></div>
          <a class="button wide" href="#/checkout">Continuar al pago</a>
          <p class="muted small">Envío gratis desde ${money(FREE_SHIPPING_FROM)}.</p>
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
      location.hash = "#/carrito";
      return;
    }
    const t = totals();
    view.innerHTML = `
      <h1 class="page-title">Finalizar compra</h1>
      <div class="cart-layout">
        <form class="card form" id="checkout" novalidate>
          <h2>Datos de envío</h2>
          <p class="notice-inline">Usa datos ficticios. El pedido es local y simulado: no ingreses información personal ni de pago real.</p>
          <label>Nombre completo <input name="name" autocomplete="name" required maxlength="80"></label>
          <label>Correo electrónico <input type="email" name="email" autocomplete="email" required maxlength="120"></label>
          <label>Dirección <input name="address" autocomplete="street-address" required maxlength="160"></label>
          <label>Ciudad <input name="city" autocomplete="address-level2" required maxlength="80"></label>
          <h2>Pago</h2>
          <fieldset class="methods">
            <label><input type="radio" name="method" value="simulado" checked> Pago simulado (no se cobra nada)</label>
            <label><input type="radio" name="method" value="transferencia"> Transferencia bancaria (simulada)</label>
          </fieldset>
          <p class="muted small">No solicitamos datos de tarjeta en esta demostración.</p>
          <p class="error" id="form-error" role="alert"></p>
          <button class="button wide" type="submit">Confirmar pedido por ${money(t.total)}</button>
        </form>
        <aside class="card summary">
          <h2>Tu pedido</h2>
          ${cart.map((line) => `<div><span>${esc(line.qty)} × ${esc(findProduct(line.id).name)}</span><span>${money(findProduct(line.id).price * line.qty)}</span></div>`).join("")}
          <div><span>Envío</span><span>${t.shipping === 0 ? "Gratis" : money(t.shipping)}</span></div>
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
      error.textContent = "Completa todos los campos de envío.";
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(fields[1])) {
      error.textContent = "Revisa el correo electrónico.";
      return;
    }
    const code = "MN-" + Math.random().toString(36).slice(2, 8).toUpperCase();
    const t = totals();
    const orders = load(ORDERS_KEY, []);
    // Solo persiste los datos necesarios para mostrar el recibo; nunca la información del formulario.
    orders.unshift({
      code,
      date: new Date().toISOString(),
      lines: cart.map((line) => ({ id: line.id, qty: line.qty })),
      total: t.total,
    });
    save(ORDERS_KEY, orders.slice(0, 20));
    setCart([]);
    location.hash = "#/pedido/" + code;
  }

  function renderOrder(code) {
    const order = load(ORDERS_KEY, []).find((o) => o.code === code);
    if (!order) return renderNotFound("No encontramos ese pedido en este navegador.");
    const lines = order.lines
      .map((line) => {
        const p = findProduct(line.id);
        return p ? `<div><span>${esc(line.qty)} × ${esc(p.name)}</span><span>${money(p.price * line.qty)}</span></div>` : "";
      })
      .join("");
    view.innerHTML = `
      <div class="card confirm">
        <div class="eyebrow">Pedido confirmado</div>
        <h1>Gracias por probar Mercado Norte</h1>
        <p>Código de pedido: <b>${esc(order.code)}</b></p>
        <p class="muted">Este pedido es una simulación y no genera cargos ni guarda datos personales.</p>
        <div class="summary">${lines}<div class="total"><span>Total</span><span>${money(order.total)}</span></div></div>
        <a class="button" href="#/catalogo">Seguir comprando</a>
      </div>`;
  }

  // Storyboard conceptual. No genera ni envía una petición de explotación.
  const SCENARIOS = {
    vulnerable: {
      label: "Runtime vulnerable (conceptual)",
      steps: [
        { title: "Solicitud HTTP", detail: "La petición llega al servidor web. En estos CVE, el procesamiento ocurre dentro del runtime PHP; la validación de la aplicación puede no ejecutarse antes." },
        { title: "Runtime PHP afectado", detail: "CVE-2026-109618: una ruta de error por falta de memoria puede dejar estado interno inconsistente. CVE-2026-109619: estado interno liberado puede seguir referenciado." },
        { title: "Ejecución en el proceso", detail: "En una instalación afectada, el resultado reportado es ejecución remota de código. El alcance inmediato depende de la configuración y permisos del proceso." },
        { title: "Límite del contenedor", detail: "Sin aislamiento adicional, el proceso podría acceder a los archivos y recursos disponibles para su usuario y su red." },
      ],
      outcome: "Storyboard terminado. No se envió tráfico, no se ejecutó código y esta tienda no usa PHP.",
    },
    isolated: {
      label: "Contención del despliegue de esta demo",
      steps: [
        { title: "Solicitud HTTP", detail: "Mercado Norte sirve archivos estáticos; no procesa solicitudes con PHP." },
        { title: "Runtime ausente", detail: "La imagen nginx no incluye intérprete PHP ni FastCGI. Este sitio no reproduce ni es vulnerable a estos CVE." },
        { title: "Proceso sin privilegios", detail: "La imagen y los manifiestos ejecutan nginx como UID 101, sin capacidades Linux y con escalamiento de privilegios desactivado." },
        { title: "Límites de impacto", detail: "El despliegue omite identidad del workload y limita filesystem y egreso según la plataforma. Consulta riesgos residuales en README." },
      ],
      outcome: "Recorrido de controles terminado. Para corregir una app PHP real, instala la versión corregida; la contención no parchea el runtime.",
    },
  };

  function renderSecurity() {
    const vulnerableRuntime = window.MN_DEMO_MODE === "vulnerable-runtime";
    const scopeNote = vulnerableRuntime
      ? "Perfil activo: PHP 8.5.11, anterior a la versión corregida 8.5.12. El recorrido no envía una petición de explotación ni ejecuta un payload."
      : "Perfil activo: sitio estático sin PHP. El runtime vulnerable se puede seleccionar solo para despliegues Kubernetes aislados.";
    SCENARIOS.vulnerable.outcome = vulnerableRuntime
      ? "Storyboard terminado. PHP 8.5.11 está activo, pero no se envió tráfico de explotación ni se ejecutó un payload."
      : "Storyboard terminado. No se envió tráfico, no se ejecutó código y este perfil no usa PHP.";
    SCENARIOS.isolated.steps = vulnerableRuntime
      ? [
          { title: "Runtime PHP 8.5.11", detail: "Este perfil sí carga las solicitudes en una versión anterior a la corrección oficial. Una explotación real podría ejecutar código dentro del proceso PHP." },
          { title: "Proceso sin privilegios", detail: "El proceso usa UID 101, no es root y no tiene capacidades Linux. Las funciones PHP para invocar comandos están desactivadas." },
          { title: "Sin shell ni escritura persistente", detail: "La imagen elimina los intérpretes de comandos; el filesystem raíz es de solo lectura y /tmp es efímero." },
          { title: "Egreso e identidad", detail: "Las NetworkPolicy de Kubernetes deniegan egreso salvo DNS; el pod no recibe token de ServiceAccount ni identidad cloud." },
        ]
      : [
          { title: "Solicitud HTTP", detail: "Mercado Norte sirve archivos estáticos; no procesa solicitudes con PHP." },
          { title: "Runtime ausente", detail: "La imagen nginx no incluye intérprete PHP ni FastCGI. Este sitio no reproduce ni es vulnerable a estos CVE." },
          { title: "Proceso sin privilegios", detail: "La imagen y los manifiestos ejecutan nginx como UID 101, sin capacidades Linux y con escalamiento de privilegios desactivado." },
          { title: "Límites de impacto", detail: "El despliegue omite identidad del workload y limita filesystem y egreso según la plataforma. Consulta riesgos residuales en README." },
        ];
    view.innerHTML = `
      <h1 class="page-title">Demo de seguridad: CVE en PHP</h1>
      <div class="card">
        <p><code>CVE-2026-109618</code> y <code>CVE-2026-109619</code> son fallas del runtime PHP que pueden permitir ejecución remota de código en instalaciones afectadas. El fallo puede ocurrir antes de que la aplicación procese la petición.</p>
        <p class="notice-inline"><b>Alcance de esta demo:</b> ${esc(scopeNote)} Los recorridos son un storyboard educativo; no envían solicitudes de ataque ni ejecutan código.</p>
        <div class="scenario-picker" role="group" aria-label="Escenario">
          <button class="button scenario-choice active" data-scenario="vulnerable" type="button">Ver cadena de riesgo</button>
          <button class="button scenario-choice secondary" data-scenario="isolated" type="button">Ver contención aplicada</button>
        </div>
        <p class="muted" id="scenario-label"></p>
        <button class="button" id="run-scenario" type="button">Recorrer escenario</button>
        <ol class="steps" id="steps"></ol>
        <p class="status" id="scenario-status" aria-live="polite"></p>
        <div class="cve-recommendation"><b>Mitigación principal</b><p>Actualizar PHP a una versión corregida según el aviso oficial. Las restricciones de contenedor reducen el impacto potencial, pero no corrigen la vulnerabilidad.</p><a href="https://www.php.net/archive/2026.php" target="_blank" rel="noreferrer">Aviso de seguridad de PHP</a></div>
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
            <span class="step-state">Pendiente</span>
          </li>`
      ).join("");
      document.getElementById("scenario-status").textContent = "";
    };
    document.querySelectorAll(".scenario-choice").forEach((button) => {
      button.addEventListener("click", () => {
        selected = button.dataset.scenario;
        document.querySelectorAll(".scenario-choice").forEach((choice) => choice.classList.toggle("active", choice === button));
        renderSteps();
      });
    });
    document.getElementById("run-scenario").addEventListener("click", () => runScenario(SCENARIOS[selected]));
    renderSteps();
  }

  function runScenario(scenario) {
    const items = [...document.querySelectorAll("#steps .step")];
    const status = document.getElementById("scenario-status");
    const button = document.getElementById("run-scenario");
    button.disabled = true;
    document.querySelectorAll(".scenario-choice").forEach((choice) => { choice.disabled = true; });
    items.forEach((item) => {
      item.classList.remove("done");
      item.querySelector(".step-state").textContent = "Pendiente";
    });
    status.textContent = "";
    items.forEach((item, i) => {
      setTimeout(() => {
        item.classList.add("done");
        item.querySelector(".step-state").textContent = "Completado";
        if (i === items.length - 1) {
          status.textContent = scenario.outcome;
          button.disabled = false;
          document.querySelectorAll(".scenario-choice").forEach((choice) => { choice.disabled = false; });
        }
      }, 600 * (i + 1));
    });
  }

  function renderNotFound(message) {
    view.innerHTML = `
      <div class="card empty">
        <h1>Página no encontrada</h1>
        <p>${esc(message || "La dirección que buscas no existe.")}</p>
        <a class="button" href="#/">Volver al inicio</a>
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
    if (parts[0] === "catalogo") return renderCatalog(params);
    if (parts[0] === "producto" && parts[1]) return renderProduct(decodeURIComponent(parts[1]));
    if (parts[0] === "carrito") return renderCart();
    if (parts[0] === "checkout") return renderCheckout();
    if (parts[0] === "pedido" && parts[1]) return renderOrder(decodeURIComponent(parts[1]));
    if (parts[0] === "seguridad") return renderSecurity();
    return renderNotFound();
  }

  window.addEventListener("hashchange", route);
  route();
})();
