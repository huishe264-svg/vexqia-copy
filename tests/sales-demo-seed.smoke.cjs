const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const sql = fs.readFileSync(
  path.join(root, "supabase/migrations/20260903130000_seed_sales_demo_store.sql"),
  "utf8",
);

assert.match(sql, /where store\.name = '営業デモ店舗'/);
assert.match(sql, /Sales demo store is no longer empty; seed was not applied/);
assert.match(sql, /set_config\('request\.jwt\.claim\.sub', administrator_user_id::text, true\)/);
assert.doesNotMatch(sql, /\b(delete|truncate)\b/i);

for (const table of [
  "employees",
  "customers",
  "bottle_brands",
  "bottles",
  "sales_goal_settings",
  "monthly_sales_goals",
  "event_sales_goals",
  "schedules",
  "sales",
  "daily_settlements",
  "sale_companions",
  "cash_registers",
  "cash_register_history",
]) {
  assert.match(sql, new RegExp(`insert into public\\.${table}`));
}

assert.equal((sql.match(/d3e00000-0000-4000-8000-00000000000[1-5]/g) || []).length > 5, true);
assert.equal((sql.match(/d3c00000-0000-4000-8000-000000000010/g) || []).length > 1, true);
assert.equal((sql.match(/d3500000-0000-4000-8000-000000000021/g) || []).length > 1, true);
assert.match(sql, /'未収'/);
assert.match(sql, /'回収済み'/);
assert.match(sql, /'現金'/);
assert.match(sql, /'カード'/);
assert.match(sql, /'バースデー'/);
assert.match(sql, /daily_target_amount/);

console.log("sales demo seed smoke test passed");
