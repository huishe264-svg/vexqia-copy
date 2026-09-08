const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  assert.match(html, /id="appLoading" class="app-loading"/);
  assert.match(html, /id="authScreen" class="auth-screen hidden"/);
  assert.match(html, /await loadAll\(\);renderPage\(currentPage\);hideAppLoading\(\);\$\("protectedApp"\)\.classList\.remove\("hidden"\)/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>new Promise(resolve=>setTimeout(()=>resolve({data:{session:null},error:null}),80)),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{constructor(){}destroy(){} update(){}};`,
  }));

  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`, { waitUntil: "domcontentloaded" });
  const duringSessionCheck = await page.evaluate(() => ({
    loadingVisible: !document.getElementById("appLoading").classList.contains("hidden"),
    authHidden: document.getElementById("authScreen").classList.contains("hidden"),
    appHidden: document.getElementById("protectedApp").classList.contains("hidden"),
  }));
  assert.deepEqual(duringSessionCheck, { loadingVisible: true, authHidden: true, appHidden: true });

  await page.waitForTimeout(120);
  const afterSessionCheck = await page.evaluate(() => ({
    loadingHidden: document.getElementById("appLoading").classList.contains("hidden"),
    authVisible: !document.getElementById("authScreen").classList.contains("hidden"),
    appHidden: document.getElementById("protectedApp").classList.contains("hidden"),
  }));
  assert.deepEqual(afterSessionCheck, { loadingHidden: true, authVisible: true, appHidden: true });

  console.log("Startup loading checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});
