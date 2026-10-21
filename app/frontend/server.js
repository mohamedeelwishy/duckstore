/**
 * Duck Store — Frontend
 * ---------------------------------------------------------------------------
 * Runs in the `frontend` namespace. Owns all HTML, CSS and SVG.
 * Proxies catalogue and order calls to the backend API over cluster DNS.
 */

const express = require("express");

const app = express();
const PORT = Number(process.env.PORT || 3000);
const BACKEND_URL =
  process.env.BACKEND_URL || "http://duck-api.backend.svc.cluster.local:3000";

app.use(express.json());

app.use((req, res, next) => {
  const started = Date.now();
  res.on("finish", () =>
    console.log(`[web] ${req.method} ${req.originalUrl} -> ${res.statusCode} (${Date.now() - started}ms)`)
  );
  next();
});

/* ==========================================================================
   BACKEND CLIENT
   ========================================================================== */

async function api(pathname, options = {}) {
  const res = await fetch(`${BACKEND_URL}${pathname}`, {
    signal: AbortSignal.timeout(5000),
    headers: { "content-type": "application/json" },
    ...options,
  });

  if (!res.ok) {
    const err = new Error(`backend responded ${res.status} for ${pathname}`);
    err.status = res.status;
    throw err;
  }
  return res.json();
}

/* ==========================================================================
   DUCK ARTWORK (inline SVG)
   ========================================================================== */

function accessories(id) {
  return {
    classic: { behind: "", front: "" },

    ninja: {
      behind: `<g transform="rotate(-12.9 105 150)">
          <rect x="105" y="145" width="246" height="10" rx="5" fill="#CBD5E0"/>
          <rect x="70" y="139" width="36" height="22" rx="6" fill="#232A35"/>
          <rect x="106" y="137" width="7" height="26" rx="3" fill="#8A97A6"/>
        </g>`,
      front: `<g clip-path="url(#head${id})" fill="#232A35">
          <rect x="186" y="98" width="134" height="44"/>
          <rect x="186" y="170" width="134" height="72"/>
        </g>
        <path d="M198 152 q -46 4 -62 32 q 34 -12 62 -14 z" fill="#232A35"/>`,
    },

    pirate: {
      behind: "",
      front: `<path d="M180 126 q 72 -70 146 -2 q 10 12 -10 12 q -22 -10 -32 4 q -34 -22 -70 0 q -10 -14 -26 -4 q -18 0 -8 -10 z" fill="#2E3A46"/>
        <circle cx="252" cy="108" r="9" fill="#FFF8E1"/>
        <path d="M212 140 q 42 -12 82 4" stroke="#2E3A46" stroke-width="6" fill="none" stroke-linecap="round"/>
        <ellipse cx="270" cy="156" rx="16" ry="13" fill="#2E3A46"/>`,
    },

    caped: {
      behind: `<path d="M254 164 q -34 136 -182 172 q 24 -34 0 -46 q 34 -8 26 -44 q 36 -4 30 -42 q 40 2 44 -44 z" fill="#2E3A46"/>`,
      front: `<path d="M210 134 q 52 -16 96 6 q 8 6 -2 12 q -14 24 -38 12 q -14 -10 -26 -2 q -24 6 -30 -28 z" fill="#2E3A46"/>
        <circle cx="270" cy="152" r="7" fill="#FFF8E1"/>
        <rect x="146" y="282" width="96" height="16" rx="8" fill="#FFD93D"/>
        <rect x="182" y="284" width="22" height="12" rx="4" fill="#2E3A46"/>`,
    },

    astronaut: {
      behind: `<rect x="326" y="206" width="7" height="136" rx="3" fill="#B9C6D2"/>
        <path d="M333 212 h 48 v 32 h -48 z" fill="#FFD93D"/>`,
      front: `<ellipse cx="266" cy="168" rx="100" ry="92" fill="#DFF3FF" opacity=".32" stroke="#BFE5F8" stroke-width="7"/>
        <path d="M206 116 q 32 -28 70 -22" stroke="#FFFFFF" stroke-width="11" fill="none" stroke-linecap="round" opacity=".85"/>
        <rect x="160" y="238" width="96" height="18" rx="9" fill="#E3EAF1"/>`,
    },

    chef: {
      behind: "",
      front: `<g fill="#FFFDF7" stroke="#E0D8C6" stroke-width="3">
          <circle cx="220" cy="88" r="25"/>
          <circle cx="252" cy="74" r="29"/>
          <circle cx="286" cy="90" r="23"/>
          <rect x="210" y="98" width="84" height="28" rx="9"/>
        </g>
        <path d="M212 116 h 80" stroke="#E0D8C6" stroke-width="3"/>`,
    },

    rockstar: {
      behind: "",
      front: `<g transform="rotate(-14 150 298)">
          <ellipse cx="148" cy="298" rx="46" ry="38" fill="#C86BFA"/>
          <ellipse cx="148" cy="298" rx="46" ry="38" fill="none" stroke="#5E2A82" stroke-width="4"/>
          <rect x="150" y="291" width="152" height="14" rx="6" fill="#8B5E3C"/>
          <rect x="296" y="284" width="26" height="28" rx="6" fill="#5E2A82"/>
          <circle cx="160" cy="298" r="13" fill="#5E2A82"/>
          <path d="M176 294 h 122 M176 302 h 122" stroke="#F1E3FF" stroke-width="2.5"/>
        </g>
        <g fill="#1B2430">
          <rect x="234" y="138" width="46" height="28" rx="11"/>
          <rect x="286" y="138" width="38" height="26" rx="11"/>
          <rect x="278" y="146" width="10" height="7"/>
          <rect x="192" y="146" width="46" height="8" rx="4"/>
        </g>`,
    },

    detective: {
      behind: "",
      front: `<path d="M194 122 q 58 -48 116 -2 q 8 10 -8 12 h -108 q -14 -2 0 -10 z" fill="#7D8F82"/>
        <path d="M300 128 q 42 4 46 16 q -48 8 -52 -8 z" fill="#66786C"/>
        <g transform="rotate(30 316 276)">
          <rect x="300" y="300" width="14" height="70" rx="7" fill="#8B5E3C"/>
          <circle cx="307" cy="276" r="40" fill="#EAF7FF" opacity=".65"/>
          <circle cx="307" cy="276" r="40" fill="none" stroke="#B9C6D2" stroke-width="9"/>
        </g>`,
    },
  };
}

function duckArt(duck) {
  const id = duck.id;
  const acc = accessories(id)[duck.theme] || { behind: "", front: "" };
  const shade = "rgba(0,0,0,.09)";
  const edge = duck.outline ? ` stroke="${duck.outline}" stroke-width="5"` : "";

  return /* html */ `
  <svg viewBox="0 0 400 400" role="img" aria-label="Illustration of ${duck.name}" xmlns="http://www.w3.org/2000/svg">
    <defs>
      <linearGradient id="bg${id}" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="${duck.bg}"/>
        <stop offset="100%" stop-color="#FFFFFF"/>
      </linearGradient>
      <clipPath id="head${id}"><circle cx="252" cy="172" r="64"/></clipPath>
    </defs>

    <rect width="400" height="400" fill="url(#bg${id})"/>
    <circle cx="200" cy="205" r="152" fill="#FFFFFF" opacity=".38"/>

    <circle cx="74" cy="132" r="15" fill="#FFFFFF" opacity=".7"/>
    <circle cx="106" cy="92" r="9" fill="#FFFFFF" opacity=".55"/>
    <circle cx="344" cy="104" r="12" fill="#FFFFFF" opacity=".6"/>

    ${acc.behind}

    <path d="M96 232 q -48 -26 -44 18 q -24 6 14 24 z" fill="${duck.body}"${edge}/>
    <ellipse cx="195" cy="262" rx="118" ry="80" fill="${duck.body}"${edge}/>
    <path d="M142 252 q 58 -34 112 4 q -48 48 -112 -4 z" fill="${shade}"/>
    <circle cx="252" cy="172" r="64" fill="${duck.body}"${edge}/>
    <path d="M300 164 q 54 4 58 20 q -4 18 -58 18 q -7 -19 0 -38 z" fill="#F5A623"/>
    <path d="M304 186 q 40 4 52 2" stroke="#D98B10" stroke-width="4" fill="none" stroke-linecap="round"/>
    <circle cx="270" cy="152" r="9" fill="#1B3A57"/>
    <circle cx="273" cy="149" r="3" fill="#FFFFFF"/>
    <ellipse cx="236" cy="188" rx="15" ry="10" fill="#FF9AA2" opacity=".55"/>

    ${acc.front}

    <ellipse cx="200" cy="344" rx="168" ry="22" fill="#9AD5F0" opacity=".55"/>
    <path d="M40 356 q 30 -12 60 0 q 30 12 60 0 q 30 -12 60 0 q 30 12 60 0 q 30 -12 60 0" stroke="#7FC7E8" stroke-width="6" fill="none" stroke-linecap="round" opacity=".6"/>
  </svg>`;
}

/* ==========================================================================
   SHARED STYLES + LAYOUT SHELL
   ========================================================================== */

const styles = /* css */ `
  :root {
    --yellow: #FFD93D;
    --yellow-deep: #F5C000;
    --blue-soft: #9AD5F0;
    --blue-mist: #E6F5FC;
    --navy: #1B3A57;
    --white: #FFFFFF;
    --cream: #FFFBF0;
    --grey: #6B7A88;
    --shadow: 0 10px 30px rgba(27, 58, 87, 0.10);
    --shadow-lift: 0 18px 40px rgba(27, 58, 87, 0.18);
    --radius: 22px;
  }

  * { margin: 0; padding: 0; box-sizing: border-box; }

  body {
    font-family: 'Baloo 2', 'Trebuchet MS', system-ui, sans-serif;
    background: var(--cream);
    color: var(--navy);
    line-height: 1.6;
    -webkit-font-smoothing: antialiased;
  }

  a { text-decoration: none; color: inherit; }
  img { display: block; max-width: 100%; }

  .wrap { width: min(1150px, 92vw); margin: 0 auto; }

  /* ---------- Header ---------- */
  header {
    position: sticky; top: 0; z-index: 50;
    background: rgba(255, 255, 255, 0.85);
    backdrop-filter: blur(10px);
    border-bottom: 3px solid var(--yellow);
  }
  .nav {
    display: flex; align-items: center; justify-content: space-between;
    padding: 14px 0; gap: 16px;
  }
  .logo { display: flex; align-items: center; gap: 10px; font-size: 1.45rem; font-weight: 800; }
  .logo .egg {
    width: 42px; height: 42px; display: grid; place-items: center;
    background: var(--yellow); border-radius: 50%; font-size: 1.3rem;
    box-shadow: 0 4px 0 var(--yellow-deep);
  }
  .nav-links { display: flex; align-items: center; gap: 22px; font-weight: 600; }
  .nav-links a { color: var(--grey); transition: color .2s; }
  .nav-links a:hover { color: var(--navy); }
  .cart-pill {
    background: var(--navy); color: var(--white);
    padding: 8px 16px; border-radius: 999px; font-weight: 700; font-size: .95rem;
  }
  .cart-pill span { color: var(--yellow); }

  /* ---------- Hero ---------- */
  .hero {
    background: linear-gradient(160deg, var(--blue-mist) 0%, var(--white) 65%);
    border-radius: var(--radius);
    margin: 28px 0 46px;
    padding: 58px 42px;
    display: grid; grid-template-columns: 1fr; gap: 30px; align-items: center;
    box-shadow: var(--shadow); overflow: hidden; position: relative;
  }
  .hero::after {
    content: ""; position: absolute; width: 320px; height: 320px; border-radius: 50%;
    background: var(--yellow); opacity: .18; right: -80px; top: -110px;
  }
  .kicker {
    display: inline-block; background: var(--yellow); color: var(--navy);
    padding: 5px 15px; border-radius: 999px; font-weight: 700;
    font-size: .82rem; letter-spacing: .06em; text-transform: uppercase; margin-bottom: 14px;
  }
  .hero h1 { font-size: clamp(2.1rem, 5vw, 3.4rem); line-height: 1.1; font-weight: 800; }
  .hero h1 em { font-style: normal; color: var(--yellow-deep); }
  .hero p { color: var(--grey); font-size: 1.08rem; margin: 16px 0 26px; max-width: 46ch; }

  /* ---------- Buttons ---------- */
  .btn {
    display: inline-block; border: none; cursor: pointer; font-family: inherit;
    font-weight: 700; font-size: 1rem; padding: 13px 26px; border-radius: 999px;
    transition: transform .15s ease, box-shadow .15s ease;
  }
  .btn-primary { background: var(--yellow); color: var(--navy); box-shadow: 0 5px 0 var(--yellow-deep); }
  .btn-primary:hover { transform: translateY(-3px); box-shadow: 0 8px 0 var(--yellow-deep); }
  .btn-primary:active { transform: translateY(2px); box-shadow: 0 2px 0 var(--yellow-deep); }
  .btn-primary[disabled] { opacity: .55; cursor: not-allowed; transform: none; box-shadow: 0 5px 0 var(--yellow-deep); }
  .btn-ghost { background: var(--white); color: var(--navy); border: 2px solid var(--blue-soft); }
  .btn-ghost:hover { background: var(--blue-mist); transform: translateY(-2px); }
  .btn-block { width: 100%; text-align: center; }

  /* ---------- Section heading ---------- */
  .section-head { text-align: center; margin-bottom: 30px; }
  .section-head h2 { font-size: 2rem; font-weight: 800; }
  .section-head p { color: var(--grey); }

  /* ---------- Product grid ---------- */
  .grid {
    display: grid; gap: 26px;
    grid-template-columns: repeat(auto-fill, minmax(255px, 1fr));
    margin-bottom: 60px;
  }
  .card {
    background: var(--white); border-radius: var(--radius); overflow: hidden;
    box-shadow: var(--shadow); display: flex; flex-direction: column;
    transition: transform .22s ease, box-shadow .22s ease;
  }
  .card:hover { transform: translateY(-8px); box-shadow: var(--shadow-lift); }
  .card-media { position: relative; aspect-ratio: 1 / 1; background: var(--blue-mist); }
  .card-media img,
  .card-media svg { width: 100%; height: 100%; object-fit: cover; display: block; }
  .badge {
    position: absolute; top: 12px; left: 12px; background: var(--navy); color: var(--white);
    font-size: .72rem; font-weight: 700; letter-spacing: .05em; text-transform: uppercase;
    padding: 5px 12px; border-radius: 999px;
  }
  .badge.sold-out { background: #C1483F; right: 12px; left: auto; }
  .card-body { padding: 18px 20px 22px; display: flex; flex-direction: column; gap: 6px; flex: 1; }
  .card-body h3 { font-size: 1.25rem; font-weight: 800; }
  .card-body .tagline { color: var(--grey); font-size: .93rem; flex: 1; }
  .price-row { display: flex; align-items: center; justify-content: space-between; margin-top: 10px; }
  .price { font-size: 1.35rem; font-weight: 800; color: var(--navy); }
  .price small { font-size: .85rem; color: var(--grey); font-weight: 600; }

  /* ---------- Product detail ---------- */
  .back-link { display: inline-block; margin: 26px 0 18px; color: var(--grey); font-weight: 600; }
  .back-link:hover { color: var(--navy); }
  .detail {
    display: grid; grid-template-columns: 1fr 1fr; gap: 44px; align-items: start;
    background: var(--white); border-radius: var(--radius); padding: 32px;
    box-shadow: var(--shadow); margin-bottom: 56px;
  }
  .detail-media { border-radius: 18px; overflow: hidden; background: var(--blue-mist); aspect-ratio: 1 / 1; }
  .detail-media img,
  .detail-media svg { width: 100%; height: 100%; object-fit: cover; display: block; }
  .detail h1 { font-size: clamp(1.9rem, 4vw, 2.7rem); font-weight: 800; line-height: 1.15; }
  .detail .tagline { color: var(--yellow-deep); font-weight: 700; font-size: 1.05rem; }
  .detail p.desc { color: var(--grey); margin: 16px 0 20px; }
  .detail .price { font-size: 2.2rem; display: block; margin-bottom: 18px; }
  .features { list-style: none; display: grid; gap: 8px; margin-bottom: 26px; }
  .features li { display: flex; gap: 10px; align-items: center; font-weight: 600; }
  .features li::before {
    content: "•"; width: 22px; height: 22px; flex: none; display: grid; place-items: center;
    background: var(--yellow); color: var(--navy); border-radius: 50%; font-size: .8rem;
  }
  .buy-row { display: flex; gap: 12px; flex-wrap: wrap; }

  /* ---------- Footer ---------- */
  footer {
    background: var(--navy); color: var(--blue-mist); padding: 34px 0; margin-top: 20px;
    text-align: center;
  }
  footer p { font-size: .92rem; opacity: .85; }
  footer .served { font-size: .78rem; opacity: .5; margin-top: 6px; font-family: ui-monospace, monospace; }

  /* ---------- Empty / error ---------- */
  .empty { text-align: center; padding: 80px 0; }
  .empty .big { font-size: 3rem; font-weight: 800; }
  .empty h1 { font-size: 2rem; margin-bottom: 8px; }
  .empty p { color: var(--grey); margin-bottom: 22px; }
  .empty code {
    display: inline-block; margin-top: 14px; padding: 8px 14px; border-radius: 8px;
    background: #FDEEEC; color: #9B3128; font-family: ui-monospace, monospace; font-size: .85rem;
  }

  /* ---------- Responsive ---------- */
  @media (max-width: 860px) {
    .hero { padding: 40px 26px; text-align: center; }
    .hero p { margin-inline: auto; }
    .detail { grid-template-columns: 1fr; gap: 26px; padding: 22px; }
  }
  @media (max-width: 560px) {
    .nav-links a:not(.cart-pill) { display: none; }
    .grid { grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: 16px; }
    .card-body { padding: 14px 15px 18px; }
    .card-body h3 { font-size: 1.05rem; }
  }
`;

const clientScript = /* js */ `
  function getCart() { return Number(localStorage.getItem('duckCart') || 0); }
  function paintCart() {
    var el = document.getElementById('cart-count');
    if (el) el.textContent = getCart();
  }

  async function buyNow(button, productId) {
    button.disabled = true;
    try {
      const res = await fetch('/cart/add', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ productId: productId, quantity: 1 })
      });
      if (!res.ok) throw new Error('order failed');
      const order = await res.json();
      localStorage.setItem('duckCart', getCart() + 1);
      paintCart();
      alert('Order placed successfully. Order #' + order.orderId + ' — $' + order.total);
    } catch (err) {
      alert('Unable to process order. Please try again.');
    } finally {
      button.disabled = false;
    }
  }

  document.addEventListener('DOMContentLoaded', paintCart);
`;

function layout(title, content) {
  return /* html */ `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${title} | Duck Store</title>
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Baloo+2:wght@400;600;700;800&display=swap" rel="stylesheet" />
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='40' fill='%23FFD93D'/></svg>" />
  <style>${styles}</style>
</head>
<body>
  <header>
    <div class="wrap nav">
      <a href="/" class="logo"><span class="egg">D</span> Duck&amp;Co.</a>
      <nav class="nav-links">
        <a href="/">Home</a>
        <a href="/#shop">Shop</a>
        <a href="/#shop" class="cart-pill">Cart <span id="cart-count">0</span></a>
      </nav>
    </div>
  </header>

  <main class="wrap">
    ${content}
  </main>

  <footer>
    <div class="wrap">
      <p>Duck&amp;Co. Demo application.</p>
      <p class="served">served by ${process.env.HOSTNAME || "localhost"}</p>
    </div>
  </footer>

  <script>${clientScript}</script>
</body>
</html>`;
}

function duckCard(duck) {
  return /* html */ `
    <article class="card">
      <div class="card-media">
        <span class="badge">${duck.badge}</span>
        ${duck.availability === "sold_out" ? '<span class="badge sold-out">Sold out</span>' : ""}
        ${duckArt(duck)}
      </div>
      <div class="card-body">
        <h3>${duck.name}</h3>
        <p class="tagline">${duck.tagline}</p>
        <div class="price-row">
          <span class="price">$${duck.price}</span>
        </div>
        <a class="btn btn-primary btn-block" href="/duck/${duck.id}" style="margin-top:12px">View Details</a>
      </div>
    </article>`;
}

function backendDownPage(err) {
  return layout(
    "Service unavailable",
    /* html */ `
    <div class="empty">
      <div class="big">503</div>
      <h1>Service Temporarily Unavailable</h1>
      <p>The catalogue service is currently unreachable. Please retry shortly.</p>
      <a href="/" class="btn btn-primary">Try again</a>
      <div><code>${BACKEND_URL} — ${err.message}</code></div>
    </div>`
  );
}

/* ==========================================================================
   ROUTES
   ========================================================================== */

app.get("/healthz", (req, res) => res.json({ status: "ok", backend: BACKEND_URL }));

app.get("/", async (req, res) => {
  let ducks;
  try {
    ducks = await api("/api/ducks");
  } catch (err) {
    console.error("[web] backend unreachable:", err.message);
    return res.status(503).send(backendDownPage(err));
  }

  const page = /* html */ `
    <section class="hero">
      <div>
        <span class="kicker">Free shipping over $40</span>
        <h1>Engineered rubber ducks for development and production.</h1>
        <p>
          Catalogue of collectible debugging ducks with persistent data storage and decoupled microservices architecture.
        </p>
        <a href="#shop" class="btn btn-primary">Shop catalogue</a>
      </div>
    </section>

    <section id="shop">
      <div class="section-head">
        <h2>Catalogue</h2>
        <p>${ducks.length} ducks in stock.</p>
      </div>
      <div class="grid">
        ${ducks.map(duckCard).join("")}
      </div>
    </section>`;

  res.send(layout("Home", page));
});

app.get("/duck/:id", async (req, res) => {
  let duck, related;
  try {
    [duck, related] = await Promise.all([
      api(`/api/ducks/${encodeURIComponent(req.params.id)}`),
      api(`/api/ducks/${encodeURIComponent(req.params.id)}/related`),
    ]);
  } catch (err) {
    if (err.status === 404) {
      return res.status(404).send(
        layout(
          "Duck not found",
          /* html */ `
          <div class="empty">
            <div class="big">404</div>
            <h1>Product Not Found</h1>
            <p>The requested product could not be located.</p>
            <a href="/" class="btn btn-primary">Back to catalogue</a>
          </div>`
        )
      );
    }
    console.error("[web] backend unreachable:", err.message);
    return res.status(503).send(backendDownPage(err));
  }

  const soldOut = duck.availability === "sold_out";

  const page = /* html */ `
    <a href="/" class="back-link">← Back to all products</a>

    <section class="detail">
      <div class="detail-media">
        ${duckArt(duck)}
      </div>
      <div>
        <p class="tagline">${duck.tagline}</p>
        <h1>${duck.name}</h1>
        <p class="desc">${duck.description}</p>
        <span class="price">$${duck.price}</span>
        <ul class="features">
          ${duck.features.map((f) => `<li>${f}</li>`).join("")}
        </ul>
        <div class="buy-row">
          <button class="btn btn-primary" ${soldOut ? "disabled" : ""}
                  onclick="buyNow(this, ${duck.id})">
            ${soldOut ? "Sold out" : "Buy Now"}
          </button>
          <a href="/" class="btn btn-ghost">Keep browsing</a>
        </div>
      </div>
    </section>

    <section>
      <div class="section-head">
        <h2>Related Products</h2>
      </div>
      <div class="grid">
        ${related.map(duckCard).join("")}
      </div>
    </section>`;

  res.send(layout(duck.name, page));
});

app.post("/cart/add", async (req, res) => {
  try {
    const order = await api("/api/orders", {
      method: "POST",
      body: JSON.stringify({
        productId: Number(req.body?.productId),
        quantity: Number(req.body?.quantity ?? 1),
      }),
    });
    res.status(201).json(order);
  } catch (err) {
    console.error("[web] order failed:", err.message);
    res.status(err.status === 404 ? 404 : 502).json({ error: "could not place order" });
  }
});

app.use((req, res) => {
  res.status(404).send(
    layout(
      "Page not found",
      /* html */ `
      <div class="empty">
        <div class="big">404</div>
        <h1>404 — Not Found</h1>
        <p>The requested page does not exist.</p>
        <a href="/" class="btn btn-primary">Return Home</a>
      </div>`
    )
  );
});

const server = app.listen(PORT, "0.0.0.0", () => {
  console.log(`[web] duck-web listening on 0.0.0.0:${PORT}`);
  console.log(`[web] backend is ${BACKEND_URL}`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => {
    console.log(`[web] ${signal} received, shutting down`);
    server.close(() => process.exit(0));
  });
}
