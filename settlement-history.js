// Compact daily settlement controls and independently paged history.
let simpleExpenseEntryExpanded=false;
const cashHistoryLabelBeforeOtherExpense=cashHistoryLabel;
cashHistoryLabel=function(action){return ['supplies_expense','supplies_expense_adjustment','supplies_expense_delete','expense'].includes(action)?'その他経費':cashHistoryLabelBeforeOtherExpense(action)};
const renderCashRegisterBeforeHistory=renderCashRegister;
renderCashRegister=function(){
  renderCashRegisterBeforeHistory();
  const box=$('cashRegisterSection'),card=box?.querySelector('.expense-entry-card'),cashCard=box?.querySelector('.cash-register-card');
  if(card){
    card.classList.remove('card');card.classList.add('cash-expense-entry');
    card.querySelector('.section-title').textContent='その他経費';
    const totalLabel=card.querySelector('.expense-entry-total span');if(totalLabel)totalLabel.textContent='その他経費合計';
    const recentTitle=card.querySelector('.expense-history .section-title');if(recentTitle)recentTitle.textContent='最近のその他経費';
    const hint=card.querySelector('#recordExpenseBtn + .hint');if(hint)hint.textContent='売上入力で記録済みの出前・タバコは含めず、レジ金から支払ったその他経費のレシート金額だけを入力します。';
    if(cashCard)cashCard.querySelector('.cash-register-actions')?.insertAdjacentElement('afterend',card);
    const fields=document.createElement('div');fields.id='simpleExpenseEntryFields';
    const title=card.querySelector('.section-title');let item=title?.nextElementSibling;
    while(item&&!item.matches('.expense-history,.history-toggle')){const next=item.nextElementSibling;fields.appendChild(item);item=next}
    title?.insertAdjacentElement('afterend',fields);
    const toggle=document.createElement('button');toggle.type='button';toggle.id='toggleSimpleExpenseEntry';toggle.className='secondary';
    const update=()=>{fields.classList.toggle('hidden',!simpleExpenseEntryExpanded);toggle.textContent=simpleExpenseEntryExpanded?'入力欄を閉じる':'＋ その他経費を登録';toggle.setAttribute('aria-expanded',String(simpleExpenseEntryExpanded))};
    toggle.setAttribute('aria-controls',fields.id);fields.before(toggle);toggle.onclick=()=>{simpleExpenseEntryExpanded=!simpleExpenseEntryExpanded;update()};update();
  }
  for(const [kind,parent,label] of [['cash',box?.querySelector('.cash-register-card'),'レジ金の全体履歴'],['expense',card,'その他経費の全体履歴']]){
    if(!parent)continue;const button=document.createElement('button');button.type='button';button.className='history-toggle';button.dataset.fullHistory=kind;button.textContent=label;button.onclick=()=>openFullFinanceHistory(kind);parent.appendChild(button);
  }
};
async function openFullFinanceHistory(kind){
  let modal=$('fullFinanceHistoryModal');
  if(!modal){modal=document.createElement('div');modal.id='fullFinanceHistoryModal';modal.className='modal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');document.body.appendChild(modal)}
  const cash=kind==='cash',historyStore=storeId;
  modal.innerHTML=`<div class="modal-card"><div class="modal-head"><h2>${cash?'レジ金':'その他経費'}の全体履歴</h2><button type="button" class="close-btn" aria-label="閉じる">×</button></div><div class="full-finance-history"></div><button type="button" class="secondary load-finance-history">さらに読み込む</button></div>`;
  modal.querySelector('.close-btn').onclick=()=>closeModal(modal.id);openModal(modal.id);
  const list=modal.querySelector('.full-finance-history'),button=modal.querySelector('.load-finance-history');let offset=0;
  async function next(){
    button.disabled=true;button.textContent='読み込み中…';
    try{
      let query=db.from(cash?'cash_register_history':'expenses').select('*').eq('store_id',historyStore);
      if(!cash)query=query.in('category',['簡易出金','備品・消耗品']).is('deleted_at',null).order('expense_date',{ascending:false});
      const result=await query.order('created_at',{ascending:false}).order('id',{ascending:false}).range(offset,offset+49);
      if(result.error)throw result.error;if(historyStore!==storeId||!list.isConnected)return;
      const rows=result.data||[];
      list.insertAdjacentHTML('beforeend',rows.map(row=>{
        const when=new Date(row.created_at).toLocaleString('ja-JP'),delta=Number(row.amount_delta||0);
        return cash?`<div class="cash-history-row"><div><strong>${esc(cashHistoryLabel(row.action))}</strong><small>${esc(when)}${row.business_date?` ・ ${esc(businessDateWithWeekday(row.business_date))}`:''} ・ ${esc(memberLabel(row.created_by))}</small></div><div class="cash-history-amount">${delta>0?'+':''}${signedYen(delta)}<span class="cash-history-balance">残高 ${signedYen(row.balance_after)}</span></div></div>`:`<div class="expense-history-row"><div>${esc(businessDateWithWeekday(row.expense_date))}<small style="display:block">${esc(when)} ・ ${esc(memberLabel(row.created_by))}</small></div><strong>−${yen(row.amount)}</strong></div>`;
      }).join(''));
      if(!offset&&!rows.length)list.innerHTML='<div class="empty">履歴はまだありません</div>';
      offset+=rows.length;button.hidden=rows.length<50;button.textContent='さらに読み込む';
    }catch(error){button.textContent='再読み込み';showStatus(friendlyErrorMessage(error,'履歴を読み込めませんでした。'),'error')}
    finally{button.disabled=false}
  }
  button.onclick=next;await next();
}

