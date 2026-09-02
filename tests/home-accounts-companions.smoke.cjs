const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260902120000_employee_archiving.sql"), "utf8");
  assert.match(migration, /add column if not exists is_active boolean not null default true/);
  assert.match(migration, /where is_active/);
  assert.match(migration, /update public\.customers[\s\S]*set employee_id = null/);
  assert.match(migration, /update public\.store_users[\s\S]*set employee_id = null/);
  assert.match(migration, /update public\.employees[\s\S]*set is_active = false/);

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
    currentStoreMember = { user_id: "owner-1", role: "owner", employee_id: null };
    storeMembers = [currentStoreMember];
    storeId = "store-1";
    employees = [
      { id: "active-1", name: "現役口座", is_active: true, color: "#4D6B5A" },
      { id: "archived-1", name: "削除済み口座", is_active: false, color: "#65758B" },
    ];
    customers = [{ id: "main-1", name: "主顧客", is_active: true, employee_id: "active-1" }];
    sales = [{ id: "old-sale", business_date: "2026-08-31", customer_id: "main-1", employee_id: "archived-1", payment_status: "回収済み", payment_method: "現金", party_size: 1, total_amount: 10000, is_settled: true }];
    schedules = [];
    monthlyGoals = [{ goal_month: "2026-09-01", weekday_goal: 23000, weekend_goal: 29000, target_amount: 116000, open_weekdays: [5] }];
    businessOverrides = [];
    eventGoals = [];

    renderEmployees();
    renderEmployeeList();
    renderHome();

    const mondayTarget = configuredDailyTarget("2026-09-07");
    const fridayTarget = configuredDailyTarget("2026-09-11");
    businessOverrides = [{ business_date: "2026-09-07", is_open: false }];
    const closedTarget = configuredDailyTarget("2026-09-07");
    businessOverrides = [];
    eventGoals = [{ start_date: "2026-09-07", end_date: "2026-09-09", daily_target_amount: 700000 }];
    const eventTarget = configuredDailyTarget("2026-09-08");

    document.getElementById("customerId").value = "main-1";
    document.getElementById("employeeSelect").value = "active-1";
    addCompanionRow();
    document.querySelector(".companion-search").value = "新しい同伴者";
    let customerInsertCount = 0;
    db.from = table => ({
      insert: values => ({
        select: () => ({
          single: async () => {
            if (table === "customers") customerInsertCount += 1;
            return { data: { id: "companion-new", ...values }, error: null };
          },
        }),
      }),
    });
    const createdIds = await resolveCompanionIds();
    document.querySelector(".companion-search").value = " 新しい同伴者 ";
    document.querySelector(".companion-id").value = "";
    const reusedIds = await resolveCompanionIds();

    return {
      weekdayRate: mondayTarget.amount === 23000,
      weekendRate: fridayTarget.amount === 29000,
      explicitClosureWins: closedTarget.label === "休業" && closedTarget.amount === 0,
      eventRateWins: eventTarget.amount === 700000,
      archivedHiddenFromSelect: !document.getElementById("employeeSelect").textContent.includes("削除済み口座"),
      activeDeleteAvailable: Boolean(document.querySelector('[data-archive-employee="active-1"]')),
      archivedHistoryPreserved: saleCard(sales[0]).includes("削除済み口座"),
      homeSimplified: !document.getElementById("homeAttention") && !document.getElementById("homeSalesChart") && !document.querySelector('[data-go-page="sales-list"]'),
      companionCreatedOnce: customerInsertCount === 1 && createdIds[0] === "companion-new" && reusedIds[0] === "companion-new",
    };
  });

  assert.deepEqual(result, {
    weekdayRate: true,
    weekendRate: true,
    explicitClosureWins: true,
    eventRateWins: true,
    archivedHiddenFromSelect: true,
    activeDeleteAvailable: true,
    archivedHistoryPreserved: true,
    homeSimplified: true,
    companionCreatedOnce: true,
  });

  await browser.close();
  console.log("home, accounts, and companions smoke test passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
