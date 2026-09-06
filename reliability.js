// Shared data-reliability controls for every store.
let pendingSaleRequestId=null;

document.head.insertAdjacentHTML("beforeend",`<style>
.integrity-card{border-color:#c8d2df}.integrity-result{margin-top:10px;padding:11px;border-radius:10px;background:#f3f6f9;font-size:13px}.integrity-result.ok{background:#edf7f1;color:#235c3b}.integrity-result.error{background:#fff0ee;color:#9e2f28}
.audit-list{display:grid;gap:8px}.audit-row{padding:10px;border-radius:10px;background:#f3f5f7}.audit-row strong{display:block}.audit-row small{display:block;color:#667085;margin-top:3px}.settled-lock-note{margin:0 0 12px;padding:11px;border-radius:10px;background:#eef3f8;color:#30445d;font-size:13px;font-weight:700}
</style>`);

canEditSale=function(sale){return Boolean(sale&&!sale.is_settled&&(isOwnerOrManager()||sale.created_by===currentAuthUser?.id))};

function reliabilityRequestId(){if(!pendingSaleRequestId)pendingSaleRequestId=crypto.randomUUID();return pendingSaleRequestId}
function reliabilityErrorMessage(error){const message=String(error?.message||error||"");if(message.includes("精算済み"))return message;if(message.includes("mismatch"))return"店舗と入力データの組み合わせを確認してください。";if(message.includes("Invalid payment"))return"会計状態と支払方法を確認してください。";if(message.includes("Request ID"))return"登録識別番号を作成できませんでした。もう一度お試しください。";return message||"売上を保存できませんでした。"}

$("saveBtn").onclick=async function(){
  if(currentStoreMember?.role==="staff"&&!currentStoreMember.employee_id)return showStatus("口座との紐付けが未設定です。オーナーに設定を依頼してください。","error");
  if(!validateSaleWithBrands())return showStatus("入力内容を確認してください","error");
  const receivableIds=[...selectedReceivableIds];if(receivableIds.length&&(selectedPaymentStatus!=="回収済み"||!selectedPaymentMethod))return showStatus("未収を含める場合は、回収済みと支払方法を選択してください。","error");
  const customerId=$("customerId").value,customer=customers.find(item=>item.id===customerId),amount=Number($("totalAmount").value),method=selectedPaymentMethod,status=selectedPaymentStatus,brandValue=$("newBottleBrandSelect").value,emptiedBottleIds=Object.entries(existingBottleStates).filter(([,state])=>state==="空いた").map(([id])=>id),button=$("saveBtn");
  let pendingBottle=null;
  if(brandValue==="__custom__")pendingBottle={brand_id:null,name:$("directBottleName").value.trim(),bottle_number:$("directBottleNumber").value.trim()||null};
  else if(brandValue){const brand=bottleBrands.find(item=>item.id===brandValue);if(!brand)return showStatus("選択した銘柄が見つかりません","error");pendingBottle={brand_id:brand.id,name:brand.name,bottle_number:$("masterBottleNumber").value.trim()||null}}
  button.disabled=true;button.textContent="安全に保存中…";
  try{
    if(pendingBottle&&!pendingBottle.brand_id){const brand=await ensureBottleBrand(pendingBottle.name);pendingBottle.brand_id=brand.id;pendingBottle.name=brand.name}
    const companionIds=await resolveCompanionIds(),requestId=reliabilityRequestId();
    const result=await db.rpc("create_reliable_sale",{
      target_store_id:storeId,target_request_id:requestId,target_business_date:$("businessDate").value,target_customer_id:customerId,target_employee_id:$("employeeSelect").value,
      target_payment_status:status,target_payment_method:method,target_party_size:Number($("partySize").value),target_total_amount:amount,target_extras_amount:Number($("extraAmount").value||0),
      target_bottle_id:pendingBottle?null:($("bottleSelect").value||null),target_notes:$("notes").value.trim()||null,target_companion_ids:companionIds,
      target_new_bottle_brand_id:pendingBottle?.brand_id||null,target_new_bottle_name:pendingBottle?.name||null,target_new_bottle_number:pendingBottle?.bottle_number||null,
      target_emptied_bottle_ids:emptiedBottleIds,target_receivable_sale_ids:receivableIds
    });
    if(result.error)throw result.error;const duplicate=Boolean(result.data?.duplicate),count=receivableIds.length;pendingSaleRequestId=null;resetInputImproved();await loadAll();showSaleSuccess(customer,amount,method,brandValue==="__custom__");showStatus(duplicate?"同じ売上は既に保存済みです。二重登録はしていません。":count?`売上と未収${count}件を安全に一括保存しました。`:"売上を安全に保存しました。","success")
  }catch(error){showStatus(`${reliabilityErrorMessage(error)} 入力内容は画面に残しています。`,"error")}
  finally{button.disabled=currentStoreMember?.role==="staff"&&!currentStoreMember.employee_id;button.textContent="売上を登録する"}
};

const resetInputBeforeReliability=resetInputImproved;
resetInputImproved=function(){pendingSaleRequestId=null;resetInputBeforeReliability()};

function auditActionLabel(action){return action==="created"?"登録":action==="updated"?"更新":action==="deleted"?"削除":"履歴記録開始時点"}
async function renderSaleAudit(saleId){
  if(!isOwnerOrManager())return;const body=$("saleEditBody");if(!body)return;
  const placeholder=document.createElement("div");placeholder.className="card";placeholder.innerHTML='<div class="section-title">変更履歴</div><div class="empty">読み込み中...</div>';body.appendChild(placeholder);
  const result=await db.from("sale_audit_log").select("id,action,before_data,after_data,changed_by,changed_at").eq("store_id",storeId).eq("sale_id",saleId).order("changed_at",{ascending:false}).limit(30);
  if(!placeholder.isConnected)return;if(result.error){placeholder.innerHTML='<div class="section-title">変更履歴</div><div class="empty">履歴を読み込めませんでした</div>';return}
  const rows=result.data||[];placeholder.innerHTML=`<div class="section-title">変更履歴</div><div class="audit-list">${rows.length?rows.map(row=>{const before=row.before_data||{},after=row.after_data||{},changes=[];if(row.action==="updated"){if(before.total_amount!==after.total_amount)changes.push(`金額 ${yen(before.total_amount)} → ${yen(after.total_amount)}`);if(before.business_date!==after.business_date)changes.push(`営業日 ${esc(before.business_date)} → ${esc(after.business_date)}`);if(before.payment_status!==after.payment_status)changes.push(`状態 ${esc(before.payment_status)} → ${esc(after.payment_status)}`);if(before.payment_method!==after.payment_method)changes.push(`支払方法 ${esc(before.payment_method||"なし")} → ${esc(after.payment_method||"なし")}`);if(before.is_settled!==after.is_settled)changes.push(after.is_settled?"精算済みに変更":"未精算に変更")}const when=new Date(row.changed_at).toLocaleString("ja-JP",{year:"numeric",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});return`<div class="audit-row"><strong>${auditActionLabel(row.action)}</strong><small>${when} ・ ${esc(memberLabel(row.changed_by))}</small>${changes.length?`<small>${changes.join(" / ")}</small>`:""}</div>`}).join(""):'<div class="empty">変更履歴なし</div>'}</div>`
}

const openSaleEditorBeforeReliability=openSaleEditor;
openSaleEditor=function(id){openSaleEditorBeforeReliability(id);const sale=sales.find(item=>item.id===id),body=$("saleEditBody");if(sale?.is_settled&&body){const note=document.createElement("div");note.className="settled-lock-note";note.textContent="精算済みのため、会計内容はロックされています。変更履歴は下で確認できます。";body.prepend(note)}renderSaleAudit(id)};

function renderIntegrityCard(){
  let card=$("dataIntegrityCard");if(!isOwnerOrManager()){card?.remove();return}if(!card){card=document.createElement("div");card.id="dataIntegrityCard";card.className="card integrity-card";$("page-settings").appendChild(card)}
  card.innerHTML='<div class="section-title">データの信頼性</div><div class="permission-note">売上・精算・未収の紐付けに矛盾がないか、店舗単位で確認します。</div><button type="button" class="secondary" id="runIntegrityCheck" style="margin-top:10px">データ整合性を確認</button><div id="integrityResult"></div>';
  $("runIntegrityCheck").onclick=async()=>{const button=$("runIntegrityCheck"),box=$("integrityResult");button.disabled=true;button.textContent="確認中…";const result=await db.rpc("check_store_data_integrity",{target_store_id:storeId});button.disabled=false;button.textContent="データ整合性を確認";if(result.error){box.innerHTML=`<div class="integrity-result error">確認できませんでした：${esc(result.error.message)}</div>`;return}const count=Number(result.data?.issue_count||0),when=new Date(result.data?.checked_at||Date.now()).toLocaleString("ja-JP");box.innerHTML=`<div class="integrity-result ${count?"error":"ok"}">${count?`要確認のデータが ${count}件あります。`:'✓ 売上・精算・未収の整合性に問題はありません。'}<br><small>${esc(when)}確認</small></div>`}
}
const renderSettingsBeforeReliability=renderSettings;
renderSettings=function(){renderSettingsBeforeReliability();renderIntegrityCard()};
