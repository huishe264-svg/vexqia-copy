// Receivable recovery and post-registration companion editing.
let saleReceivableLinks=[];
let selectedReceivableIds=new Set();

document.head.insertAdjacentHTML("beforeend",`<style>
.receivable-toggle{width:100%;min-height:48px;border:1px solid #c6a15b;background:#fff;color:#132238;border-radius:12px;font-weight:800}
.receivable-option{display:flex;align-items:center;gap:10px;padding:11px 0;border-top:1px solid #e5e9ef}
.receivable-option input{width:22px;height:22px;flex:0 0 auto}.receivable-option-copy{display:flex;justify-content:space-between;gap:8px;width:100%}
.receivable-summary{margin-top:10px;padding:12px;border-radius:10px;background:#f3f5f7;color:#334155;font-size:13px}.receivable-summary strong{color:#132238}
.sale-link-note{margin:0 0 12px;padding:12px;border:1px solid #d8c08a;border-radius:10px;background:#fffaf0;color:#5c461d;font-size:13px}
.edit-companion-list{display:flex;flex-wrap:wrap;gap:7px;margin:8px 0}.edit-companion-chip{display:inline-flex;align-items:center;gap:6px;padding:7px 9px;border-radius:999px;background:#eef1f5;font-size:13px}
.edit-companion-chip button{border:0;background:transparent;font-size:18px;line-height:1;color:#6b7280}.recovery-card{border-color:#d8c08a;background:#fffdf8}
</style>`);

function revenueBearingSale(sale){return !sale.recognized_via_sale_id}
isRecovered=function(sale){return sale.payment_status==="回収済み"&&revenueBearingSale(sale)};
recoveredSales=function(rows){return rows.filter(isRecovered)};
totalForCustomer=function(id){return sales.filter(s=>s.customer_id===id&&revenueBearingSale(s)).reduce((sum,s)=>sum+Number(s.total_amount||0),0)};
directVisitCount=function(id){return sales.filter(s=>s.customer_id===id&&s.record_type!=="receivable_payment").length};

function linksPaidBy(saleId){return saleReceivableLinks.filter(link=>link.payment_sale_id===saleId)}
function linkForReceivable(saleId){return saleReceivableLinks.find(link=>link.receivable_sale_id===saleId)}
function availableReceivables(customerId){return sales.filter(s=>s.customer_id===customerId&&s.payment_status==="未収"&&!s.recognized_via_sale_id)}

function renderReceivableCombine(){
  const card=$("receivableCombineCard");if(!card)return;
  const customerId=$("customerId").value,rows=availableReceivables(customerId),canCombine=selectedPaymentStatus==="回収済み";
  for(const id of [...selectedReceivableIds])if(!rows.some(s=>s.id===id))selectedReceivableIds.delete(id);
  if(!customerId||!rows.length){card.classList.add("hidden");selectedReceivableIds.clear();return}
  card.classList.remove("hidden");
  const expanded=card.dataset.expanded==="true";
  const selected=rows.filter(s=>selectedReceivableIds.has(s.id)),selectedTotal=totalSales(selected);
  card.innerHTML=`<div class="section-title">過去の未収</div><button type="button" class="receivable-toggle" id="toggleReceivableCombine" ${canCombine?"":"disabled"}>${selected.length?`✓ 前回の未収 ${selected.length}件を含む`:`前回の未収を含む`}</button>${!canCombine?'<div class="hint">「回収済み」と支払方法を選ぶと合算できます。</div>':""}<div id="receivableOptions" class="${expanded&&canCombine?"":"hidden"}">${rows.map(s=>`<label class="receivable-option"><input type="checkbox" data-receivable-id="${s.id}" ${selectedReceivableIds.has(s.id)?"checked":""}><span class="receivable-option-copy"><span>${esc(s.business_date)}の未収</span><strong>${yen(s.total_amount)}</strong></span></label>`).join("")}<div class="receivable-summary">合計金額には、今回分・選択した未収・端数調整を含む<strong>実際の伝票金額</strong>を入力してください。<br>選択した未収の元金：<strong>${yen(selectedTotal)}</strong></div></div>`;
  const toggle=$("toggleReceivableCombine");if(toggle)toggle.onclick=()=>{card.dataset.expanded=expanded?"false":"true";renderReceivableCombine()};
  card.querySelectorAll("[data-receivable-id]").forEach(input=>input.onchange=()=>{input.checked?selectedReceivableIds.add(input.dataset.receivableId):selectedReceivableIds.delete(input.dataset.receivableId);card.dataset.expanded="true";renderReceivableCombine()});
}

const loadAllBeforeReceivables=loadAll;
loadAll=async function(){await loadAllBeforeReceivables();const result=await db.from("sale_receivable_links").select("*").eq("store_id",storeId);if(result.error)throw result.error;saleReceivableLinks=result.data||[];renderReceivableCombine()};
const selectMainCustomerBeforeReceivables=selectMainCustomer;
selectMainCustomer=function(id){selectedReceivableIds.clear();const result=selectMainCustomerBeforeReceivables(id);renderReceivableCombine();return result};
document.querySelectorAll('[data-group="paymentStatus"],[data-group="paymentMethod"]').forEach(button=>button.addEventListener("click",()=>setTimeout(renderReceivableCombine,0)));
const resetInputBeforeReceivables=resetInputImproved;
resetInputImproved=function(){selectedReceivableIds.clear();if($("receivableCombineCard"))$("receivableCombineCard").dataset.expanded="false";resetInputBeforeReceivables();renderReceivableCombine()};

const normalSaleSave=$("saveBtn").onclick;
$("saveBtn").onclick=async function(event){
  const receivableIds=[...selectedReceivableIds];if(!receivableIds.length)return normalSaleSave.call(this,event);
  if(selectedPaymentStatus!=="回収済み"||!selectedPaymentMethod)return showStatus("未収を含める場合は、回収済みと支払方法を選択してください。","error");
  if(currentStoreMember?.role==="staff"&&!currentStoreMember.employee_id)return showStatus("口座との紐付けが未設定です。オーナーに設定を依頼してください。","error");
  if(!validateSaleWithBrands())return showStatus("入力内容を確認してください","error");
  const customerId=$("customerId").value,customer=customers.find(item=>item.id===customerId),amount=Number($("totalAmount").value),method=selectedPaymentMethod,brandValue=$("newBottleBrandSelect").value,emptiedBottleIds=Object.entries(existingBottleStates).filter(([,state])=>state==="空いた").map(([id])=>id),button=$("saveBtn");
  let pendingBottle=null,paymentSaleId=null;
  if(brandValue==="__custom__")pendingBottle={brand_id:null,name:$("directBottleName").value.trim(),bottle_number:$("directBottleNumber").value.trim()||null};
  else if(brandValue){const brand=bottleBrands.find(item=>item.id===brandValue);if(!brand)return showStatus("選択した銘柄が見つかりません","error");pendingBottle={brand_id:brand.id,name:brand.name,bottle_number:$("masterBottleNumber").value.trim()||null}}
  button.disabled=true;button.textContent="登録中…";
  try{
    if(pendingBottle&&!pendingBottle.brand_id){const brand=await ensureBottleBrand(pendingBottle.name);pendingBottle.brand_id=brand.id;pendingBottle.name=brand.name}
    const companionIds=await resolveCompanionIds();
    const inserted=await db.from("sales").insert({store_id:storeId,business_date:$("businessDate").value,customer_id:customerId,employee_id:$("employeeSelect").value,payment_status:"回収済み",payment_method:method,party_size:Number($("partySize").value),total_amount:amount,delivery_tobacco_amount:Number($("extraAmount").value||0),consumables_amount:0,bottle_id:pendingBottle?null:($("bottleSelect").value||null),notes:$("notes").value.trim()||null,companion_id:null,is_settled:false,settled_at:null,settlement_id:null,created_by:currentAuthUser.id,updated_by:currentAuthUser.id,record_type:"combined_sale"}).select("*").single();
    if(inserted.error)throw inserted.error;paymentSaleId=inserted.data.id;
    const attached=await db.rpc("attach_receivables_to_sale",{target_store_id:storeId,target_payment_sale_id:paymentSaleId,target_receivable_sale_ids:receivableIds});if(attached.error)throw attached.error;
    if(pendingBottle){const created=await db.from("bottles").insert({store_id:storeId,customer_id:customerId,brand_id:pendingBottle.brand_id,name:pendingBottle.name,bottle_number:pendingBottle.bottle_number,status:"保有中"}).select("*").single();if(created.error)throw created.error;const linked=await db.from("sales").update({bottle_id:created.data.id}).eq("id",paymentSaleId);if(linked.error)throw linked.error}
    if(companionIds.length){const companions=await db.rpc("replace_sale_companions",{target_store_id:storeId,target_sale_id:paymentSaleId,target_customer_ids:companionIds});if(companions.error)throw companions.error}
    if(emptiedBottleIds.length){const emptied=await db.from("bottles").update({status:"飲み切り"}).in("id",emptiedBottleIds).eq("store_id",storeId).eq("customer_id",customerId);if(emptied.error)throw emptied.error}
    const count=receivableIds.length;resetInputImproved();await loadAll();showSaleSuccess(customer,amount,method,brandValue==="__custom__");showStatus(`売上を登録し、過去の未収${count}件を回収済みにしました。`,"success")
  }catch(error){if(paymentSaleId)await db.rpc("delete_sale_with_receivable_restore",{target_store_id:storeId,target_sale_id:paymentSaleId});showStatus(error.message||"合算会計を登録できませんでした","error")}
  finally{button.disabled=currentStoreMember?.role==="staff"&&!currentStoreMember.employee_id;button.textContent="売上を登録する"}
};

const saleCardBeforeReceivables=saleCard;
saleCard=function(s,showBusinessDate=false){
  let html=saleCardBeforeReceivables(s,showBusinessDate),note="";const outgoing=linksPaidBy(s.id),incoming=linkForReceivable(s.id);
  if(incoming){const payment=sales.find(row=>row.id===incoming.payment_sale_id);note=`<div class="sale-link-note">${esc(payment?.business_date||"")}の会計に合算して回収済み（集計対象外）</div>`}
  else if(outgoing.length){note=`<div class="sale-link-note">過去の未収 ${yen(outgoing.reduce((sum,row)=>sum+Number(row.original_receivable_amount||0),0))} を含む伝票</div>`}
  else if(s.record_type==="receivable_payment")note='<div class="sale-link-note">過去の未収を単独で回収した伝票</div>';
  if(!note)return html;const end=html.lastIndexOf("</div>");return end<0?html+note:html.slice(0,end)+note+html.slice(end)
};

async function resolveEditedCompanions(mainCustomerId,names){const ids=[];for(const raw of names){const name=raw.trim();if(!name)continue;let customer=activeCustomers().find(c=>normalizeText(c.name)===normalizeText(name));if(!customer){const created=await db.from("customers").insert({store_id:storeId,name,employee_id:null,notes:null}).select("*").single();if(created.error)throw created.error;customer=created.data;customers.push(customer)}if(customer.id!==mainCustomerId&&!ids.includes(customer.id))ids.push(customer.id)}return ids}

openSaleEditor=function(id){
  const s=sales.find(x=>x.id===id);if(!s)return;const incoming=linkForReceivable(s.id),outgoing=linksPaidBy(s.id),locked=Boolean(incoming),editable=canEditSale(s)&&!locked,creator=memberLabel(s.created_by),currentCompanionIds=saleCompanions.filter(row=>row.sale_id===s.id).map(row=>row.customer_id),payment=sales.find(row=>row.id===incoming?.payment_sale_id),linkedTotal=outgoing.reduce((sum,row)=>sum+Number(row.original_receivable_amount||0),0);
  openModal("saleEditModal");
  const linkNote=incoming?`<div class="sale-link-note">この未収は ${esc(payment?.business_date||"")} の会計に合算して回収済みです。元の来店履歴として残り、売上には二重計上されません。</div>`:outgoing.length?`<div class="sale-link-note">この伝票には過去の未収 ${yen(linkedTotal)} が含まれています。入力した合計金額だけをこの日の売上に計上します。</div>`:s.record_type==="receivable_payment"?'<div class="sale-link-note">過去の未収を単独で回収した伝票です。</div>':"";
  const companionNames=currentCompanionIds.map(cid=>customers.find(c=>c.id===cid)?.name).filter(Boolean);
  const companionSection=s.record_type==="receivable_payment"?"":`<div class="field"><label>同伴者（任意）</label><div id="editCompanionList" class="edit-companion-list"></div>${editable?`<div class="row"><input id="editCompanionInput" list="editCompanionOptions" placeholder="顧客を検索、または名前を入力"><button type="button" class="small-btn" id="addEditCompanion">＋ 追加</button></div><datalist id="editCompanionOptions">${activeCustomers().filter(c=>c.id!==s.customer_id).map(c=>`<option value="${esc(c.name)}">`).join("")}</datalist><div class="hint">未登録の名前は保存時に顧客へ登録されます。</div>`:""}</div>`;
  $("saleEditBody").innerHTML=`<div class="card">${linkNote}<div class="permission-note" style="margin-bottom:12px">入力者: ${esc(creator)}${s.is_settled?" ・ 精算済み":""}${editable?"":" ・ 閲覧のみ"}</div><div class="field"><label>営業日</label><input type="date" id="editSaleDate" value="${s.business_date}" ${editable?"":"disabled"}></div><div class="field"><label>合計金額</label><input type="number" id="editSaleTotal" value="${s.total_amount}" ${editable?"":"disabled"}></div><div class="field"><label>出前・タバコ等</label><input type="number" id="editSaleExtras" value="${s.delivery_tobacco_amount||0}" ${editable?"":"disabled"}></div><div class="field"><label>会計状態</label><select id="editSaleStatus" ${editable&&s.payment_status!=="未収"?"":"disabled"}><option ${s.payment_status==="未収"?"selected":""}>未収</option><option ${s.payment_status==="回収済み"?"selected":""}>回収済み</option></select></div><div class="field ${s.payment_status==="未収"?"hidden":""}" id="editSaleMethodField"><label>支払方法</label><select id="editSaleMethod" ${editable?"":"disabled"}><option value="">選択してください</option><option ${s.payment_method==="現金"?"selected":""}>現金</option><option ${s.payment_method==="カード"?"selected":""}>カード</option></select></div>${companionSection}<div class="field"><label>備考</label><textarea id="editSaleNotes" ${editable?"":"disabled"}>${esc(s.notes||"")}</textarea></div>${editable?'<button class="primary" id="saveSaleEdit">保存</button><button class="secondary danger" id="deleteSaleBtn" style="margin-top:10px">この会計を完全に削除</button>':""}</div>${s.payment_status==="未収"&&!incoming?`<div class="card recovery-card"><div class="section-title">未収を回収する</div><div class="field"><label>回収した営業日</label><input type="date" id="recoveryBusinessDate" value="${businessDateString()}"></div><div class="field"><label>実際に受け取った金額</label><input type="number" id="recoveryAmount" value="${s.total_amount}" min="1"><div class="hint">端数調整後の、実際に受け取った金額を入力します。</div></div><div class="field"><label>支払方法</label><select id="recoveryMethod"><option value="">選択してください</option><option>現金</option><option>カード</option></select></div><button class="primary" id="collectReceivableBtn">この日の売上として回収登録</button></div>`:""}`;
  const editNames=[...companionNames];const drawCompanions=()=>{const box=$("editCompanionList");if(!box)return;box.innerHTML=editNames.length?editNames.map((name,index)=>`<span class="edit-companion-chip">${esc(name)}${editable?`<button type="button" data-remove-edit-companion="${index}" aria-label="削除">×</button>`:""}</span>`).join(""):'<span class="hint">同伴者なし</span>';box.querySelectorAll("[data-remove-edit-companion]").forEach(button=>button.onclick=()=>{editNames.splice(Number(button.dataset.removeEditCompanion),1);drawCompanions()})};drawCompanions();
  if($("addEditCompanion"))$("addEditCompanion").onclick=()=>{const name=$("editCompanionInput").value.trim();if(name&&!editNames.some(x=>normalizeText(x)===normalizeText(name))){editNames.push(name);$("editCompanionInput").value="";drawCompanions()}};
  if($("saveSaleEdit"))$("saveSaleEdit").onclick=async()=>{const status=$("editSaleStatus").value,method=status==="未収"?null:$("editSaleMethod").value;if(status==="回収済み"&&!method)return showStatus("支払方法を選択してください","error");try{const p={business_date:$("editSaleDate").value,total_amount:Number($("editSaleTotal").value),delivery_tobacco_amount:Number($("editSaleExtras").value||0),payment_status:status,payment_method:method,notes:$("editSaleNotes").value.trim()||null};if(status==="未収"){p.is_settled=false;p.settled_at=null;p.settlement_id=null}const updated=await db.from("sales").update(p).eq("id",s.id);if(updated.error)throw updated.error;const companionIds=await resolveEditedCompanions(s.customer_id,editNames);const replaced=await db.rpc("replace_sale_companions",{target_store_id:storeId,target_sale_id:s.id,target_customer_ids:companionIds});if(replaced.error)throw replaced.error;closeModal("saleEditModal");await loadAll();if(currentSalesDate)renderSalesDay(currentSalesDate);showStatus("会計と同伴者を更新しました","success")}catch(error){showStatus(error.message||"売上を更新できませんでした","error")}};
  if($("deleteSaleBtn"))$("deleteSaleBtn").onclick=async()=>{if(!(await appConfirm(outgoing.length?"この会計を削除し、紐付けた過去の未収を未収状態へ戻しますか？":"この会計を完全に削除しますか？")))return;const deleted=await db.rpc("delete_sale_with_receivable_restore",{target_store_id:storeId,target_sale_id:s.id});if(deleted.error)return showStatus(deleted.error.message||"売上を削除できませんでした","error");closeModal("saleEditModal");await loadAll();if(currentSalesDate)renderSalesDay(currentSalesDate);showStatus(outgoing.length?"会計を削除し、過去の未収を元に戻しました":"売上を削除しました","success")};
  if($("collectReceivableBtn"))$("collectReceivableBtn").onclick=async()=>{const date=$("recoveryBusinessDate").value,amount=Number($("recoveryAmount").value),method=$("recoveryMethod").value;if(!date||amount<=0||!method)return showStatus("回収日・金額・支払方法を入力してください","error");const button=$("collectReceivableBtn");button.disabled=true;const collected=await db.rpc("collect_receivable_payment",{target_store_id:storeId,target_receivable_sale_id:s.id,target_business_date:date,target_received_amount:amount,target_payment_method:method});if(collected.error){button.disabled=false;return showStatus(collected.error.message||"未収を回収登録できませんでした","error")}closeModal("saleEditModal");await loadAll();showStatus(`${date}の売上として${yen(amount)}を回収登録しました。`,"success")}
};

customerIdsForVisitDate=function(date){if(!date)return null;const daySales=sales.filter(s=>s.business_date===date&&s.record_type!=="receivable_payment"),saleIds=new Set(daySales.map(s=>s.id)),ids=new Set(daySales.map(s=>s.customer_id).filter(Boolean));saleCompanions.filter(row=>saleIds.has(row.sale_id)).forEach(row=>ids.add(row.customer_id));return ids};
