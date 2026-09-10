begin;

-- 簡易経費の登録・変更・削除で記録する履歴種別を許可する。
alter table public.cash_register_history
  drop constraint if exists cash_register_history_action_check;

alter table public.cash_register_history
  add constraint cash_register_history_action_check
  check (action in (
    'set_amount',
    'settlement',
    'reset',
    'expense',
    'supplies_expense',
    'supplies_expense_adjustment',
    'supplies_expense_delete'
  ));

-- 関数を置き換えた後も呼出権限が明示的に維持されるようにする。
revoke all on function public.create_simple_store_expenses(uuid, date, jsonb) from public, anon;
grant execute on function public.create_simple_store_expenses(uuid, date, jsonb) to authenticated;

commit;
