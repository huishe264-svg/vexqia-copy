const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260902100000_revise_settlement_totals_and_cash_flow.sql"), "utf8");

  assert.match(migration, /after_register := before_register \+ cash_net_amount/);
  assert.match(migration, /gross_amount - extras_amount,/);
  assert.match(migration, /'settlement', cash_net_amount/);
  assert.match(migration, /0, 0, 0,/);
  assert.match(html, /bottom:calc\(84px \+ env\(safe-area-inset-bottom\)\)/);
  assert.doesNotMatch(html, /id="recentCustomerBlock"/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{constructor(canvas,config){this.canvas=canvas;this.config=config}destroy(){} update(){}};`,
  }));
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(async () => {
    currentAuthUser = { id: "owner-1" };
    currentStoreMember = { user_id: "owner-1", role: "owner" };
    storeMembers = [currentStoreMember];
    customers = [{ id: "customer-1", name: "田中", name_kana: "たなか", employee_id: "employee-1", notes: "VIP", is_active: true }];
    employees = [{ id: "employee-1", name: "口座A" }];
    businessDayClosures = [{ business_date: "2026-09-01" }];
    sales = [{ id: "sale-1", business_date: "2026-09-01", customer_id: "customer-1", employee_id: "employee-1", payment_status: "回収済み", payment_method: "現金", total_amount: 100000, delivery_tobacco_amount: 10000, party_size: 2, is_settled: true }];
    settlements = [{ business_date: "2026-09-01", settled_total_amount: 100000, settled_delivery_tobacco_amount: 10000, settled_net_amount: 90000, settled_cash_amount: 100000, settled_cash_net_amount: 85000, consumables_amount: 5000, settled_sale_ids: ["sale-1"] }];
    cashRegister = { base_amount: 50000, current_amount: 130000 };
    cashRegisterHistory = [
      { action: "settlement", amount_delta: 85000, balance_after: 135000, business_date: "2026-09-01", created_by: "owner-1", created_at: "2026-09-02T01:00:00Z" },
      { action: "reset", amount_delta: -85000, balance_after: 50000, created_by: "owner-1", created_at: "2026-09-02T02:00:00Z" },
    ];

    renderSalesDay("2026-09-01");
    renderCashRegister();
    document.querySelector('[data-party-size="3"]').click();

    let insertCalls = 0;
    appConfirm = async () => false;
    db.from = () => ({ insert: () => { insertCalls += 1; return { select: () => ({ single: async () => ({ data: null, error: null }) }) }; } });
    document.getElementById("newCustomerName").value = "田中";
    document.getElementById("newCustomerKana").value = "たなか";
    document.getElementById("newCustomerEmployee").innerHTML = '<option value="employee-1">口座A</option>';
    document.getElementById("newCustomerEmployee").value = "employee-1";
    document.getElementById("newCustomerNotes").value = "VIP";
    await document.getElementById("createCustomerBtn").onclick();

    return {
      totalExcludesExtrasOnly: document.getElementById("salesDayDetail").textContent.includes("¥90,000"),
      cashNetKeepsConsumablesRule: document.getElementById("salesDayDetail").textContent.includes("¥85,000"),
      settlementPositiveGreen: Boolean(document.querySelector(".cash-history-amount.positive")),
      resetAlwaysBlack: Boolean(document.querySelector(".cash-history-amount.reset")) && !document.querySelector(".cash-history-amount.reset").classList.contains("negative"),
      noPreviousBalance: !document.getElementById("cashRegisterSection").textContent.includes("精算前残高") && !document.getElementById("cashRegisterSection").textContent.includes("リセット前残高"),
      partyButtons: document.getElementById("partySize").value === "3" && document.querySelector('[data-party-size="3"]').classList.contains("active"),
      duplicateWarnedBeforeInsert: insertCalls === 0,
      wordingClean: !document.getElementById("salesDayDetail").textContent.includes("営業締め") && document.getElementById("salesDayDetail").textContent.includes("精算済み"),
    };
  });

  assert.deepEqual(result, {
    totalExcludesExtrasOnly: true,
    cashNetKeepsConsumablesRule: true,
    settlementPositiveGreen: true,
    resetAlwaysBlack: true,
    noPreviousBalance: true,
    partyButtons: true,
    duplicateWarnedBeforeInsert: true,
    wordingClean: true,
  });
  console.log("September usability and settlement checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});
