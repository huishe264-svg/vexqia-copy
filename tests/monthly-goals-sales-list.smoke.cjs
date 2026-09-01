const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260901170000_monthly_and_event_sales_goals.sql"), "utf8");
  assert.match(migration, /create table if not exists public\.monthly_sales_goals/);
  assert.match(migration, /unique \(store_id, goal_month\)/);
  assert.match(migration, /create table if not exists public\.event_sales_goals/);
  assert.match(migration, /end_date date not null check \(end_date >= start_date\)/);
  assert.match(migration, /public\.is_store_owner_or_manager/);
  assert.match(migration, /Preserve the current month's goal/);

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

  const result = await page.evaluate(() => {
    currentAuthUser = { id: "owner-1" };
    currentStoreMember = { user_id: "owner-1", role: "owner" };
    customers = [
      { id: "customer-1", name: "田中様", name_kana: "たなか" },
      { id: "customer-2", name: "佐藤様", name_kana: "さとう" },
    ];
    employees = [{ id: "employee-1", name: "口座A" }];
    settlements = [];
    monthlyGoals = [
      { goal_month: "2026-09-01", target_amount: 200000 },
      { goal_month: "2026-08-01", target_amount: 100000 },
    ];
    eventGoals = [{ id: "event-1", name: "周年イベント", start_date: "2026-09-01", end_date: "2026-09-02", target_amount: 50000, note: "2日間" }];
    sales = [
      { id: "sep-1", business_date: "2026-09-01", customer_id: "customer-1", employee_id: "employee-1", payment_status: "回収済み", payment_method: "現金", total_amount: 30000, delivery_tobacco_amount: 0, party_size: 1, is_settled: true },
      { id: "sep-2", business_date: "2026-09-01", customer_id: "customer-2", employee_id: "employee-1", payment_status: "未収", payment_method: "カード", total_amount: 10000, delivery_tobacco_amount: 0, party_size: 1, is_settled: false },
      { id: "sep-3", business_date: "2026-09-02", customer_id: "customer-2", employee_id: "employee-1", payment_status: "回収済み", payment_method: "カード", total_amount: 40000, delivery_tobacco_amount: 0, party_size: 1, is_settled: true },
      { id: "aug-1", business_date: "2026-08-31", customer_id: "customer-1", employee_id: "employee-1", payment_status: "回収済み", payment_method: "現金", total_amount: 120000, delivery_tobacco_amount: 0, party_size: 1, is_settled: true },
    ];

    renderMonthlyGoalHistory();
    renderEventGoalList();
    salesListMonth = "2026-09";
    renderSalesList();
    const monthTotal = document.getElementById("salesMonthNavigator").textContent.includes("¥70,000");
    const twoDays = document.querySelectorAll("[data-sales-day]").length === 2;
    document.querySelector('[data-sales-day="2026-09-01"]').click();
    const dayDetails = document.querySelector('[data-sales-day="2026-09-01"]').nextElementSibling.querySelectorAll("[data-sale-id]").length === 2;
    const augustHistory = [...document.querySelectorAll("[data-sales-month]")].some(button => button.dataset.salesMonth === "2026-08" && button.textContent.includes("¥120,000"));

    document.getElementById("salesListSearch").value = "田中";
    renderSalesList();
    const searchAllMonths = document.getElementById("salesMonthNavigator").textContent.includes("2件") && document.querySelectorAll("[data-sales-day]").length === 2;

    document.getElementById("analyticsStartDate").value = "2026-08-01";
    document.getElementById("analyticsEndDate").value = "2026-08-31";
    renderAnalytics();
    const analyticsHistoricalGoal = document.getElementById("analyticsMetrics").children[3].textContent.includes("120.0%") && document.getElementById("analyticsMetrics").children[3].textContent.includes("+¥20,000");

    return {
      monthTotal,
      twoDays,
      dayDetails,
      augustHistory,
      searchAllMonths,
      historicalGoalResult: document.getElementById("monthlyGoalHistory").textContent.includes("+¥20,000") && document.getElementById("monthlyGoalHistory").textContent.includes("120.0%"),
      eventResult: document.getElementById("eventGoalList").textContent.includes("周年イベント") && document.getElementById("eventGoalList").textContent.includes("+¥20,000") && document.getElementById("eventGoalList").textContent.includes("140.0%"),
      analyticsHistoricalGoal,
    };
  });

  assert.deepEqual(result, {
    monthTotal: true,
    twoDays: true,
    dayDetails: true,
    augustHistory: true,
    searchAllMonths: true,
    historicalGoalResult: true,
    eventResult: true,
    analyticsHistoricalGoal: true,
  });
  console.log("Monthly goals and hierarchical sales list checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});

