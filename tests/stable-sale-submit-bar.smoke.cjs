const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{destroy(){} update(){}};`,
  }));
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(() => {
    document.getElementById("appLoading").classList.add("hidden");
    document.getElementById("protectedApp").classList.remove("hidden");
    document.getElementById("page-home").classList.remove("active");
    document.getElementById("page-input").classList.add("active");
    customers = [{ id: "customer-1", name: "テスト顧客" }];
    document.getElementById("customerId").value = "";
    document.getElementById("employeeSelect").innerHTML = '<option value="employee-1">担当</option>';
    document.getElementById("employeeSelect").value = "";
    document.getElementById("partySize").value = "";
    document.getElementById("totalAmount").value = "";
    selectedPaymentStatus = "";
    selectedPaymentMethod = "";
    updateSaleSubmitSummary();
    const bar = document.querySelector(".sticky-save");
    const panel = document.querySelector(".sticky-save-panel");
    const emptyHeight = panel.getBoundingClientRect().height;
    const hiddenInitially = !bar.classList.contains("ready") && bar.getAttribute("aria-hidden") === "true";
    document.getElementById("customerId").value = "customer-1";
    document.getElementById("totalAmount").value = "38000";
    selectedPaymentStatus = "回収済み";
    selectedPaymentMethod = "カード";
    updateSaleSubmitSummary();
    const hiddenWhenPartial = !bar.classList.contains("ready");
    document.getElementById("employeeSelect").value = "employee-1";
    document.getElementById("partySize").value = "1";
    updateSaleSubmitSummary();
    const completedHeight = panel.getBoundingClientRect().height;
    return {
      hiddenInitially,
      hiddenWhenPartial,
      visibleWhenComplete: bar.classList.contains("ready") && bar.getAttribute("aria-hidden") === "false",
      heightStable: Math.abs(emptyHeight - completedHeight) < 1,
      emptyHeight,
      completedHeight,
      singleLine: getComputedStyle(document.getElementById("saleSubmitSummary")).whiteSpace === "nowrap",
    };
  });

  assert.equal(result.hiddenInitially, true, JSON.stringify(result));
  assert.equal(result.hiddenWhenPartial, true, JSON.stringify(result));
  assert.equal(result.visibleWhenComplete, true, JSON.stringify(result));
  assert.equal(result.heightStable, true, JSON.stringify(result));
  assert.equal(result.singleLine, true, JSON.stringify(result));
  await browser.close();
  console.log("stable sale submit bar checks passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
