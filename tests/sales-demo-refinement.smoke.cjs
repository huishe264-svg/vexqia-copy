const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sql = fs.readFileSync(
  path.resolve(__dirname, "../supabase/migrations/20260903131000_refine_sales_demo_store.sql"),
  "utf8",
);

assert.match(sql, /where store\.name = '営業デモ店舗'/);
assert.match(sql, /delete from public\.cash_register_history history/);
assert.match(sql, /history\.store_id = demo_store_id/);
assert.match(sql, /history\.id not in/);
assert.doesNotMatch(sql, /delete from public\.(?!cash_register_history)/);
assert.match(sql, /set total_amount = 200000/);
assert.match(sql, /settled_total_amount = 760000/);
assert.match(sql, /settled_net_amount = 740000/);
assert.match(sql, /settled_card_amount = 540000/);

console.log("sales demo refinement smoke test passed");
