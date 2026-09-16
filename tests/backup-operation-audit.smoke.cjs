const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const migration = fs.readFileSync(path.resolve(__dirname, "../supabase/migrations/20260916140000_store_operation_audit.sql"), "utf8");
  for (const table of ["customers", "employees", "bottles", "schedules", "expenses", "daily_settlements"]) assert.ok(migration.includes(`'${table}'`));
  assert.match(migration, /revoke insert, update, delete on public\.operation_audit_log/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({ contentType: "application/javascript", body: "window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};" }));
    await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({ contentType: "application/javascript", body: "window.Chart=class{constructor(){}destroy(){}update(){}};" }));
    await page.goto("file:///" + path.resolve(__dirname, "../index.html").replaceAll("\\", "/"));
    const result = await page.evaluate(() => {
      currentAuthUser = { id: "owner" }; currentStoreMember = { user_id: "owner", role: "owner" }; platformAdminMode = false; storeId = "store-1"; storeName = "確認店舗";
      renderDataSafetyCard();
      const owner = { backup: Boolean(document.getElementById("downloadStoreBackup")), history: Boolean(document.getElementById("showOperationHistory")) };
      currentStoreMember = { user_id: "manager", role: "manager" }; renderDataSafetyCard();
      return { owner, manager: { backup: Boolean(document.getElementById("downloadStoreBackup")), history: Boolean(document.getElementById("showOperationHistory")) } };
    });
    assert.deepEqual(result.owner, { backup: true, history: true });
    assert.deepEqual(result.manager, { backup: false, history: true });
    console.log("Backup and operation audit test passed.");
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
