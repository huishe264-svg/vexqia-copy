const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const sql = fs.readFileSync(
  path.resolve(__dirname, "../supabase/migrations/20260914120000_complete_sales_demo_month.sql"),
  "utf8",
);

assert.match(sql, /where store\.name = '営業デモ店舗'/);
assert.match(sql, /expense_management_mode = 'full'/);
assert.match(sql, /date '2026-08-01'/);
assert.match(sql, /target_amount = 3710000/);
assert.match(sql, /'d4500000-0000-4000-8000-000000000036'/);
assert.match(sql, /'d4600000-0000-4000-8000-000000000017'/);
assert.match(sql, /'d4e00000-0000-4000-8000-000000000008'/);
assert.match(sql, /'未収', null/);
assert.match(sql, /settled_total_amount/);
assert.match(sql, /settled_net_amount/);
assert.match(sql, /insert into public\.expenses/);
assert.doesNotMatch(sql, /\btruncate\b/i);

const businessDates = new Set([...sql.matchAll(/date '(2026-08-\d{2})'/g)].map(match => match[1]));
for (const date of ["2026-08-03", "2026-08-04", "2026-08-05", "2026-08-07", "2026-08-31"]) {
  assert.ok(businessDates.has(date), `missing demo business date ${date}`);
}

console.log("Complete sales demo month checks passed.");
