const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const edge = fs.readFileSync(path.join(root, "supabase/functions/manage-store-members/index.ts"), "utf8");
const migration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260901140000_reset_stale_store_invitations.sql"),
  "utf8",
);
const rpcMigration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260901150000_owner_invitation_rpc.sql"),
  "utf8",
);
const memberAndCashMigration = fs.readFileSync(
  path.join(root, "supabase/migrations/20260901160000_member_directory_and_cash_register.sql"),
  "utf8",
);
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");

assert.match(edge, /mailClient\.auth\.signInWithOtp/);
assert.match(edge, /callerClient\.rpc\("save_store_invitation"/);
assert.match(edge, /shouldCreateUser:\s*true/);
assert.match(edge, /emailRedirectTo:\s*redirectUrl/);
assert.doesNotMatch(edge, /membershipError/);
assert.doesNotMatch(edge, /INVITATION_FINALIZE_FAILED/);
assert.match(edge, /callerClient\.rpc\(\s*"get_store_member_directory"/);

assert.match(migration, /delete from public\.store_invitations/);
assert.match(migration, /where status = 'pending'/);
assert.doesNotMatch(migration, /delete from auth\.users/);
assert.doesNotMatch(migration, /delete from public\.store_users/);

assert.match(rpcMigration, /security definer/);
assert.match(rpcMigration, /membership\.role = 'owner'/);
assert.match(rpcMigration, /insert into public\.store_invitations/);
assert.match(rpcMigration, /grant execute on function public\.save_store_invitation/);

assert.match(memberAndCashMigration, /left join auth\.users/);
assert.match(memberAndCashMigration, /membership\.role = 'owner'/);
assert.match(memberAndCashMigration, /create table if not exists public\.cash_registers/);
assert.match(memberAndCashMigration, /create table if not exists public\.cash_register_history/);
assert.match(memberAndCashMigration, /create or replace function public\.settle_store_sales/);
assert.match(memberAndCashMigration, /shortage_amount := greatest\(-cash_net_amount, 0\)/);
assert.match(memberAndCashMigration, /after_register := before_register - shortage_amount/);
assert.match(memberAndCashMigration, /revoke insert, update, delete on public\.cash_registers from anon, authenticated/);

assert.match(html, /ログインメールを送信しました/);
assert.match(html, /同じメールのGoogleログインで参加できます/);

console.log("Invitation flow checks passed.");
