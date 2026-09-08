begin;

create or replace function public.create_simple_store_expenses(
  target_store_id uuid,
  target_expense_date date,
  target_amounts jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  item jsonb;
  amount_value bigint;
  saved public.expenses;
  saved_rows jsonb := '[]'::jsonb;
  item_count integer := 0;
begin
  if target_expense_date is null
    or target_amounts is null
    or jsonb_typeof(target_amounts) <> 'array'
    or jsonb_array_length(target_amounts) = 0
    or jsonb_array_length(target_amounts) > 50 then
    raise exception 'Invalid simple expense data' using errcode = '22023';
  end if;

  for item in select value from jsonb_array_elements(target_amounts)
  loop
    if jsonb_typeof(item) <> 'number' or (item #>> '{}') !~ '^[0-9]+$' then
      raise exception 'Expense amount must be a positive integer' using errcode = '22023';
    end if;

    amount_value := (item #>> '{}')::bigint;
    if amount_value <= 0 then
      raise exception 'Expense amount must be greater than zero' using errcode = '22023';
    end if;

    saved := public.create_store_expense(
      target_store_id,
      target_expense_date,
      amount_value,
      '',
      '簡易出金',
      '現金',
      null,
      null
    );
    saved_rows := saved_rows || jsonb_build_array(to_jsonb(saved));
    item_count := item_count + 1;
  end loop;

  return jsonb_build_object(
    'expenses', saved_rows,
    'count', item_count,
    'total_amount', (
      select coalesce(sum((value #>> '{}')::bigint), 0)
      from jsonb_array_elements(target_amounts)
    )
  );
end;
$$;

revoke all on function public.create_simple_store_expenses(uuid, date, jsonb) from public, anon;
grant execute on function public.create_simple_store_expenses(uuid, date, jsonb) to authenticated;

commit;
