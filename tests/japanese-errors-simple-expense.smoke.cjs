const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260910120000_fix_simple_expense_history_actions.sql"), "utf8");
  for (const action of ["supplies_expense", "supplies_expense_adjustment", "supplies_expense_delete"]) {
    assert.match(migration, new RegExp(`'${action}'`));
  }
  assert.match(migration, /grant execute on function public\.create_simple_store_expenses/);
  assert.match(html, /function friendlyErrorMessage/);

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
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`, { waitUntil: "domcontentloaded" });
  const messages = await page.evaluate(() => [
    friendlyErrorMessage({ code: "23514", message: 'new row violates check constraint "cash_register_history_action_check"' }),
    friendlyErrorMessage({ code: "42501", message: "permission denied for table expenses" }),
    friendlyErrorMessage({ code: "23505", message: "duplicate key value violates unique constraint" }),
    friendlyErrorMessage({ code: "PGRST202", message: "Could not find the function in the schema cache" }),
    friendlyErrorMessage({ message: "Failed to fetch" }),
    friendlyErrorMessage({ message: "Unexpected backend failure" }),
  ]);
  assert.deepEqual(messages, [
    "レジ金履歴の保存設定に問題があります。管理者へお知らせください。",
    "この操作を行う権限がありません。店舗の権限設定を確認してください。",
    "同じ内容のデータがすでに登録されています。",
    "サーバーの更新が反映されていません。管理者へお知らせください。",
    "通信できませんでした。電波状況を確認して、もう一度お試しください。",
    "処理を完了できませんでした。時間をおいてもう一度お試しください。",
  ]);
  assert.ok(messages.every(message => /[ぁ-んァ-ヶ一-龠]/.test(message)));
  console.log("Japanese error and simple expense checks passed.");
  await browser.close();
})().catch(error => {
  console.error(error);
  process.exit(1);
});
