const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
const path = require("node:path");

(async () => {
  const browser = await chromium.launch({
    headless: true,
    executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe",
  });
  const page = await browser.newPage();

  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", (route) =>
    route.fulfill({
      contentType: "application/javascript",
      body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:(callback)=>{window.__authCallback=callback;return {data:{subscription:{unsubscribe(){}}}}},signOut:async()=>({error:null})}}}};`,
    }),
  );
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", (route) =>
    route.fulfill({
      contentType: "application/javascript",
      body: `window.Chart=class{constructor(canvas,config){this.canvas=canvas;this.config=config}destroy(){} update(){}};`,
    }),
  );

  await page.goto(`file:///${path.resolve(__dirname, "../index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(async () => {
    currentAuthUser = { id: "user-staff" };
    currentStoreMember = { user_id: "user-staff", role: "staff", employee_id: "employee-1" };
    employees = [{ id: "employee-1", name: "テスト従業員" }, { id: "employee-2", name: "別の従業員" }];
    storeMembers = [currentStoreMember];
    sales = [
      { id: "own", created_by: "user-staff", is_settled: false },
      { id: "other", created_by: "user-other", is_settled: false },
      { id: "settled", created_by: "user-staff", is_settled: true },
    ];

    renderEmployees();
    applyRoleNavigation();

    const managerPagesHidden = [...document.querySelectorAll("[data-manager-only]")]
      .every((element) => element.classList.contains("hidden"));
    const analyticsVisible = !document.querySelector('[data-page="analytics"]').classList.contains("hidden");

    const staffResult = {
      businessDateIsYesterday: (() => { const d = new Date(); d.setDate(d.getDate() - 1); return document.getElementById("businessDate").value === dateString(d); })(),
      selectedEmployee: document.getElementById("employeeSelect").value,
      employeeLocked: document.getElementById("employeeSelect").disabled,
      quickEmployeeHidden: document.getElementById("quickEmployeeBtn").classList.contains("hidden"),
      managerPagesHidden,
      analyticsVisible,
      canEditOwn: canEditSale(sales[0]),
      canEditOther: canEditSale(sales[1]),
      canEditSettled: canEditSale(sales[2]),
      autoBrandCopy: document.getElementById("directBottleInputArea").textContent.includes("自動登録"),
    };

    currentStoreMember = { user_id: "user-manager", role: "manager", employee_id: null };
    currentAuthUser = { id: "user-manager" };
    renderEmployees();
    applyRoleNavigation();
    const managerResult = {
      managerPagesVisible: [...document.querySelectorAll("[data-manager-only]")]
        .every((element) => !element.classList.contains("hidden")),
      ownerPagesHidden: [...document.querySelectorAll("[data-owner-only]")]
        .every((element) => element.classList.contains("hidden")),
      employeeUnlocked: !document.getElementById("employeeSelect").disabled,
      canEditOther: canEditSale(sales[1]),
    };

    currentStoreMember = { user_id: "user-owner", role: "owner", employee_id: null };
    currentAuthUser = { id: "user-owner" };
    applyRoleNavigation();
    const ownerResult = {
      managerPagesVisible: [...document.querySelectorAll("[data-manager-only]")]
        .every((element) => !element.classList.contains("hidden")),
      ownerPagesVisible: [...document.querySelectorAll("[data-owner-only]")]
        .every((element) => !element.classList.contains("hidden")),
      canEditOther: canEditSale(sales[1]),
    };

    uiPreviewRole = null;
    renderSettings();
    const ownerSwitcherHidden = document.getElementById("rolePreviewSettings").classList.contains("hidden");
    setRolePreview("staff");
    const ownerPreviewBlocked = uiPreviewRole === null && displayRole() === "owner";

    platformAdminMode = true;
    currentAuthUser = { id: "platform-admin" };
    uiPreviewRole = null;
    const staleFinanceHome = document.createElement("div");
    staleFinanceHome.id = "ownerFinanceHome";
    document.getElementById("homeGoalSection").insertAdjacentElement("afterend", staleFinanceHome);
    setRolePreview("staff");
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const staffPreviewState = {
      actualRoleUnchanged: actualRole() === "admin",
      displayRoleChanged: displayRole() === "staff",
      bannerVisible: !document.getElementById("rolePreviewBanner").classList.contains("hidden") && document.getElementById("rolePreviewBannerTitle").textContent.includes("従業員"),
      switcherStillVisible: !document.getElementById("rolePreviewSettings").classList.contains("hidden"),
      ownerFeaturesHidden: [...document.querySelectorAll("[data-owner-only]")].every((element) => element.classList.contains("hidden")),
      managerFeaturesHidden: [...document.querySelectorAll("[data-manager-only]")].every((element) => element.classList.contains("hidden")),
      employeePreviewLocked: document.getElementById("employeeSelect").disabled && document.getElementById("employeeSelect").value === "employee-1",
      ownerFinanceHidden: !document.getElementById("ownerFinanceHome"),
    };
    setRolePreview("manager");
    const managerPreviewState = {
      actualRoleUnchanged: actualRole() === "admin",
      displayRoleChanged: displayRole() === "manager",
      managerFeaturesVisible: [...document.querySelectorAll("[data-manager-only]")].every((element) => !element.classList.contains("hidden")),
      ownerFeaturesHidden: [...document.querySelectorAll("[data-owner-only]")].every((element) => element.classList.contains("hidden")),
    };
    document.getElementById("exitRolePreviewBtn").click();
    const restoredOwnerState = {
      previewCleared: uiPreviewRole === null && displayRole() === "admin",
      bannerHidden: document.getElementById("rolePreviewBanner").classList.contains("hidden"),
      ownerFeaturesVisible: [...document.querySelectorAll("[data-owner-only]")].every((element) => !element.classList.contains("hidden")),
    };
    platformAdminMode = false;
    currentStoreMember = { user_id: "user-manager", role: "manager", employee_id: null };
    uiPreviewRole = null;
    setRolePreview("staff");
    const nonOwnerBlocked = uiPreviewRole === null && displayRole() === "manager";
    const previewResult = { ownerSwitcherHidden, ownerPreviewBlocked, staffPreviewState, managerPreviewState, restoredOwnerState, nonOwnerBlocked };

    customers = [{ id: "customer-1", name: "分析顧客", is_active: true, employee_id: "employee-1" }];
    employees = [{ id: "employee-1", name: "テスト従業員", color: "#4D6B5A" }, { id: "employee-2", name: "別の従業員", color: "#625A7B" }];
    goalSettings = { weekday_goal: 10000, weekend_goal: 15000, closed_weekdays: [] };
    businessOverrides = [];
    sales = [
      { business_date: "2026-08-10", payment_status: "回収済み", payment_method: "現金", total_amount: 30000, delivery_tobacco_amount: 0, party_size: 2, employee_id: "employee-1", customer_id: "customer-1", is_settled: true },
      { business_date: "2026-08-11", payment_status: "未収", payment_method: "カード", total_amount: 12000, party_size: 1, employee_id: "employee-1", customer_id: "customer-1" },
    ];
    document.getElementById("analyticsStartDate").value = "2026-08-01";
    document.getElementById("analyticsEndDate").value = "2026-08-31";
    renderAnalytics();
    resizeChartWrap("customer", "customerSalesChart", { data: { labels: ["1", "2", "3", "4", "5", "6"] } });
    const analyticsResult = {
      hasSalesMetric: document.getElementById("analyticsMetrics").textContent.includes("¥30,000"),
      hasUnpaidMetric: document.getElementById("analyticsMetrics").textContent.includes("¥12,000"),
      hasGoalMetric: document.getElementById("analyticsMetrics").textContent.includes("目標達成率"),
      chartsCreated: ["daily", "analyticsPayment", "employee", "customer"].every((key) => Boolean(charts[key])),
      onlyHomeDoughnutRemoved: !document.getElementById("homePaymentChart") && Boolean(document.getElementById("analyticsPaymentChart")),
      refinedChartPalette: charts.daily?.config?.data?.datasets?.[0]?.backgroundColor === "#31445e" && charts.analyticsPayment?.config?.data?.datasets?.[0]?.backgroundColor?.join(",") === "#132238,#697586,#c8cdd4",
      fixedBarThickness: charts.daily?.config?.data?.datasets?.[0]?.barThickness === 9 && charts.employee?.config?.data?.datasets?.[0]?.barThickness === 14 && charts.customer?.config?.data?.datasets?.[0]?.barThickness === 14,
      adaptiveChartHeight: document.getElementById("customerSalesChart").closest(".chart-wrap").style.height === "292px",
      paymentLegendAmounts: document.getElementById("analyticsPaymentLegend").textContent.includes("現金¥30,000") && document.getElementById("analyticsPaymentLegend").textContent.includes("カード¥0") && document.getElementById("analyticsPaymentLegend").textContent.includes("未収¥12,000"),
      builtInLegendHidden: charts.analyticsPayment?.config?.options?.plugins?.legend?.display === false,
    };

    currentStoreMember = { user_id: "user-staff", role: "staff", employee_id: "employee-1" };
    currentAuthUser = { id: "user-staff" };
    schedules = [{ schedule_date: dateString(), status: "予定", employee_id: "employee-1", created_by: "user-staff" }];
    sales = [
      { id: "cash", business_date: "2026-08-10", payment_status: "回収済み", payment_method: "現金", total_amount: 30000, party_size: 2, employee_id: "employee-1", customer_id: "customer-1", created_by: "user-staff", is_settled: false },
      { id: "card", business_date: "2026-08-10", payment_status: "回収済み", payment_method: "カード", total_amount: 8000, party_size: 1, employee_id: "employee-1", customer_id: "customer-1", created_by: "user-staff", is_settled: false },
      { id: "unpaid", business_date: "2026-08-10", payment_status: "未収", payment_method: "カード", total_amount: 12000, party_size: 1, employee_id: "employee-1", customer_id: "customer-1", created_by: "user-staff", is_settled: false },
    ];
    settlements = [];
    bottles = [];
    renderRecentCustomers();
    selectMainCustomer("customer-1");
    document.getElementById("totalAmount").value = "38000";
    document.querySelector('[data-group="paymentStatus"][data-value="回収済み"]').click();
    document.querySelector('[data-group="paymentMethod"][data-value="カード"]').click();
    document.getElementById("totalAmount").dispatchEvent(new Event("input"));
    renderSalesDay("2026-08-10");
    renderRoleHome();
    setAnalyticsPreset("month");
    showSaleSuccess(customers[0], 38000, "カード", true);
    const uiThirdRoundResult = {
      recentCustomerRemoved: !document.getElementById("recentCustomerBlock"),
      stickySummaryComplete: document.getElementById("saleSubmitSummary").textContent.includes("分析顧客") && document.getElementById("saleSubmitSummary").textContent.includes("¥38,000") && document.getElementById("saleSubmitSummary").textContent.includes("カード"),
      selectedStateAccessible: document.querySelector('[data-group="paymentMethod"][data-value="カード"]').getAttribute("aria-pressed") === "true",
      dailyCashVisible: document.getElementById("salesDayDetail").textContent.includes("現金売上") && document.getElementById("salesDayDetail").textContent.includes("¥30,000"),
      dailyCardVisible: document.getElementById("salesDayDetail").textContent.includes("カード売上") && document.getElementById("salesDayDetail").textContent.includes("¥8,000"),
      dailyGrossVisible: document.getElementById("salesDayDetail").textContent.includes("総売上") && document.getElementById("salesDayDetail").textContent.includes("¥38,000"),
      staffHomeVisible: document.getElementById("roleHomeSummary").textContent.includes("本日の予定") && document.getElementById("roleHomeSummary").textContent.includes("本日の目標金額"),
      monthPresetActive: document.querySelector('[data-analytics-preset="month"]').classList.contains("active") && document.getElementById("analyticsStartDate").value.endsWith("-01"),
      schedulePromoted: document.querySelector('[data-page="schedule"]').previousElementSibling?.dataset.page === "customers",
      successActionsVisible: document.querySelectorAll("#saleSuccessSummary [data-success-action]").length === 3 && document.getElementById("saleSuccessSummary").textContent.includes("銘柄も自動登録"),
    };

    sales = [
      { id: "settled-card", business_date: "2026-08-12", payment_status: "回収済み", payment_method: "カード", total_amount: 10000, delivery_tobacco_amount: 3000, party_size: 1, employee_id: "employee-1", customer_id: "customer-1", created_by: "user-manager", is_settled: true },
    ];
    settlements = [{ business_date: "2026-08-12", consumables_amount: 2000 }];
    cashRegister = { base_amount: 50000, current_amount: 45000 };
    cashRegisterHistory = [{ action: "settlement", amount_delta: -5000, balance_before: 50000, balance_after: 45000, base_amount: 50000, business_date: "2026-08-12", created_by: "user-manager", created_at: "2026-08-12T12:00:00Z" }];
    renderSalesDashboard();
    renderSalesDay("2026-08-12");
    const cashRegisterResult = {
      registerShownFirst: document.querySelector("#salesDashboardOverview > :first-child")?.id === "cashRegisterSection",
      settlementGoalRemoved: !document.getElementById("goalSection") && !document.getElementById("monthGrossSales"),
      cashNetLabel: document.getElementById("salesDayDetail").textContent.includes("精算後現金売上"),
      oldNetLabelRemoved: !document.getElementById("salesDayDetail").textContent.includes("精算後売上"),
      negativeCashNet: document.getElementById("salesDayDetail").textContent.includes("-¥5,000") && Boolean(document.querySelector("#salesDayDetail .cash-net-negative")),
      registerBalance: document.getElementById("cashRegisterSection").textContent.includes("¥45,000") && document.getElementById("cashRegisterSection").textContent.includes("常レジ金 ¥50,000"),
      registerHistory: document.getElementById("cashRegisterSection").textContent.includes("日別精算") && document.getElementById("cashRegisterSection").textContent.includes("-¥5,000"),
    };

    currentStoreMember = { user_id: "user-owner", role: "owner", employee_id: null };
    currentAuthUser = { id: "user-owner" };
    customers = [{ id: "customer-1", name: "分析顧客", is_active: true, employee_id: "employee-1" }];
    bottles = [
      { id: "bottle-active-1", customer_id: "customer-1", name: "吉四六", bottle_number: "12", status: "保有中" },
      { id: "bottle-active-2", customer_id: "customer-1", name: "黒霧島", bottle_number: null, status: "保有中" },
      { id: "bottle-empty", customer_id: "customer-1", name: "飲み切り済み", status: "飲み切り" },
    ];
    document.getElementById("customerId").value = "customer-1";
    renderEmployees();
    renderCustomerList();
    renderEmployeeList();
    selectMainCustomer("customer-1");
    renderBottleSelect();
    document.querySelector('[data-bottle-id="bottle-active-1"][data-bottle-state="空いた"]').click();
    renderBottleBrandSelect();
    renderHome();
    renderGoalSection("homeGoalSection");
    currentPage = "home";
    const swipeAdvanced = navigateMainSwipe(-100, 5, 200) && currentPage === "schedule";
    const swipeIgnoredVertical = !navigateMainSwipe(-20, 120, 200) && currentPage === "schedule";
    const bottomNavLabels = [...document.querySelectorAll(".bottom-nav .nav-btn span")].map((node) => node.textContent).join(",");
    const companionCard = document.getElementById("companionRows").closest(".card");
    const extraBeforeTotal = Boolean(document.getElementById("extraAmount").compareDocumentPosition(document.getElementById("totalAmount")) & Node.DOCUMENT_POSITION_FOLLOWING);
    const fourthRoundResult = {
      bottomNavOrder: bottomNavLabels === "ホーム,カレンダー,顧客,売上入力,その他",
      compactHome: !document.getElementById("homeTodaySummary") && !document.getElementById("homeAttention") && !document.getElementById("homeSalesChart") && document.getElementById("roleHomeSummary").textContent.includes("本日の予定") && document.getElementById("roleHomeSummary").textContent.includes("本日の目標金額") && !document.getElementById("roleHomeSummary").textContent.includes("店舗の運営状況"),
      navyGoalFirst: document.querySelector("#page-home > :first-child")?.id === "homeGoalSection" && Boolean(document.querySelector("#homeGoalSection .home-goal-card")),
      requiredMarksCompact: [...document.querySelectorAll("#page-input .required")].every((node) => node.textContent.trim() === "※" && node.getAttribute("aria-label") === "必須"),
      companionsInBasicInfo: companionCard?.textContent.includes("基本情報") && companionCard?.contains(document.getElementById("customerId")),
      existingBottlesVisible: document.querySelectorAll("#existingBottleList .existing-bottle-card").length === 2 && !document.getElementById("existingBottleList").textContent.includes("飲み切り済み"),
      bottleStateSelectable: existingBottleStates["bottle-active-1"] === "空いた" && document.querySelector('[data-bottle-id="bottle-active-1"][data-bottle-state="空いた"]').classList.contains("active"),
      newBottleNone: document.getElementById("newBottleBrandSelect").options[0].textContent === "なし",
      extraBeforeTotal,
      noDetailAccordion: document.getElementById("saleDetails").tagName === "DIV" && !document.querySelector("#page-input details"),
      noAmountShortcuts: !document.querySelector("#page-input [data-add-amount]") && !document.querySelector("#page-input .amount-shortcuts"),
      swipeAdvanced,
      swipeIgnoredVertical,
      linkedAccountVisible: document.getElementById("customerList").textContent.includes("テスト従業員") && document.getElementById("customerList").querySelector(".account-badge")?.getAttribute("style")?.includes("#4D6B5A"),
      linkedAccountAutoSelected: document.getElementById("employeeSelect").value === "employee-1",
      accountColorEditable: document.querySelector('[data-employee-color="employee-1"]')?.value.toUpperCase() === "#4D6B5A",
      homeTodaySalesSmall: document.getElementById("homeGoalSection").textContent.includes("本日の売上") && Boolean(document.querySelector("#homeGoalSection .home-goal-today")),
      homeGoalTitleRemoved: !document.getElementById("homeGoalSection").textContent.includes("今月の売上目標"),
    };

    currentAuthUser = { id: "user-owner", email: "owner@example.com" };
    currentStoreMember = { user_id: "user-owner", role: "owner", employee_id: null };
    storeMembers = [currentStoreMember];
    db.functions = { invoke: async () => ({ data: null, error: { message: "Edge Function failed" } }) };
    await loadPermissionMembers();
    const permissionFallbackResult = {
      memberStillVisible: document.getElementById("permissionMemberList").textContent.includes("owner@example.com"),
      ownerRoleVisible: document.getElementById("permissionMemberList").textContent.includes("オーナー"),
      retryVisible: Boolean(document.getElementById("retryPermissionMembersBtn")),
      genericFailureRemoved: !document.getElementById("permissionMemberList").textContent.includes("メンバーを読み込めませんでした"),
    };

    permissionMembers = [{ user_id: "user-owner", email: "owner@example.com", role: "owner", employee_id: null }];
    pendingInvitations = [{ email: "staff@example.com", role: "staff", employee_id: "employee-1" }];
    renderPermissionMembers();
    db.functions = { invoke: async (_name, options) => options.body.action === "claim"
      ? { data: { claimed: [{ claimed_store_id: "store-1", claimed_role: "staff" }] }, error: null }
      : { data: null, error: null } };
    const claimedCount = await claimPendingStoreInvitations();
    const invitationResult = {
      pendingVisible: document.getElementById("permissionMemberList").textContent.includes("招待待ち") && document.getElementById("permissionMemberList").textContent.includes("staff@example.com"),
      pendingAccountVisible: document.getElementById("permissionMemberList").textContent.includes("テスト従業員"),
      connectedSeparated: document.getElementById("permissionMemberList").textContent.includes("接続済み"),
      claimDetected: claimedCount === 1 && invitationClaimError === "",
    };

    const originalInit = init;
    let deferredInitCalls = 0;
    init = async () => { deferredInitCalls += 1; };
    appInitialized = false;
    const authCallbackReturn = window.__authCallback("SIGNED_IN", { user: { id: "invited-user", email: "staff@example.com" } });
    const initWasDeferred = deferredInitCalls === 0;
    await new Promise((resolve) => setTimeout(resolve, 10));
    const authFlowResult = {
      callbackIsSynchronous: !(authCallbackReturn instanceof Promise),
      initWasDeferred,
      initRanOnce: deferredInitCalls === 1,
      japaneseMembershipError: await permissionErrorMessage(null, { code: "MEMBERSHIP_SAVE_FAILED" }, "fallback") === "店舗への権限登録に失敗しました。もう一度お試しください。",
    };
    init = originalInit;

    return { staffResult, managerResult, ownerResult, previewResult, analyticsResult, uiThirdRoundResult, cashRegisterResult, fourthRoundResult, permissionFallbackResult, invitationResult, authFlowResult };
  });

  const expected = {
    staffResult: {
      businessDateIsYesterday: true,
      selectedEmployee: "employee-1",
      employeeLocked: true,
      quickEmployeeHidden: true,
      managerPagesHidden: true,
      analyticsVisible: true,
      canEditOwn: true,
      canEditOther: false,
      canEditSettled: false,
      autoBrandCopy: true,
    },
    managerResult: {
      managerPagesVisible: true,
      ownerPagesHidden: true,
      employeeUnlocked: true,
      canEditOther: true,
    },
    ownerResult: {
      managerPagesVisible: true,
      ownerPagesVisible: true,
      canEditOther: true,
    },
    previewResult: {
      ownerSwitcherHidden: true,
      ownerPreviewBlocked: true,
      staffPreviewState: {
        actualRoleUnchanged: true,
        displayRoleChanged: true,
        bannerVisible: true,
        switcherStillVisible: true,
        ownerFeaturesHidden: true,
        managerFeaturesHidden: true,
        employeePreviewLocked: true,
        ownerFinanceHidden: true,
      },
      managerPreviewState: {
        actualRoleUnchanged: true,
        displayRoleChanged: true,
        managerFeaturesVisible: true,
        ownerFeaturesHidden: true,
      },
      restoredOwnerState: {
        previewCleared: true,
        bannerHidden: true,
        ownerFeaturesVisible: true,
      },
      nonOwnerBlocked: true,
    },
    analyticsResult: {
      hasSalesMetric: true,
      hasUnpaidMetric: true,
      hasGoalMetric: true,
      chartsCreated: true,
      onlyHomeDoughnutRemoved: true,
      refinedChartPalette: true,
      fixedBarThickness: true,
      adaptiveChartHeight: true,
      paymentLegendAmounts: true,
      builtInLegendHidden: true,
    },
    uiThirdRoundResult: {
      recentCustomerRemoved: true,
      stickySummaryComplete: true,
      selectedStateAccessible: true,
      dailyCashVisible: true,
      dailyCardVisible: true,
      dailyGrossVisible: true,
      staffHomeVisible: true,
      monthPresetActive: true,
      schedulePromoted: true,
      successActionsVisible: true,
    },
    cashRegisterResult: {
      registerShownFirst: true,
      settlementGoalRemoved: true,
      cashNetLabel: true,
      oldNetLabelRemoved: true,
      negativeCashNet: true,
      registerBalance: true,
      registerHistory: true,
    },
    fourthRoundResult: {
      bottomNavOrder: true,
      compactHome: true,
      navyGoalFirst: true,
      requiredMarksCompact: true,
      companionsInBasicInfo: true,
      existingBottlesVisible: true,
      bottleStateSelectable: true,
      newBottleNone: true,
      extraBeforeTotal: true,
      noDetailAccordion: true,
      noAmountShortcuts: true,
      swipeAdvanced: true,
      swipeIgnoredVertical: true,
      linkedAccountVisible: true,
      linkedAccountAutoSelected: true,
      accountColorEditable: true,
      homeTodaySalesSmall: true,
      homeGoalTitleRemoved: true,
    },
    permissionFallbackResult: {
      memberStillVisible: true,
      ownerRoleVisible: true,
      retryVisible: true,
      genericFailureRemoved: true,
    },
    invitationResult: {
      pendingVisible: true,
      pendingAccountVisible: true,
      connectedSeparated: true,
      claimDetected: true,
    },
    authFlowResult: {
      callbackIsSynchronous: true,
      initWasDeferred: true,
      initRanOnce: true,
      japaneseMembershipError: true,
    },
  };

  if (JSON.stringify(result) !== JSON.stringify(expected)) {
    throw new Error(`Role UI smoke test failed: ${JSON.stringify(result)}`);
  }

  console.log("Role UI smoke test passed", result);
  await browser.close();
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
