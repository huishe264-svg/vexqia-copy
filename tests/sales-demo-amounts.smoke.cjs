const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sql = fs.readFileSync(
  path.resolve(__dirname, "../supabase/migrations/20260903132000_rebalance_sales_demo_amounts.sql"),
  "utf8",
);
const app = fs.readFileSync(path.resolve(__dirname, "../index.html"), "utf8");

assert.match(sql, /where store\.name = '営業デモ店舗'/);
assert.match(sql, /weekday_goal = 150000/);
assert.match(sql, /weekend_goal = 220000/);
assert.match(sql, /target_amount = case when goal_month = this_month then 4170000 else 3710000 end/);
assert.match(sql, /base_amount = 30000/);
assert.match(sql, /current_amount = 416000/);
assert.match(sql, /settled_total_amount = demo_totals\.total_amount/);
assert.match(sql, /d3600000-0000-4000-8000-000000000002[\s\S]*255000::bigint/);
assert.match(sql, /d3800000-0000-4000-8000-000000000001/);
assert.match(app, /renderAnalyticsBeforeAverageRounding/);
assert.match(app, /yen\(Math\.round\(people\?actual\/people:0\)\)/);

console.log("sales demo amount rebalance smoke test passed");
