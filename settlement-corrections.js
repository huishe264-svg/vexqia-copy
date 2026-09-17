// Safe correction flow for settled sales, plus mobile pull-to-refresh.
document.head.insertAdjacentHTML("beforeend",`<style>
.pull-refresh-indicator{position:fixed;top:8px;left:50%;z-index:115;min-width:150px;padding:9px 14px;border:1px solid #d9dee6;border-radius:999px;background:rgba(255,255,255,.97);box-shadow:0 8px 24px rgba(19,34,56,.16);color:var(--navy);font-size:12px;font-weight:850;text-align:center;transform:translate(-50%,-70px);transition:transform .18s ease}.pull-refresh-indicator.show{transform:translate(-50%,0)}.settlement-correction-card{border-color:#dac79d}.settlement-correction-warning{margin-bottom:10px;padding:11px;border-radius:10px;background:#fff8e8;color:#665124;font-size:12px;line-height:1.6}
</style>`);

const canReopenSettledSale=()=>["owner","admin"].includes(displayRole())||(displayRole()==="manager"&&Boolean(storeOperatingSettings?.manager_settled_sale_edit));

const cashHistoryLabelBeforeSettlementCorrection=cashHistoryLabel;
cashHistoryLabel=function(action){return action==="settlement_reopen"?"精算取消":cashHistoryLabelBeforeSettlementCorrection(action)};

function renderSettlementEditPermission(){
  let card=$("settlementEditPermission");
  if(!isOwner()){card?.remove();return}
  if(!card){card=document.createElement("div");card.id="settlementEditPermission";card.className="card settlement-correction-card";const accountCard=$("settingsGoalBtn")?.closest(".card");(accountCard||$("settingsStoreName")?.closest(".card"))?.insertAdjacentElement("afterend",card)}
  const managerAllowed=Boolean(storeOperatingSettings?.manager_settled_sale_edit);
  card.innerHTML=`<div class="section-title">精算済み会計の訂正権限</div><div class="field"><label>精算を取り消して再編集できる権限</label><select id="settledSaleEditRole"><option value="owner" ${managerAllowed?"":"selected"}>オーナーのみ</option><option value="manager" ${managerAllowed?"selected":""}>店長まで</option></select></div><div class="permission-note" style="margin-bottom:10px">訂正時は同じ精算に含まれる会計を未精算へ戻し、レジ金へ逆仕訳を記録します。従業員には許可できません。</div><button type="button" class="secondary" id="saveSettledSaleEditPermission">権限を保存</button>`;
  $("saveSettledSaleEditPermission").onclick=async()=>{const button=$("saveSettledSaleEditPermission");button.disabled=true;const result=await db.rpc("set_settled_sale_edit_permission",{target_store_id:storeId,target_manager_allowed:$("settledSaleEditRole").value==="manager"});button.disabled=false;if(result.error)return showStatus(friendlyErrorMessage(result.error,"訂正権限を保存できませんでした。"),"error");storeOperatingSettings=result.data;renderSettlementEditPermission();showStatus("精算済み会計の訂正権限を保存しました。","success")}
}

const renderSettingsBeforeSettlementCorrection=renderSettings;
renderSettings=function(){renderSettingsBeforeSettlementCorrection();renderSettlementEditPermission()};

const openSaleEditorBeforeSettlementCorrection=openSaleEditor;
openSaleEditor=function(id){
  openSaleEditorBeforeSettlementCorrection(id);const sale=sales.find(item=>item.id===id),body=$("saleEditBody");
  if(!sale?.is_settled||!body)return;
  if(!canReopenSettledSale())return;
  const settlementCount=sales.filter(item=>item.settlement_id&&item.settlement_id===sale.settlement_id).length||1,card=document.createElement("div");card.className="card settlement-correction-card";card.innerHTML=`<div class="section-title">精算済み会計を訂正</div><div class="settlement-correction-warning">この会計を含む同じ精算の${settlementCount}件を未精算へ戻し、レジ金への反映を取り消してから編集します。履歴は消えません。</div><button type="button" class="secondary danger" id="reopenSettlementForSale">精算を取り消して編集</button>`;body.appendChild(card);
  $("reopenSettlementForSale").onclick=async()=>{if(!(await appConfirm(`同じ精算の${settlementCount}件を未精算に戻しますか？レジ金には取消履歴が残ります。`,"精算を取り消す")))return;const button=$("reopenSettlementForSale");button.disabled=true;button.textContent="精算を取り消しています…";const result=await db.rpc("reopen_settlement_for_sale",{target_store_id:storeId,target_sale_id:id});if(result.error){button.disabled=false;button.textContent="精算を取り消して編集";return showStatus(friendlyErrorMessage(result.error,"精算を取り消せませんでした。"),"error")}closeModal("saleEditModal");await loadAll();if(currentSalesDate)renderSalesDay(currentSalesDate);openSaleEditor(id);showStatus(`${Number(result.data?.affected_sales||settlementCount)}件を未精算へ戻しました。内容を編集してください。`,"success")}
};

(function setupPullToRefresh(){
  const indicator=document.createElement("div");indicator.id="pullRefreshIndicator";indicator.className="pull-refresh-indicator";indicator.textContent="↓ 引っ張って更新";document.body.appendChild(indicator);
  let startY=0,distance=0,tracking=false,refreshing=false;
  const blocked=target=>target?.closest?.("input,textarea,select,button,.modal.show");
  document.addEventListener("touchstart",event=>{if(refreshing||window.scrollY>0||blocked(event.target)||event.touches.length!==1)return;startY=event.touches[0].clientY;distance=0;tracking=true},{passive:true});
  document.addEventListener("touchmove",event=>{if(!tracking)return;distance=Math.max(0,event.touches[0].clientY-startY);if(distance>18){indicator.classList.add("show");indicator.textContent=distance>=75?"↑ 離して更新":"↓ 引っ張って更新"}},{passive:true});
  document.addEventListener("touchend",async()=>{if(!tracking)return;tracking=false;const shouldRefresh=distance>=75;distance=0;if(!shouldRefresh){indicator.classList.remove("show");return}refreshing=true;indicator.classList.add("show");indicator.textContent="更新中…";try{await loadAll();renderPage(currentPage);indicator.textContent="✓ 更新しました";setTimeout(()=>indicator.classList.remove("show"),650)}catch(error){indicator.textContent="更新できませんでした";showStatus(friendlyErrorMessage(error,"データを更新できませんでした。"),"error");setTimeout(()=>indicator.classList.remove("show"),1100)}finally{refreshing=false}}
  ,{passive:true});
})();
