const assert = require("node:assert/strict");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  try {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({ contentType: "application/javascript", body: "window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};" }));
    await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({ contentType: "application/javascript", body: "window.Chart=class{constructor(){}destroy(){}update(){}};" }));
    await page.goto("file:///" + path.resolve(__dirname, "../index.html").replaceAll("\\", "/"));
    const result = await page.evaluate(() => {
      currentAuthUser = { id: "owner" };
      currentStoreMember = { user_id: "owner", role: "owner", employee_id: null };
      customers = []; employees = []; schedules = [];
      openScheduleModal("2026-01-31");
      document.querySelector('[data-color="wine"]').click();
      document.getElementById("scheduleRecurrence").value = "monthly";
      document.getElementById("scheduleRecurrence").dispatchEvent(new Event("change"));
      return {
        colorCount: document.querySelectorAll("#scheduleColors [data-color]").length,
        selectedColor: selectedScheduleColor(),
        recurrenceEndVisible: !document.getElementById("scheduleRecurrenceEndField").classList.contains("hidden"),
        monthlyDates: buildScheduleDates("2026-01-31", "monthly", "2026-04-30"),
        yearlyDates: buildScheduleDates("2028-02-29", "yearly", "2030-03-01"),
      };
    });
    assert.equal(result.colorCount, 5);
    assert.equal(result.selectedColor, "wine");
    assert.ok(result.recurrenceEndVisible);
    assert.deepEqual(result.monthlyDates, ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"]);
    assert.deepEqual(result.yearlyDates, ["2028-02-29", "2029-02-28", "2030-02-28"]);
    console.log("Schedule colors and recurrence test passed.");
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
