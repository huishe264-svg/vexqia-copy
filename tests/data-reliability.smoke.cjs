const fs=require('fs');
const assert=require('assert');
const html=fs.readFileSync('index.html','utf8');
const js=fs.readFileSync('reliability.js','utf8');
const sql=fs.readFileSync('supabase/migrations/20260907100000_sales_reliability_foundation.sql','utf8');

assert(html.includes('src="./reliability.js?v=20260910-1"'),'reliability layer must load for every store');
assert(js.includes('crypto.randomUUID()'),'every save attempt needs an idempotency key');
assert(js.includes('create_reliable_sale'),'sale UI must use the transactional RPC');
assert(js.includes('入力内容は画面に残しています'),'failed saves must preserve user input');
assert(js.includes('同じ売上は既に保存済みです。二重登録はしていません。'),'duplicate retries need a clear message');
assert(js.includes('sale_audit_log'),'owner/manager must be able to inspect audit history');
assert(js.includes('check_store_data_integrity'),'settings must expose integrity checks');
assert(sql.includes('sales_store_client_request_unique'),'database must reject duplicate requests');
assert(sql.includes('sales_00_guard_settled'),'settled sales must be guarded at database level');
assert(sql.includes("action in ('baseline','created','updated','deleted')"),'audit action set must be constrained');
assert(sql.includes('revoke insert,update,delete on public.sale_audit_log'),'audit history must be immutable to clients');
assert(sql.includes('target_companion_ids')&&sql.includes('target_emptied_bottle_ids')&&sql.includes('target_receivable_sale_ids'),'related sale data must save in the same transaction');
console.log('Shared data reliability checks passed.');
