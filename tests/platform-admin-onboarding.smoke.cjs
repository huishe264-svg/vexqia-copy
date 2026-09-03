const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");

(async () => {
  const root = path.resolve(__dirname, "..");
  const migration = fs.readFileSync(path.join(root, "supabase/migrations/20260903100000_platform_admin_and_store_onboarding.sql"), "utf8");
  const assignmentMigration = fs.readFileSync(path.join(root, "supabase/migrations/20260903110000_assign_platform_admin.sql"), "utf8");
  const ownerRestoreMigration = fs.readFileSync(path.join(root, "supabase/migrations/20260903120000_restore_ownerless_stores.sql"), "utf8");
  const edge = fs.readFileSync(path.join(root, "supabase/functions/manage-store-members/index.ts"), "utf8");

  assert.match(migration, /create table if not exists public\.platform_admins/);
  assert.match(migration, /revoke all on public\.platform_admins from anon, authenticated/);
  assert.match(migration, /create or replace function public\.get_accessible_stores/);
  assert.match(migration, /create or replace function public\.create_managed_store/);
  assert.match(migration, /create or replace function public\.transfer_store_ownership/);
  assert.match(migration, /role in \('owner', 'manager', 'staff'\)/);
  assert.match(migration, /not exists \([\s\S]*from public\.platform_admins administrator[\s\S]*administrator\.user_id = membership\.user_id/);
  assert.match(migration, /previous_owner_action not in \('manager', 'remove'\)/);
  assert.match(assignmentMigration, /lower\('huishe264@gmail\.com'\)/);
  assert.match(assignmentMigration, /from auth\.users auth_user/);
  assert.match(assignmentMigration, /insert into public\.platform_admins/);
  assert.match(assignmentMigration, /select store\.id, administrator_user_id, 'manager'/);
  assert.match(ownerRestoreMigration, /set role = 'owner'/);
  assert.match(ownerRestoreMigration, /not exists \([\s\S]*owner_membership\.role = 'owner'/);
  assert.match(ownerRestoreMigration, /administrator_membership\.role = 'manager'/);
  assert.match(edge, /action === "create-store"/);
  assert.match(edge, /action === "transfer-owner"/);
  assert.match(edge, /callerClient\.rpc\("is_platform_admin"\)/);

  const browser = await chromium.launch({ headless: true, executablePath: "C:/Program Files/Google/Chrome/Application/chrome.exe" });
  const page = await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`,
  }));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js", route => route.fulfill({
    contentType: "application/javascript",
    body: `window.Chart=class{constructor(){}destroy(){}update(){}};`,
  }));
  await page.goto(`file:///${path.join(root, "index.html").replaceAll("\\", "/")}`);

  const result = await page.evaluate(async () => {
    currentAuthUser = { id: "platform-admin" };
    localStorage.removeItem("vexqia_store_id");
    db.rpc = async name => {
      if (name !== "get_accessible_stores") throw new Error("unexpected RPC");
      return { data: [
        { id: "store-a", name: "営業デモ店舗", access_role: "admin" },
        { id: "store-b", name: "導入店舗", access_role: "admin" },
      ], error: null };
    };
    await loadStore();
    currentStoreMember = { user_id: "platform-admin", role: "admin", employee_id: null };
    applyRoleNavigation();
    renderAdminStores();

    return {
      adminDetected: platformAdminMode && actualRole() === "admin",
      ownerCapabilities: isOwner() && isOwnerOrManager(),
      switcherVisible: !document.getElementById("storeSwitcherWrap").classList.contains("hidden") && document.getElementById("storeSwitcher").options.length === 2,
      adminMenuPrivate: !document.querySelector("[data-admin-only]").classList.contains("hidden"),
      adminPageExists: document.getElementById("page-admin").textContent.includes("初代オーナーのメールアドレス"),
      ownerInviteAvailable: Boolean(document.querySelector('#memberInviteRole option[value="owner"]')),
      noAdminRoleOption: !document.getElementById("memberInviteRole").textContent.includes("運営管理者"),
      storesRendered: document.getElementById("adminStoreList").textContent.includes("営業デモ店舗") && document.getElementById("adminStoreList").textContent.includes("導入店舗"),
    };
  });

  assert.deepEqual(result, {
    adminDetected: true,
    ownerCapabilities: true,
    switcherVisible: true,
    adminMenuPrivate: true,
    adminPageExists: true,
    ownerInviteAvailable: true,
    noAdminRoleOption: true,
    storesRendered: true,
  });

  await browser.close();
  console.log("platform admin onboarding smoke test passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
