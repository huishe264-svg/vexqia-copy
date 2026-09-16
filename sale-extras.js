// Multiple receipt amounts on sale entry; sales continue storing one compatible total.
(function setupSaleExtraAmounts(){
 const totalInput=$('extraAmount');if(!totalInput)return;
 const field=totalInput.closest('.field');
 totalInput.type='hidden';
 totalInput.value='0';
 const list=document.createElement('div');list.id='saleExtraAmounts';
 const add=document.createElement('button');add.type='button';add.id='addSaleExtraAmount';add.className='secondary';add.textContent='＋ 金額を追加';
 const total=document.createElement('div');total.className='sale-extra-total';total.innerHTML='<span>出前・タバコ等 合計</span><strong id="saleExtraTotal">¥0</strong>';
 totalInput.insertAdjacentElement('afterend',list);list.insertAdjacentElement('afterend',add);add.insertAdjacentElement('afterend',total);
 function amountRow(value=''){
  const row=document.createElement('div');row.className='sale-extra-row';
  row.innerHTML=`<input type="number" inputmode="numeric" class="sale-extra-amount" min="0" step="1" placeholder="金額を入力" value="${esc(value)}" aria-label="出前・タバコ等の金額"><button type="button" class="remove-btn" aria-label="この金額を削除">×</button>`;
  row.querySelector('input').oninput=calculate;
  row.querySelector('button').onclick=()=>{row.remove();if(!list.children.length)addRow();calculate()};
  return row;
 }
 function addRow(value=''){const row=amountRow(value);list.appendChild(row);return row}
 function calculate(){
  const amounts=[...list.querySelectorAll('.sale-extra-amount')].map(input=>Math.max(0,Math.trunc(Number(input.value)||0)));
  const sum=amounts.reduce((n,value)=>n+value,0);totalInput.value=String(sum);$('saleExtraTotal').textContent=yen(sum);
  totalInput.dispatchEvent(new Event('input',{bubbles:true}));return sum;
 }
 function reset(){list.innerHTML='';addRow();calculate()}
 add.onclick=()=>{const row=addRow();row.querySelector('input').focus();calculate()};
 reset();
 const previousReset=resetInputImproved;
 resetInputImproved=function(){previousReset();reset()};
 window.saleExtraAmounts={addRow,calculate,reset};
 const style=document.createElement('style');
 style.textContent='.sale-extra-row{display:grid;grid-template-columns:1fr 44px;gap:8px;margin-bottom:8px}.sale-extra-total{display:flex;justify-content:space-between;align-items:center;margin-top:10px;padding:12px;border-radius:12px;background:#f3f5f7;color:#132238}.sale-extra-total span{font-size:13px;font-weight:750}.sale-extra-total strong{font-size:18px}#addSaleExtraAmount{margin-top:2px}';
 document.head.appendChild(style);
})();
