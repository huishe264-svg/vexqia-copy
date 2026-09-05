const fs=require('fs');
const assert=require('assert');
const html=fs.readFileSync('index.html','utf8');
const js=fs.readFileSync('demo-settings.js','utf8');
const sql=fs.readFileSync('supabase/migrations/20260905140000_sales_demo_operating_settings.sql','utf8');

assert(html.includes('src="./demo-settings.js"'),'demo settings script must load');
assert(js.includes('demo_configuration_enabled'),'settings must be gated by a database flag');
assert(js.includes('営業デモ限定'),'settings must clearly identify demo-only scope');
assert(js.includes('monthly_direct'),'monthly direct goal mode must exist');
assert(js.includes('残り営業日あたり必要額'),'monthly direct goals need an actionable daily guide');
assert(js.includes('account_label')&&js.includes('deduction_label'),'store terminology must be configurable');
assert(js.includes('payment_methods'),'payment methods must be configurable');
assert(js.includes('bottle_management_enabled')&&js.includes('cash_register_enabled'),'optional modules must be configurable');
assert(sql.includes("where name='営業デモ店舗'"),'only the sales demo store must be seeded');
assert(sql.includes("demo_configuration_enabled=true"),'demo feature gate must be enabled only by its row');
assert(!sql.includes("update public.stores set"),'existing stores must not be modified');
console.log('Sales demo operating settings checks passed.');
