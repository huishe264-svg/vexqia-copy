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
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");

assert.match(edge, /mailClient\.auth\.signInWithOtp/);
assert.match(edge, /callerClient\.rpc\("save_store_invitation"/);
assert.match(edge, /shouldCreateUser:\s*true/);
assert.match(edge, /emailRedirectTo:\s*appUrl/);
assert.doesNotMatch(edge, /membershipError/);
assert.doesNotMatch(edge, /INVITATION_FINALIZE_FAILED/);

assert.match(migration, /delete from public\.store_invitations/);
assert.match(migration, /where status = 'pending'/);
assert.doesNotMatch(migration, /delete from auth\.users/);
assert.doesNotMatch(migration, /delete from public\.store_users/);

assert.match(rpcMigration, /security definer/);
assert.match(rpcMigration, /membership\.role = 'owner'/);
assert.match(rpcMigration, /insert into public\.store_invitations/);
assert.match(rpcMigration, /grant execute on function public\.save_store_invitation/);

assert.match(html, /ログインメールを送信しました/);
assert.match(html, /同じメールのGoogleログインで参加できます/);

console.log("Invitation flow checks passed.");

