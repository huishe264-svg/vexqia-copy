begin;

-- 出前・タバコ等は未収でも注文時点でレジから支払われている。
alter table public.sales
  add column if not exists cash_deducted_extras_amount bigint not null default 0
  check (cash_deducted_extras_amount >= 0);

alter table public.cash_register_history drop constraint if exists cash_register_history_action_check;
alter table public.cash_register_history add constraint cash_register_history_action_check
check (action in (
  'set_amount','settlement','settlement_reopen','reset','expense',
  'supplies_expense','supplies_expense_adjustment','supplies_expense_delete',
  'unpaid_extras','unpaid_extras_adjustment','unpaid_extras_refund'
));

create or replace function public.prepare_unpaid_sale_extras_cash()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' then
    new.cash_deducted_extras_amount:=case when new.payment_status='未収'
      then greatest(coalesce(new.delivery_tobacco_amount,0),0) else 0 end;
  else
    -- 回収後も登録時に出金済みという事実を保持する。金額修正時だけ追随する。
    new.cash_deducted_extras_amount:=old.cash_deducted_extras_amount;
    if new.delivery_tobacco_amount is distinct from old.delivery_tobacco_amount
      and (old.payment_status='未収' or old.cash_deducted_extras_amount>0) then
      new.cash_deducted_extras_amount:=greatest(coalesce(new.delivery_tobacco_amount,0),0);
    elsif old.payment_status<>'未収' and new.payment_status='未収' then
      new.cash_deducted_extras_amount:=greatest(coalesce(new.delivery_tobacco_amount,0),0);
    end if;
  end if;
  return new;
end; $$;

create or replace function public.apply_unpaid_sale_extras_cash()
returns trigger language plpgsql security definer set search_path='' as $$
declare tracked_change bigint;cash_change bigint;before_amount bigint;saved_register public.cash_registers;
 actor uuid;history_action text;history_date date;history_store uuid;
begin
  if tg_op='INSERT' then
    tracked_change:=new.cash_deducted_extras_amount;actor:=coalesce((select auth.uid()),new.created_by,new.updated_by);
    history_action:='unpaid_extras';history_date:=new.business_date;history_store:=new.store_id;
  elsif tg_op='UPDATE' then
    tracked_change:=new.cash_deducted_extras_amount-old.cash_deducted_extras_amount;actor:=coalesce((select auth.uid()),new.updated_by,new.created_by);
    history_action:='unpaid_extras_adjustment';history_date:=new.business_date;history_store:=new.store_id;
  else
    tracked_change:=-old.cash_deducted_extras_amount;actor:=coalesce((select auth.uid()),old.updated_by,old.created_by);
    history_action:='unpaid_extras_refund';history_date:=old.business_date;history_store:=old.store_id;
  end if;
  if tracked_change=0 then return case when tg_op='DELETE' then old else new end;end if;
  cash_change:=-tracked_change;
  insert into public.cash_registers(store_id,base_amount,current_amount,updated_by)
  values(history_store,0,0,actor) on conflict(store_id) do nothing;
  select current_amount into before_amount from public.cash_registers where store_id=history_store for update;
  update public.cash_registers set current_amount=before_amount+cash_change,updated_at=now(),updated_by=actor
  where store_id=history_store returning * into saved_register;
  insert into public.cash_register_history(store_id,action,amount_delta,balance_before,balance_after,base_amount,business_date,created_by)
  values(history_store,history_action,cash_change,before_amount,saved_register.current_amount,saved_register.base_amount,history_date,actor);
  return case when tg_op='DELETE' then old else new end;
end; $$;

drop trigger if exists sales_prepare_unpaid_extras_cash on public.sales;
create trigger sales_prepare_unpaid_extras_cash before insert or update of payment_status,delivery_tobacco_amount on public.sales
for each row execute function public.prepare_unpaid_sale_extras_cash();
drop trigger if exists sales_apply_unpaid_extras_cash on public.sales;
create trigger sales_apply_unpaid_extras_cash after insert or update of payment_status,delivery_tobacco_amount or delete on public.sales
for each row execute function public.apply_unpaid_sale_extras_cash();

create or replace function public.settle_store_sales(target_store_id uuid,target_business_date date,target_sale_ids uuid[],target_consumables_amount bigint default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller_id uuid:=(select auth.uid());unique_sale_ids uuid[];matching_count integer;gross_amount bigint;cash_amount bigint;
 card_amount bigint;extras_amount bigint;unsettled_extras_amount bigint;cash_net_amount bigint;shortage_amount bigint;
 before_register bigint;after_register bigint;saved_settlement public.daily_settlements;saved_register public.cash_registers;
begin
  if caller_id is null or not exists(select 1 from public.store_users where store_id=target_store_id and user_id=caller_id and role in('owner','manager'))
    then raise exception 'Only store managers can settle sales' using errcode='42501';end if;
  if target_consumables_amount is null or target_consumables_amount<0 then raise exception 'Consumables amount must be zero or greater' using errcode='22023';end if;
  unique_sale_ids:=array(select distinct sale_id from unnest(coalesce(target_sale_ids,array[]::uuid[])) selected(sale_id));
  if cardinality(unique_sale_ids)=0 then raise exception 'No unsettled sales were selected' using errcode='22023';end if;
  perform 1 from public.sales where id=any(unique_sale_ids) for update;
  select count(*)::integer,coalesce(sum(total_amount),0)::bigint,
    coalesce(sum(total_amount) filter(where payment_method='現金'),0)::bigint,
    coalesce(sum(total_amount) filter(where payment_method='カード'),0)::bigint,
    coalesce(sum(delivery_tobacco_amount),0)::bigint,
    coalesce(sum(greatest(delivery_tobacco_amount-cash_deducted_extras_amount,0)),0)::bigint
  into matching_count,gross_amount,cash_amount,card_amount,extras_amount,unsettled_extras_amount
  from public.sales where id=any(unique_sale_ids) and store_id=target_store_id and business_date=target_business_date
    and payment_status='回収済み' and not coalesce(is_settled,false);
  if matching_count<>cardinality(unique_sale_ids) then raise exception 'Some sales are invalid or already settled' using errcode='22023';end if;
  cash_net_amount:=cash_amount-unsettled_extras_amount-target_consumables_amount;shortage_amount:=greatest(-cash_net_amount,0);
  insert into public.cash_registers(store_id,base_amount,current_amount,updated_by) values(target_store_id,0,0,caller_id) on conflict(store_id) do nothing;
  select current_amount into before_register from public.cash_registers where store_id=target_store_id for update;
  after_register:=before_register+cash_net_amount;
  insert into public.daily_settlements(store_id,business_date,consumables_amount,settled_sale_ids,settled_total_amount,
    settled_delivery_tobacco_amount,settled_net_amount,settled_cash_amount,settled_card_amount,settled_cash_net_amount,
    register_shortage_amount,register_balance_after)
  values(target_store_id,target_business_date,target_consumables_amount,unique_sale_ids,gross_amount,extras_amount,gross_amount-extras_amount,
    cash_amount,card_amount,cash_net_amount,shortage_amount,after_register) returning * into saved_settlement;
  update public.sales set is_settled=true,settled_at=saved_settlement.settled_at,settlement_id=saved_settlement.id where id=any(unique_sale_ids);
  update public.cash_registers set current_amount=after_register,updated_at=now(),updated_by=caller_id where store_id=target_store_id returning * into saved_register;
  insert into public.cash_register_history(store_id,action,amount_delta,balance_before,balance_after,base_amount,business_date,settlement_id,created_by)
  values(target_store_id,'settlement',cash_net_amount,before_register,after_register,saved_register.base_amount,target_business_date,saved_settlement.id,caller_id);
  return jsonb_build_object('settlement',to_jsonb(saved_settlement),'cash_register',to_jsonb(saved_register));
end; $$;
revoke all on function public.settle_store_sales(uuid,date,uuid[],bigint) from public,anon;
grant execute on function public.settle_store_sales(uuid,date,uuid[],bigint) to authenticated;

commit;