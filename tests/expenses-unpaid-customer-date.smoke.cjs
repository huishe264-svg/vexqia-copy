const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260904100000_expenses_and_unpaid_payment_method.sql"), "utf8");
  assert.match(migration, /create table if not exists public\.expenses/);
  assert.match(migration, /after_register := before_register - target_amount/);
  assert.match(migration, /payment_status = '未収' and payment_method is null/);
  assert.match(migration, /'expense', -target_amount/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{constructor(){}destroy(){} update(){}};`,
  }));
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(async () => {
    currentAuthUser = { id: "owner-1" };
    currentStoreMember = { user_id: "owner-1", role: "owner" };
    storeMembers = [currentStoreMember];
    storeId = "store-1";
    customers = [
      { id: "main", name: "主顧客", is_active: true },
      { id: "companion", name: "同伴顧客", is_active: true },
      { id: "other", name: "別日顧客", is_active: true },
    ];
    employees = [];
    bottles = [];
    sales = [
      { id: "sale-day", business_date: "2026-09-03", customer_id: "main", payment_status: "回収済み", payment_method: "現金", total_amount: 10000, party_size: 2 },
      { id: "sale-other", business_date: "2026-09-02", customer_id: "other", payment_status: "回収済み", payment_method: "現金", total_amount: 5000, party_size: 1 },
    ];
    saleCompanions = [{ sale_id: "sale-day", customer_id: "companion" }];
    expenses = [{ expense_date: "2026-09-03", amount: 1200, description: "備品" }];
    cashRegister = { base_amount: 30000, current_amount: 28800 };
    cashRegisterHistory = [{ action: "expense", amount_delta: -1200, balance_after: 28800, business_date: "2026-09-03", created_by: "owner-1", created_at: "2026-09-03T12:00:00Z" }];

    document.getElementById("customerVisitDate").value = "2026-09-03";
    renderCustomerList();
    const visitText = document.getElementById("customerList").textContent;

    document.querySelector('[data-group="paymentStatus"][data-value="未収"]').click();
    document.getElementById("customerId").value = "main";
    document.getElementById("employeeSelect").innerHTML = '<option value="employee">口座</option>';
    document.getElementById("employeeSelect").value = "employee";
    document.getElementById("partySize").value = "1";
    document.getElementById("totalAmount").value = "10000";
    const unpaidValid = validateSale();

    renderCashRegister();
    const expenseUi = document.getElementById("cashRegisterSection").textContent;

    document.getElementById("newCustomerName").value = "前の顧客";
    document.getElementById("newCustomerKana").value = "まえ";
    document.getElementById("newCustomerNotes").value = "前回の備考";
    closeModal("newCustomerModal");

    return {
      visitHasMain: visitText.includes("主顧客"),
      visitHasCompanion: visitText.includes("同伴顧客"),
      visitExcludesOtherDay: !visitText.includes("別日顧客"),
      unpaidNeedsNoMethod: unpaidValid && selectedPaymentMethod === null,
      paymentMethodHidden: document.getElementById("paymentMethodField").classList.contains("hidden"),
      expenseInputOutsideSettlement: !expenseUi.includes("経費を入力") && Boolean(document.querySelector('[data-page="finance"]')),
      expenseHistoryLabel: expenseUi.includes("経費"),
      customerFormReset: !document.getElementById("newCustomerName").value && !document.getElementById("newCustomerKana").value && !document.getElementById("newCustomerNotes").value,
    };
  });

  assert.deepEqual(result, {
    visitHasMain: true,
    visitHasCompanion: true,
    visitExcludesOtherDay: true,
    unpaidNeedsNoMethod: true,
    paymentMethodHidden: true,
    expenseInputOutsideSettlement: true,
    expenseHistoryLabel: true,
    customerFormReset: true,
  });
  console.log("Expenses, unpaid payment, and customer visit-date checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});
