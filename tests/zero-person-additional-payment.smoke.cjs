const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const sql = fs.readFileSync(path.resolve(__dirname, "../supabase/migrations/20260916160000_allow_zero_person_supplemental_sales.sql"), "utf8");
  assert.match(sql, /check \(party_size >= 0\)/);
  assert.match(sql, /target_party_size<0/);
  assert.doesNotMatch(sql, /target_party_size<1/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({ contentType: "application/javascript", body: "window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};" }));
    await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({ contentType: "application/javascript", body: "window.Chart=class{constructor(){}destroy(){}update(){}};" }));
    await page.goto("file:///" + path.resolve(__dirname, "../index.html").replaceAll("\\", "/"));
    const result = await page.evaluate(() => {
      const button=document.querySelector('[data-party-size="0"]');button.click();
      return {label:button.textContent.trim(),selected:document.getElementById("partySize").value,active:button.classList.contains("active")};
    });
    assert.equal(result.selected, "0");
    assert.ok(result.active);
    assert.match(result.label, /人数に含めない/);
    console.log("Zero-person additional payment test passed.");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
