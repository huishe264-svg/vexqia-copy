// Configurable operating profile. It is enabled only for the dedicated sales demo store.
let storeOperatingSettings=null;
const DEFAULT_OPERATING_SETTINGS={goal_mode:"daily_calculation",account_label:"口座",deduction_label:"出前・タバコ等",payment_methods:["現金","カード"],bottle_management_enabled:true,cash_register_enabled:true};
const demoSettingsEnabled=()=>Boolean(storeOperatingSettings?.demo_configuration_enabled);
const operatingValue=key=>demoSettingsEnabled()?(storeOperatingSettings[key]??DEFAULT_OPERATING_SETTINGS[key]):DEFAULT_OPERATING_SETTINGS[key];

document.head.insertAdjacentHTML("beforeend",`<style>
.demo-settings-card{border-color:#d8c08a}.demo-settings-badge{display:inline-flex;padding:3px 8px;margin-left:6px;border-radius:999px;background:#fff3d6;color:#70521d;font-size:11px;font-weight:800}
.settings-check-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.settings-check{display:flex;align-items:center;gap:9px;min-height:46px;padding:9px;border:1px solid #d9dee6;border-radius:10px}.settings-check input{width:21px;height:21px}
.feature-disabled{display:none!important}@media(max-width:520px){.settings-check-grid{grid-template-columns:1fr}}
</style>`);

function monthOpenDates(month){
  const [year,number]=month.split("-").map(Number),last=new Date(year,number,0).getDate(),plan=goalPlanForMonth(month),result=[];
  for(let day=1;day<=last;day++){const date=`${year}-${String(number).padStart(2,"0")}-${String(day).padStart(2,"0")}`,override=overrideFor(date),weekday=parseDateLocal(date).getDay();if(override?override.is_open:plan.open_weekdays?.includes(weekday))result.push(date)}
  return result
}

const configuredDailyTargetBeforeDemo=configuredDailyTarget;
configuredDailyTarget=function(date){
  if(!demoSettingsEnabled()||operatingValue("goal_mode")!=="monthly_direct")return configuredDailyTargetBeforeDemo(date);
  const month=date.slice(0,7),goal=monthGoal(Number(month.slice(0,4)),Number(month.slice(5,7))-1),openDates=monthOpenDates(month),override=overrideFor(date);
  if((override&&!override.is_open)||!openDates.includes(date))return{amount:0,label:"休業"};
  if(!goal)return{amount:0,label:"月間目標未設定"};
  const actual=settledNetForMonth(Number(month.slice(0,4)),Number(month.slice(5,7))-1),remainingDates=openDates.filter(item=>item>=date),needed=Math.max(0,goal-actual),amount=remainingDates.length?Math.ceil(needed/remainingDates.length/1000)*1000:needed;
  return{amount,label:"残り営業日あたり必要額"}
};

const accountBadgeBeforeDemo=accountBadge;
accountBadge=function(employee,emptyLabel){const label=operatingValue("account_label");return accountBadgeBeforeDemo(employee,emptyLabel).replaceAll("口座",esc(label))};
const saleCardBeforeDemoSettings=saleCard;
saleCard=function(s,showBusinessDate=false){return saleCardBeforeDemoSettings(s,showBusinessDate).replaceAll("口座 ",`${esc(operatingValue("account_label"))} `)};

function replaceTextIn(root,from,to){if(!root||from===to)return;const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);const nodes=[];while(walker.nextNode())nodes.push(walker.currentNode);nodes.forEach(node=>{if(node.parentElement?.matches("script,style,input,textarea"))return;node.nodeValue=node.nodeValue.replaceAll(from,to)})}

function bindDemoPaymentMethods(){
  const container=document.querySelector('[data-group="paymentMethod"]')?.parentElement;if(!container)return;
  const methods=operatingValue("payment_methods");if(!methods.includes(selectedPaymentMethod))selectedPaymentMethod="";
  container.innerHTML=methods.map(method=>`<button type="button" data-group="paymentMethod" data-value="${esc(method)}" class="${selectedPaymentMethod===method?"active":""}" aria-pressed="${selectedPaymentMethod===method}">${esc(method)}</button>`).join("");
  container.querySelectorAll("button").forEach(button=>button.onclick=()=>{container.querySelectorAll("button").forEach(item=>{item.classList.toggle("active",item===button);item.setAttribute("aria-pressed",String(item===button))});selectedPaymentMethod=button.dataset.value;updateSaleSubmitSummary();renderReceivableCombine()})
}

function applyDemoOperatingSettings(){
  const account=operatingValue("account_label"),deduction=operatingValue("deduction_label"),bottlesEnabled=operatingValue("bottle_management_enabled"),cashEnabled=operatingValue("cash_register_enabled");
  const employeeNav=document.querySelector('.drawer-link[data-page="employees"]');if(employeeNav){employeeNav.textContent=`${account}管理`;employeeNav.dataset.title=`${account}管理`}
  const employeeLabel=$("employeeSelect")?.closest(".field")?.querySelector("label");if(employeeLabel)employeeLabel.innerHTML=`${esc(account)} <span class="required" aria-label="必須">※</span>`;
  const extrasLabel=$("extraAmount")?.closest(".field")?.querySelector("label");if(extrasLabel)extrasLabel.innerHTML=`${esc(deduction)} <span class="required" aria-label="必須">※</span>`;
  document.querySelectorAll('.drawer-link[data-page="bottles"],.drawer-link[data-page="bottle-master"]').forEach(node=>node.classList.toggle("feature-disabled",!bottlesEnabled));
  $("saleDetails")?.classList.toggle("feature-disabled",!bottlesEnabled);if(!bottlesEnabled){$("bottleSelect").value="";$("newBottleBrandSelect").value=""}
  $("cashRegisterSection")?.querySelector(".cash-register-card")?.classList.toggle("feature-disabled",!cashEnabled);
  bindDemoPaymentMethods();
}

function renderDemoOperatingSettings(){
  let card=$("demoOperatingSettings");if(!demoSettingsEnabled()||!isOwnerOrManager()){card?.remove();return}
  if(!card){card=document.createElement("div");card.id="demoOperatingSettings";card.className="card demo-settings-card";const page=$("page-settings"),storeCard=$("settingsStoreName")?.closest(".card");storeCard?.insertAdjacentElement("afterend",card)}
  const month=dateString().slice(0,7),goal=monthlyGoals.find(item=>String(item.goal_month).slice(0,7)===month);
  card.innerHTML=`<div class="section-title">店舗運用設定 <span class="demo-settings-badge">営業デモ限定</span></div><div class="permission-note" style="margin-bottom:12px">導入先ごとの違いを設定で確認するためのデモ機能です。本来の店舗には表示・適用されません。</div><div class="field"><label>売上目標の決め方</label><select id="demoGoalMode"><option value="daily_calculation" ${operatingValue("goal_mode")==="daily_calculation"?"selected":""}>曜日・営業日から月間目標を算出</option><option value="monthly_direct" ${operatingValue("goal_mode")==="monthly_direct"?"selected":""}>月間総額を直接設定</option></select></div><div id="demoMonthlyDirect" class="${operatingValue("goal_mode")==="monthly_direct"?"":"hidden"}"><div class="row"><div class="field"><label>対象月</label><input type="month" id="demoDirectMonth" value="${month}"></div><div class="field"><label>月間目標</label><input type="number" id="demoDirectAmount" min="0" inputmode="numeric" value="${Number(goal?.target_amount||0)}"></div></div><div class="hint">ホームの本日の目標には、残り営業日あたりの必要額を自動表示します。</div><button type="button" class="secondary" id="saveDemoDirectGoal" style="margin-top:8px">月間目標を保存</button></div><div class="row" style="margin-top:12px"><div class="field"><label>担当者の呼び方</label><input id="demoAccountLabel" maxlength="12" value="${esc(operatingValue("account_label"))}" placeholder="例：口座、担当、キャスト"></div><div class="field"><label>売上控除項目の名称</label><input id="demoDeductionLabel" maxlength="30" value="${esc(operatingValue("deduction_label"))}" placeholder="例：出前・タバコ等"></div></div><div class="field"><label>使用する支払方法</label><div class="settings-check-grid">${["現金","カード"].map(method=>`<label class="settings-check"><input type="checkbox" data-demo-payment="${method}" ${operatingValue("payment_methods").includes(method)?"checked":""}>${method}</label>`).join("")}</div><div class="hint">振込・QR決済などの追加は、既存店舗へ影響しない専用設計を行ってから対応します。</div></div><div class="field"><label>使用する機能</label><div class="settings-check-grid"><label class="settings-check"><input type="checkbox" id="demoBottleEnabled" ${operatingValue("bottle_management_enabled")?"checked":""}>ボトル管理</label><label class="settings-check"><input type="checkbox" id="demoCashEnabled" ${operatingValue("cash_register_enabled")?"checked":""}>レジ金表示</label></div></div><button type="button" class="primary" id="saveDemoOperatingSettings">店舗運用設定を保存</button>`;
  $("demoGoalMode").onchange=()=>$("demoMonthlyDirect").classList.toggle("hidden",$("demoGoalMode").value!=="monthly_direct");
  $("demoDirectMonth").onchange=()=>{const selected=monthlyGoals.find(item=>String(item.goal_month).slice(0,7)===$("demoDirectMonth").value);$("demoDirectAmount").value=Number(selected?.target_amount||0)};
  $("saveDemoDirectGoal").onclick=async()=>{const month=$("demoDirectMonth").value,amount=Math.round(Number($("demoDirectAmount").value||0));if(!month||amount<=0)return showStatus("対象月と月間目標を入力してください","error");const existing=monthlyGoals.find(item=>String(item.goal_month).slice(0,7)===month),plan=goalPlanForMonth(month),result=await db.from("monthly_sales_goals").upsert({store_id:storeId,goal_month:`${month}-01`,target_amount:amount,weekday_goal:Number(existing?.weekday_goal??plan.weekday_goal??0),weekend_goal:Number(existing?.weekend_goal??plan.weekend_goal??0),open_weekdays:existing?.open_weekdays??plan.open_weekdays,updated_by:currentAuthUser.id,updated_at:new Date().toISOString()},{onConflict:"store_id,goal_month"});if(result.error)return showStatus(result.error.message||"月間目標を保存できませんでした","error");await loadAll();showStatus(`${month.replace("-","年")}月の目標を${yen(amount)}に設定しました`,"success")};
  $("saveDemoOperatingSettings").onclick=async()=>{const methods=[...card.querySelectorAll("[data-demo-payment]:checked")].map(input=>input.dataset.demoPayment),account=$("demoAccountLabel").value.trim(),deduction=$("demoDeductionLabel").value.trim();if(!account||!deduction||!methods.length)return showStatus("呼び方・控除項目名・支払方法を確認してください","error");const button=$("saveDemoOperatingSettings");button.disabled=true;const result=await db.from("store_operating_settings").upsert({store_id:storeId,demo_configuration_enabled:true,goal_mode:$("demoGoalMode").value,account_label:account,deduction_label:deduction,payment_methods:methods,bottle_management_enabled:$("demoBottleEnabled").checked,cash_register_enabled:$("demoCashEnabled").checked,updated_by:currentAuthUser.id,updated_at:new Date().toISOString()},{onConflict:"store_id"}).select("*").single();button.disabled=false;if(result.error)return showStatus(result.error.message||"店舗運用設定を保存できませんでした","error");storeOperatingSettings=result.data;renderDemoOperatingSettings();applyDemoOperatingSettings();renderHome();showStatus("営業デモ店舗の運用設定を保存しました","success")}
}

const renderSettingsBeforeDemo=renderSettings;
renderSettings=function(){renderSettingsBeforeDemo();renderDemoOperatingSettings();applyDemoOperatingSettings()};
const renderSalesDayBeforeDemoSettings=renderSalesDay;
renderSalesDay=function(date){renderSalesDayBeforeDemoSettings(date);if(demoSettingsEnabled())replaceTextIn($("salesDayDetail"),"出前・タバコ等",operatingValue("deduction_label"))};
const openSaleEditorBeforeDemoSettings=openSaleEditor;
openSaleEditor=function(id){openSaleEditorBeforeDemoSettings(id);if(!demoSettingsEnabled())return;const methods=operatingValue("payment_methods");for(const select of [$("editSaleMethod"),$("recoveryMethod")]){if(!select)continue;const current=select.value;select.innerHTML='<option value="">選択してください</option>'+methods.map(method=>`<option ${method===current?"selected":""}>${esc(method)}</option>`).join("")}replaceTextIn($("saleEditBody"),"出前・タバコ等",operatingValue("deduction_label"))};

const loadAllBeforeDemoSettings=loadAll;
loadAll=async function(){await loadAllBeforeDemoSettings();const result=await db.from("store_operating_settings").select("*").eq("store_id",storeId).maybeSingle();if(result.error)throw result.error;storeOperatingSettings=result.data||null;renderDemoOperatingSettings();applyDemoOperatingSettings();if(currentPage==="home")renderHome()};
