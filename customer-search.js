/* Readings are generated locally; customer names and notes never go to a reading API. */
function customerNameMatch(customer, query) {
 const q=normalizeText(query), name=normalizeText(customer?.name||'');
 if(!q)return {index:0,direct:true};
 const directIndex=name.indexOf(q);
 if(directIndex>=0)return {index:directIndex,direct:true};
 const chars=Array.from(name), dictionary=window.VEXQIA_KANJI_READINGS||{};
 const voiced={'か':'が','き':'ぎ','く':'ぐ','け':'げ','こ':'ご','さ':'ざ','し':'じ','す':'ず','せ':'ぜ','そ':'ぞ','た':'だ','ち':'ぢ','つ':'づ','て':'で','と':'ど','は':'ば','ひ':'び','ふ':'ぶ','へ':'べ','ほ':'ぼ'};
 const options=chars.map((ch,i)=>{
  const readings=[ch,...(dictionary[ch]||[]).map(normalizeText)];
  if(i>0)for(const r of [...readings])if(voiced[r[0]])readings.push(voiced[r[0]]+r.slice(1));
  return [...new Set(readings)];
 });
 // Match a prefix starting at any character, without generating exponential combinations.
 const memo=new Map();
 function walk(i,pos){
  if(pos===q.length)return true;
  if(i===options.length)return false;
  const key=i+':'+pos;if(memo.has(key))return memo.get(key);
  const tail=q.slice(pos);
  const found=options[i].some(r=>r.startsWith(tail)||(tail.startsWith(r)&&walk(i+1,pos+r.length)));
  memo.set(key,found);return found;
 }
 for(let i=0;i<chars.length;i++)if(walk(i,0))return {index:i,direct:false};
 return null;
}
function customerNameMatches(customer,query){return Boolean(customerNameMatch(customer,query))}
function customerNameOrder(a,b,query){const q=normalizeText(query),am=customerNameMatch(a,q),bm=customerNameMatch(b,q);if(!q)return 0;if(!am)return 1;if(!bm)return-1;return am.index-bm.index||Number(bm.direct)-Number(am.direct)||directVisitCount(b.id)-directVisitCount(a.id)||String(a.name||'').localeCompare(String(b.name||''),'ja')}

// Keep all existing customer-search consumers on the same matching rules.
searchableCustomer=function(customer){return {includes:q=>customerNameMatches(customer,q)}};

const customerPreview=document.createElement('div');
customerPreview.id='customerQuickPreview';customerPreview.className='modal';
customerPreview.setAttribute('role','dialog');customerPreview.setAttribute('aria-modal','true');
customerPreview.setAttribute('aria-labelledby','customerPreviewTitle');
customerPreview.innerHTML='<div class="modal-card"><div class="modal-head"><h2 id="customerPreviewTitle">顧客プレビュー</h2><button type="button" class="close-btn" aria-label="プレビューを閉じる">×</button></div><div id="customerPreviewBody"></div></div>';
document.body.appendChild(customerPreview);
let previewOrigin=null;
function closeCustomerPreview(){closeModal('customerQuickPreview');previewOrigin?.focus();}
customerPreview.querySelector('button').onclick=closeCustomerPreview;
customerPreview.addEventListener('click',event=>{if(event.target===customerPreview)closeCustomerPreview()});
customerPreview.addEventListener('keydown',event=>{if(event.key==='Escape'){event.stopPropagation();closeCustomerPreview()}if(event.key==='Tab'){event.preventDefault();customerPreview.querySelector('button').focus()}});
function openCustomerPreview(id,origin){
 const c=activeCustomers().find(row=>row.id===id);if(!c)return;
 previewOrigin=origin;const employee=employees.find(row=>row.id===c.employee_id);
 $('customerPreviewBody').innerHTML=`<div class="card"><h3>${esc(c.name)}</h3><p>${esc(employee?.name||'担当口座未設定')} ・ 本人来店 ${directVisitCount(c.id)}回</p><div class="section-title">備考</div><div class="customer-preview-notes">${esc(c.notes||'備考は登録されていません。')}</div></div>`;
 openModal('customerQuickPreview');customerPreview.querySelector('button').focus();
}
renderCustomerSuggestions=function(query){
 const box=$('customerSuggestions'),q=normalizeText(query);
 if(!q){box.classList.remove('show');return;}
 const rows=activeCustomers().filter(customer=>customerNameMatches(customer,q)).sort((a,b)=>customerNameOrder(a,b,q)).slice(0,15);
 box.innerHTML=rows.length?rows.map(c=>`<div class="customer-suggestion-row"><button type="button" class="suggestion customer-pick" data-pick="${esc(c.id)}"><b>${esc(c.name)}</b><small>本人来店 ${directVisitCount(c.id)}回 ・ 同伴 ${companionVisitCount(c.id)}回</small></button><button type="button" class="customer-preview-button" data-preview="${esc(c.id)}" aria-label="${esc(c.name)}の備考・詳細">詳細</button></div>`).join(''):'<button type="button" class="suggestion customer-pick" id="noCustomer"><b>該当なし</b><small>新規顧客として登録</small></button>';
 box.classList.add('show');
 box.querySelectorAll('[data-pick]').forEach(button=>button.onclick=()=>selectMainCustomer(button.dataset.pick));
 box.querySelectorAll('[data-preview]').forEach(button=>button.onclick=event=>{event.stopPropagation();openCustomerPreview(button.dataset.preview,button)});
 if($('noCustomer'))$('noCustomer').onclick=()=>{openNewCustomerModal();$('newCustomerName').value=query};
};
const customerSearchStyle=document.createElement('style');
customerSearchStyle.textContent='.customer-suggestion-row{display:flex;align-items:stretch;border-bottom:1px solid #e2e6eb}.customer-pick{flex:1;min-width:0;width:100%;text-align:left;background:white;color:#132238;border:0;min-height:48px;font:inherit}.customer-pick b,.customer-pick small{display:block}.customer-preview-button{flex:0 0 60px;min-height:48px;background:#f3f5f7;color:#132238;border:0;border-left:1px solid #e2e6eb;font:inherit}.customer-preview-notes{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.7;font-size:16px}#customerQuickPreview{z-index:10050}';
document.head.appendChild(customerSearchStyle);
