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

  const result = await page.evaluate(async () => {
    currentStoreMember = { user_id: "owner-1", role: "owner" };
    customers = [];
    employees = [{ id: "employee-1", name: "担当" }];
    document.getElementById("protectedApp").classList.remove("hidden");
    document.getElementById("page-home").classList.remove("active");
    document.getElementById("page-input").classList.add("active");
    document.getElementById("employeeSelect").value = "employee-1";
    const add = document.getElementById("addCompanionBtn");
    add.click(); add.click(); add.click();
    await new Promise(resolve => requestAnimationFrame(resolve));
    const rows = [...document.querySelectorAll("#companionRows .companion-row")];
    const compactBeforeDetails = rows.every(row => row.querySelector(".companion-new-fields").classList.contains("hidden"));
    const focusedLatest = document.activeElement === rows[2].querySelector(".companion-search");
    const addNotCovered = add.getBoundingClientRect().bottom < document.querySelector(".sticky-save").getBoundingClientRect().top;
    const noIosZoom = [...rows[0].querySelectorAll(".companion-search,.companion-employee,.companion-notes")]
      .every(field => getComputedStyle(field).fontSize === "16px");
    rows[0].querySelector(".companion-detail-btn").click();
    rows[1].querySelector(".remove-btn").click();
    const remaining = [...document.querySelectorAll("#companionRows .companion-row")];
    return {
      addAfterRows: Boolean(document.getElementById("companionRows").compareDocumentPosition(add) & Node.DOCUMENT_POSITION_FOLLOWING),
      threeRowsAdded: rows.length === 3,
      compactBeforeDetails,
      detailsExpandable: !remaining[0].querySelector(".companion-new-fields").classList.contains("hidden"),
      renumbered: remaining.map(row => row.querySelector(".companion-index").textContent).join(",") === "1,2",
      addLabel: add.textContent.includes("次の同伴者"),
      focusedLatest,
      addNotCovered,
      noIosZoom,
    };
  });

  assert.deepEqual(result, {
    addAfterRows: true,
    threeRowsAdded: true,
    compactBeforeDetails: true,
    detailsExpandable: true,
    renumbered: true,
    addLabel: true,
    focusedLatest: true,
    addNotCovered: true,
    noIosZoom: true,
  });
  await browser.close();
  console.log("compact companion input checks passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
