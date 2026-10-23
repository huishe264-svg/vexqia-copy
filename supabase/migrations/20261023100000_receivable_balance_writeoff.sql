begin;

-- A partial payment remains in the payment history while only the unpaid
-- balance can be closed. Write-offs never create sales or cash movements.
create table if not exists public.receivable_writeoffs (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  receivable_sale_id uuid not null references public.sales(id) on delete cascade,
  amount bigint not null check (amount > 0),
  reason text not null default '未収残額の消去',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint receivable_writeoffs_receivable_key unique (receivable_sale_id)
);
create index if not exists receivable_writeoffs_store_created_idx on public.receivable_writeoffs(store_id,created_at desc);
alter table public.receivable_writeoffs enable row level security;
drop policy if exists "store members read receivable writeoffs" on public.receivable_writeoffs;
create policy "store members read receivable writeoffs" on public.receivable_writeoffs for select to authenticated using(public.is_store_member(store_id));
revoke insert,update,delete on public.receivable_writeoffs from anon,authenticated;
grant select on public.receivable_writeoffs to authenticated;

create or replace function public.refresh_receivable_balance(target_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare original public.sales;paid bigint;written_off bigint;resolved bigint;payment_id uuid;method text;has_resolution boolean;
begin
 select * into original from public.sales where id=target_id for update;
 if not found then return;end if;
 select coalesce(sum(allocated_amount),0) into paid from public.sale_receivable_links where receivable_sale_id=target_id;
 select coalesce(sum(amount),0) into written_off from public.receivable_writeoffs where receivable_sale_id=target_id;
 resolved:=paid+written_off;
 if resolved>original.total_amount then raise exception '未収の元金を超える返済・消去は登録できません' using errcode='22023';end if;
 select p.id,p.payment_method into payment_id,method from public.sale_receivable_links l join public.sales p on p.id=l.payment_sale_id
 where l.receivable_sale_id=target_id and l.allocated_amount>0 order by l.created_at,l.id limit 1;
 has_resolution:=exists(select 1 from public.sale_receivable_links where receivable_sale_id=target_id)
   or exists(select 1 from public.receivable_writeoffs where receivable_sale_id=target_id);
 update public.sales set
  receivable_remaining_amount=case when has_resolution then original.total_amount-resolved else null end,
  payment_status=case when resolved>=original.total_amount then '回収済み' else '未収' end,
  payment_method=case when resolved>=original.total_amount then method else null end,
  recognized_via_sale_id=case when resolved>=original.total_amount then payment_id else null end,
  updated_by=coalesce((select auth.uid()),updated_by)
 where id=target_id;
end; $$;
revoke all on function public.refresh_receivable_balance(uuid) from public,anon,authenticated;

create or replace function public.write_off_receivable_balance(target_store_id uuid,target_receivable_sale_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare caller uuid:=(select auth.uid());debt public.sales;paid bigint;remaining bigint;saved public.receivable_writeoffs;
begin
 if caller is null or not public.is_store_owner_or_manager(target_store_id) then raise exception '未収残額を消去できるのはオーナー・店長だけです' using errcode='42501';end if;
 select * into debt from public.sales where id=target_receivable_sale_id and store_id=target_store_id for update;
 if not found then raise exception '未収伝票が見つかりません' using errcode='P0002';end if;
 if debt.payment_status<>'未収' or debt.is_settled then raise exception '消去できる未収残額がありません' using errcode='22023';end if;
 select coalesce(sum(allocated_amount),0) into paid from public.sale_receivable_links where receivable_sale_id=debt.id;
 if paid<=0 then raise exception '一部入金後の未収だけ残額を消去できます' using errcode='22023';end if;
 remaining:=coalesce(debt.receivable_remaining_amount,debt.total_amount-paid);
 if remaining<=0 or remaining>=debt.total_amount then raise exception '消去できる未収残額がありません' using errcode='22023';end if;
 insert into public.receivable_writeoffs(store_id,receivable_sale_id,amount,created_by)
 values(target_store_id,debt.id,remaining,caller) returning * into saved;
 perform public.refresh_receivable_balance(debt.id);
 return jsonb_build_object('receivable_sale_id',debt.id,'paid_amount',paid,'written_off_amount',saved.amount,'remaining_amount',0);
end; $$;
revoke all on function public.write_off_receivable_balance(uuid,uuid) from public,anon;
grant execute on function public.write_off_receivable_balance(uuid,uuid) to authenticated;

commit;

