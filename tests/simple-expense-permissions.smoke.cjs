const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
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

  const result = await page.evaluate(() => {
    storeId = "store-1";
    currentAuthUser = { id: "user-1" };
    cashRegister = { base_amount: 30000, current_amount: 28000 };
    cashRegisterHistory = [];
    sales = [];
    businessDayClosures = [];
    expenses = [{ id: "expense-1", store_id: storeId, expense_date: "2026-09-08", amount: 2000, category: "備品・消耗品", payment_method: "現金" }];
    storeOperatingSettings = { expense_management_mode: "simple", manager_simple_expense_permission: "create", staff_simple_expense_permission: "none" };

    currentStoreMember = { user_id: "owner-1", role: "owner" };
    renderSettings();
    const ownerSettings = {
      managerPermission: document.getElementById("managerSimpleExpensePermission")?.value,
      staffPermission: document.getElementById("staffSimpleExpensePermission")?.value,
    };

    currentStoreMember = { user_id: "user-1", role: "manager" };
    applyRoleNavigation();
    renderSalesDashboard();
    const managerCreate = {
      form: Boolean(document.getElementById("recordExpenseBtn")),
      editHidden: !document.querySelector("[data-edit-simple-expense]"),
    };

    storeOperatingSettings.manager_simple_expense_permission = "manage";
    renderSalesDashboard();
    const managerManage = Boolean(document.querySelector("[data-edit-simple-expense]") && document.querySelector("[data-delete-simple-expense]"));

    currentStoreMember = { user_id: "user-1", role: "staff" };
    storeOperatingSettings.staff_simple_expense_permission = "none";
    applyRoleNavigation();
    const staffNoneHidden = document.querySelector('.drawer-link[data-page="sales"]').classList.contains("hidden");

    storeOperatingSettings.staff_simple_expense_permission = "create";
    applyRoleNavigation();
    renderSalesDashboard();
    const staffCreate = {
      navVisible: !document.querySelector('.drawer-link[data-page="sales"]').classList.contains("hidden"),
      form: Boolean(document.getElementById("recordExpenseBtn")),
      registerControlsHidden: !document.querySelector(".cash-register-card"),
      settlementListHidden: document.getElementById("salesDateList").classList.contains("hidden"),
    };
    return { ownerSettings, managerCreate, managerManage, staffNoneHidden, staffCreate };
  });

  assert.deepEqual(result, {
    ownerSettings: { managerPermission: "create", staffPermission: "none" },
    managerCreate: { form: true, editHidden: true },
    managerManage: true,
    staffNoneHidden: true,
    staffCreate: { navVisible: true, form: true, registerControlsHidden: true, settlementListHidden: true },
  });
  console.log("Simple expense role permission checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});
