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
  $("runIntegrityCheck").onclick=async()=>{const button=$("runIntegrityCheck"),box=$("integrityResult");button.disabled=true;button.textContent="確認中…";const result=await db.rpc("check_store_data_integrity",{target_store_id:storeId});button.disabled=false;button.textContent="データ整合性を確認";if(result.error){box.innerHTML=`<div class="integrity-result error">${esc(friendlyErrorMessage(result.error,"データの整合性を確認できませんでした。もう一度お試しください。"))}</div>`;return}const count=Number(result.data?.issue_count||0),when=new Date(result.data?.checked_at||Date.now()).toLocaleString("ja-JP");box.innerHTML=`<div class="integrity-result ${count?"error":"ok"}">${count?`要確認のデータが ${count}件あります。`:'✓ 売上・精算・未収の整合性に問題はありません。'}<br><small>${esc(when)}確認</small></div>`}
}
const renderSettingsBeforeReliability=renderSettings;
renderSettings=function(){renderSettingsBeforeReliability();renderIntegrityCard()};

document.head.insertAdjacentHTML("beforeend",`<style>
.data-safety-actions{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:11px}.operation-log{display:grid;gap:7px;margin-top:11px}.operation-row{padding:10px 11px;border:1px solid #e4e8ed;border-radius:10px;background:#fafbfc}.operation-row-head{display:flex;justify-content:space-between;gap:8px}.operation-row strong{font-size:12px}.operation-row small{display:block;margin-top:3px;color:#667085;font-size:10px}.backup-note{margin-top:8px;color:#667085;font-size:11px;line-height:1.55}@media(max-width:430px){.data-safety-actions{grid-template-columns:1fr}}
</style>`);

const auditedEntityLabels={customers:"顧客",employees:"口座",bottles:"ボトル",schedules:"予定",expenses:"経費",daily_settlements:"日別精算"};
const auditedActionLabels={created:"登録",updated:"変更",deleted:"削除"};
async function pagedStoreBackupRows(table){let rows=[];for(let from=0;;from+=1000){const result=await db.from(table).select("*").eq("store_id",storeId).range(from,from+999);if(result.error)throw result.error;rows.push(...(result.data||[]));if(!result.data||result.data.length<1000)break}return rows}
async function downloadStoreBackup(){
  if(!isOwner())return showStatus("店舗データのバックアップはオーナーのみ利用できます。","error");
  const button=$("downloadStoreBackup");button.disabled=true;button.textContent="バックアップ作成中…";
  try{
    const tables=["customers","employees","bottles","bottle_brands","sales","sale_companions","daily_settlements","schedules","expenses","cash_registers","cash_register_history","monthly_sales_goals","event_sales_goals","business_day_overrides","business_day_closures","sales_goal_settings"];
    const entries=await Promise.all(tables.map(async table=>[table,await pagedStoreBackupRows(table)]));
    const payload={format:"vexqia-store-backup",version:1,store:{id:storeId,name:storeName},exported_at:new Date().toISOString(),exported_by:currentAuthUser?.id||null,data:Object.fromEntries(entries),note:"領収書画像本体は含まず、画像への参照情報を保存しています。"};
    const blob=new Blob([JSON.stringify(payload,null,2)],{type:"application/json;charset=utf-8"}),url=URL.createObjectURL(blob),link=document.createElement("a"),stamp=dateString();link.href=url;link.download=`VEXQIA_${String(storeName||"store").replace(/[\\/:*?\"<>|]/g,"_")}_${stamp}.json`;document.body.appendChild(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);showStatus("店舗データのバックアップを保存しました。","success")
  }catch(error){showStatus(friendlyErrorMessage(error,"バックアップを作成できませんでした。"),"error")}
  finally{button.disabled=false;button.textContent="店舗データをバックアップ"}
}
async function loadOperationHistory(){
  const box=$("operationHistory");if(!box)return;box.innerHTML='<div class="empty">読み込み中...</div>';
  const result=await db.from("operation_audit_log").select("id,entity_type,entity_id,action,changed_by,changed_at").eq("store_id",storeId).order("changed_at",{ascending:false}).limit(50);
  if(result.error){box.innerHTML=`<div class="empty">${esc(friendlyErrorMessage(result.error,"操作履歴を読み込めませんでした。"))}</div>`;return}
  const rows=result.data||[];box.innerHTML=rows.length?`<div class="operation-log">${rows.map(row=>{const when=new Date(row.changed_at).toLocaleString("ja-JP",{month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit"});return`<div class="operation-row"><div class="operation-row-head"><strong>${esc(auditedEntityLabels[row.entity_type]||row.entity_type)}を${esc(auditedActionLabels[row.action]||row.action)}</strong><span class="badge">${esc(memberLabel(row.changed_by))}</span></div><small>${esc(when)}</small></div>`}).join("")}</div>`:'<div class="empty">記録開始後の操作はまだありません</div>'
}
function renderDataSafetyCard(){
  let card=$("dataSafetyCard");if(!isOwnerOrManager()){card?.remove();return}if(!card){card=document.createElement("div");card.id="dataSafetyCard";card.className="card";$("page-settings").appendChild(card)}
  card.innerHTML=`<div class="section-title">バックアップと操作履歴</div><div class="permission-note">顧客・口座・ボトル・予定・経費・日別精算の変更者と日時を記録します。</div><div class="data-safety-actions">${isOwner()?'<button type="button" class="secondary" id="downloadStoreBackup">店舗データをバックアップ</button>':""}<button type="button" class="secondary" id="showOperationHistory">最近の操作を見る</button></div><div class="backup-note">バックアップは復旧用JSONです。端末外の安全な場所にも保管してください。領収書画像本体は別管理です。</div><div id="operationHistory"></div>`;
  if($("downloadStoreBackup"))$("downloadStoreBackup").onclick=downloadStoreBackup;$("showOperationHistory").onclick=loadOperationHistory
}
const renderSettingsBeforeDataSafety=renderSettings;
renderSettings=function(){renderSettingsBeforeDataSafety();renderDataSafetyCard()};
