const http = require("http");

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>MEDSAI / ISTSEH — iOS Medication Care App</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #0a0e1a;
      color: #e8eaf0;
      min-height: 100vh;
    }
    header {
      background: linear-gradient(135deg, #1a4a2e 0%, #0d2d1e 100%);
      padding: 48px 32px 40px;
      text-align: center;
      border-bottom: 1px solid #2a5a3a;
    }
    header h1 {
      font-size: 2.6rem;
      font-weight: 700;
      color: #4ade80;
      letter-spacing: -0.5px;
    }
    header p.subtitle {
      margin-top: 10px;
      font-size: 1.1rem;
      color: #a7f3d0;
      opacity: 0.85;
    }
    .badge {
      display: inline-block;
      margin-top: 16px;
      padding: 6px 16px;
      border-radius: 20px;
      font-size: 0.82rem;
      font-weight: 600;
      background: #14532d;
      color: #86efac;
      border: 1px solid #166534;
    }
    main {
      max-width: 960px;
      margin: 0 auto;
      padding: 40px 24px 60px;
    }
    .notice {
      background: #1e2a3a;
      border: 1px solid #2d4a6a;
      border-left: 4px solid #60a5fa;
      border-radius: 8px;
      padding: 18px 22px;
      margin-bottom: 36px;
      font-size: 0.95rem;
      color: #bfdbfe;
      line-height: 1.6;
    }
    .notice strong { color: #93c5fd; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      gap: 20px;
      margin-bottom: 36px;
    }
    .card {
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 12px;
      padding: 24px;
    }
    .card h3 {
      font-size: 1rem;
      font-weight: 600;
      color: #4ade80;
      margin-bottom: 12px;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .card ul {
      list-style: none;
      padding: 0;
    }
    .card ul li {
      font-size: 0.875rem;
      color: #9ca3af;
      padding: 4px 0;
      border-bottom: 1px solid #1f2937;
    }
    .card ul li:last-child { border-bottom: none; }
    .card ul li strong { color: #d1d5db; }
    .section-title {
      font-size: 1.3rem;
      font-weight: 700;
      color: #e5e7eb;
      margin: 36px 0 16px;
      padding-bottom: 8px;
      border-bottom: 1px solid #1f2937;
    }
    .fn-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
      gap: 12px;
    }
    .fn-card {
      background: #111827;
      border: 1px solid #1f2937;
      border-radius: 8px;
      padding: 14px 16px;
    }
    .fn-card .fn-name {
      font-size: 0.85rem;
      font-weight: 600;
      color: #a78bfa;
      font-family: "SF Mono", "Fira Code", monospace;
    }
    .fn-card .fn-desc {
      font-size: 0.78rem;
      color: #6b7280;
      margin-top: 4px;
    }
    footer {
      text-align: center;
      padding: 24px;
      font-size: 0.8rem;
      color: #374151;
      border-top: 1px solid #1f2937;
    }
  </style>
</head>
<body>
  <header>
    <h1>MEDSAI · ISTSEH</h1>
    <p class="subtitle">iOS Medication Management &amp; Care Platform</p>
    <span class="badge">SwiftUI · Supabase · Firebase · OpenAI</span>
  </header>
  <main>
    <div class="notice">
      <strong>Note:</strong> This is an <strong>iOS/SwiftUI native application</strong>. It runs on iPhone/iPad via Xcode and cannot be previewed in a web browser. This page provides a project overview and documentation of the backend API functions.
    </div>

    <div class="grid">
      <div class="card">
        <h3>📱 Platform</h3>
        <ul>
          <li><strong>Target:</strong> iOS 16.0+</li>
          <li><strong>Language:</strong> Swift / SwiftUI</li>
          <li><strong>Build:</strong> Xcode + Swift Package Manager</li>
          <li><strong>Architecture:</strong> MVVM + Combine</li>
        </ul>
      </div>
      <div class="card">
        <h3>🗄️ Backend</h3>
        <ul>
          <li><strong>Database:</strong> Supabase (PostgreSQL)</li>
          <li><strong>Auth:</strong> Supabase Auth</li>
          <li><strong>Edge Functions:</strong> Deno/TypeScript</li>
          <li><strong>Legacy:</strong> Firebase Functions</li>
        </ul>
      </div>
      <div class="card">
        <h3>🤖 AI &amp; APIs</h3>
        <ul>
          <li><strong>LLM:</strong> OpenAI GPT-4o-mini</li>
          <li><strong>Drug Data:</strong> RxNav (NIH)</li>
          <li><strong>Education:</strong> MedlinePlus</li>
          <li><strong>Safety:</strong> OpenFDA</li>
        </ul>
      </div>
      <div class="card">
        <h3>✅ Working Features</h3>
        <ul>
          <li>Duplicate ingredient badges</li>
          <li>Medication schedule generation</li>
          <li>Caregiver / patient roles</li>
          <li>Care code redemption</li>
          <li>OCR / camera medication scan</li>
        </ul>
      </div>
    </div>

    <div class="section-title">Supabase Edge Functions</div>
    <div class="fn-grid">
      <div class="fn-card"><div class="fn-name">check-interactions</div><div class="fn-desc">Drug safety: duplicates, allergies, interactions</div></div>
      <div class="fn-card"><div class="fn-name">drug-intel</div><div class="fn-desc">AI-powered medication information lookup</div></div>
      <div class="fn-card"><div class="fn-name">image-to-drug</div><div class="fn-desc">OCR + AI medication image recognition</div></div>
      <div class="fn-card"><div class="fn-name">parse-schedule</div><div class="fn-desc">AI schedule parsing from natural language</div></div>
      <div class="fn-card"><div class="fn-name">patient-medications</div><div class="fn-desc">CRUD for patient medication records</div></div>
      <div class="fn-card"><div class="fn-name">patient-profile</div><div class="fn-desc">Patient profile &amp; medical info</div></div>
      <div class="fn-card"><div class="fn-name">redeem-care-code</div><div class="fn-desc">Patient ↔ caregiver linking</div></div>
      <div class="fn-card"><div class="fn-name">create-family-member</div><div class="fn-desc">Add caregiver family members</div></div>
      <div class="fn-card"><div class="fn-name">list-patient-devices</div><div class="fn-desc">Device management for patients</div></div>
      <div class="fn-card"><div class="fn-name">revoke-patient-device</div><div class="fn-desc">Revoke device access</div></div>
      <div class="fn-card"><div class="fn-name">transfer-patient</div><div class="fn-desc">Transfer patient between caregivers</div></div>
    </div>

    <div class="section-title">Firebase Cloud Function</div>
    <div class="fn-grid">
      <div class="fn-card"><div class="fn-name">drugIntel (v2)</div><div class="fn-desc">POST /drugIntel — GPT-4o-mini medication JSON</div></div>
    </div>

    <div class="section-title">Database Migrations</div>
    <div class="fn-grid">
      <div class="fn-card"><div class="fn-name">2026-03-26</div><div class="fn-desc">Fix Supabase writes</div></div>
      <div class="fn-card"><div class="fn-name">2026-04-18</div><div class="fn-desc">Caregiver enhancements + status</div></div>
      <div class="fn-card"><div class="fn-name">2026-05-05</div><div class="fn-desc">Caregiver calendar permissions + RLS</div></div>
      <div class="fn-card"><div class="fn-name">2026-05-09</div><div class="fn-desc">Backend foundation + care code hardening</div></div>
      <div class="fn-card"><div class="fn-name">2026-05-10</div><div class="fn-desc">Schema sync + medication scheduling</div></div>
    </div>
  </main>
  <footer>MEDSAI / ISTSEH &mdash; iOS Medication Care App &mdash; Supabase + Firebase + OpenAI</footer>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(html);
});

server.listen(5000, "0.0.0.0", () => {
  console.log("MEDSAI project overview running on http://0.0.0.0:5000");
});
