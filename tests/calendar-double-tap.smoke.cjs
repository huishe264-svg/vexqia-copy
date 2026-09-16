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
      currentCalendarDate = new Date(2026, 8, 1);
      selectedCalendarDate = null;
      customers = []; employees = []; schedules = [];
      renderCalendar();
      const day = document.querySelector('[data-calendar-date="2026-09-16"]');
      day.click();
      const afterFirst = { selected: selectedCalendarDate, modal: document.getElementById("scheduleModal").classList.contains("show") };
      document.querySelector('[data-calendar-date="2026-09-16"]').click();
      const afterSecond = { selected: selectedCalendarDate, modal: document.getElementById("scheduleModal").classList.contains("show"), date: document.getElementById("scheduleDate").value };
      closeModal("scheduleModal");
      selectedCalendarDate = "2026-09-17";
      document.getElementById("newScheduleBtn").click();
      return {
        afterFirst,
        afterSecond,
        plusUsesSelectedDate: document.getElementById("scheduleDate").value === "2026-09-17",
        oneAddButton: !document.getElementById("newScheduleBtn").classList.contains("hidden") && document.getElementById("addSelectedDateScheduleBtn").classList.contains("hidden"),
      };
    });
    assert.deepEqual(result.afterFirst, { selected: "2026-09-16", modal: false });
    assert.deepEqual(result.afterSecond, { selected: "2026-09-16", modal: true, date: "2026-09-16" });
    assert.ok(result.oneAddButton);
    assert.ok(result.plusUsesSelectedDate);
    console.log("Calendar select-then-tap-again scheduling test passed.");
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exit(1); });
