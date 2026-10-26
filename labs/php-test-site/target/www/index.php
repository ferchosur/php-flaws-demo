<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="A PHP vulnerability scanner test site for CVE-2026-109618 and CVE-2026-109619, with a link to the Trend Micro security advisory.">
  <meta name="color-scheme" content="dark">
  <title>CVE-2026-109618 CVE-2026-109619 Test Site.</title>
  <style>
    :root { color-scheme: dark; font-family: Arial, Helvetica, sans-serif; background: #000; color: #f4f4f4; }
    * { box-sizing: border-box; }
    body { margin: 0; }
    main { min-height: 100svh; padding: clamp(28px, 5vw, 88px); display: flex; flex-direction: column; }
    .eyebrow { margin: 0 0 clamp(48px, 9vh, 100px); font: 11px/1.6 monospace; letter-spacing: .18em; text-transform: uppercase; color: #a1a1a1; }
    .eyebrow::before { content: ''; display: inline-block; width: 7px; height: 7px; margin-right: 12px; border-radius: 50%; background: #e6ff6b; }
    h1 { margin: 0; font-family: "Arial Black", Arial, Helvetica, sans-serif; font-size: clamp(34px, 7.8vw, 120px); line-height: 1.02; font-weight: 900; letter-spacing: -.065em; -webkit-text-stroke: .018em currentColor; }
    h1 span { display: block; }
    h1 .accent { color: #e6ff6b; }
    .intro { max-width: 650px; margin: 32px 0 0; font-size: clamp(16px, 1.5vw, 20px); line-height: 1.65; color: #a1a1a1; }
    .details { display: flex; gap: 36px; max-width: 880px; margin: 40px 0 32px; }
    .detail { flex: 1; border-top: 1px solid #333; padding-top: 18px; }
    h2 { margin: 0 0 10px; font: 12px/1.6 monospace; letter-spacing: .04em; color: #eee; }
    .detail p { margin: 0; color: #999; font-size: 14px; line-height: 1.7; }
    a { display: inline-flex; align-items: center; gap: 24px; align-self: flex-start; padding: 16px 0 10px; border-bottom: 1px solid #e6ff6b; color: #e6ff6b; text-decoration: none; font-size: 14px; }
    a:hover { color: white; border-color: white; }
    a:focus-visible { outline: 2px solid #e6ff6b; outline-offset: 6px; }
    footer { padding-top: 64px; margin-top: auto; font: 10px/1.7 monospace; letter-spacing: .12em; color: #777; text-transform: uppercase; }
    @media (max-width: 600px) { .details { flex-direction: column; gap: 22px; } .eyebrow { margin-bottom: 48px; } }
  </style>
</head>
<body>
  <main>
    <p class="eyebrow">PHP security research / scanner test environment</p>
    <h1><span>CVE-2026-109618</span><span>CVE-2026-109619</span><span class="accent">Test Site.</span></h1>
    <p class="intro">Two critical PHP vulnerabilities. A dedicated target for testing vulnerability scanner detection. Trend Micro reports that both flaws can allow unauthenticated remote code execution as the web worker account.</p>
    <section class="details" aria-label="Vulnerability overview">
      <div class="detail">
        <h2>CVE-2026-109618</h2>
        <p>Memory corruption associated with an out-of-memory condition can lead to remote code execution.</p>
      </div>
      <div class="detail">
        <h2>CVE-2026-109619</h2>
        <p>Stale global state in PHP can lead to remote code execution when handling web requests.</p>
      </div>
    </section>
    <a href="https://success.trendmicro.com/en-US/solution/KA-0024789" target="_blank" rel="noopener noreferrer">Read the Trend Micro advisory <span aria-hidden="true">↗</span></a>
    <footer>Scanner lab &nbsp;/&nbsp; PHP <?= htmlspecialchars(PHP_VERSION, ENT_QUOTES, 'UTF-8') ?> &nbsp;/&nbsp; on-prem</footer>
  </main>
</body>
</html>
