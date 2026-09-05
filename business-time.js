function storeClockParts(now=new Date()){
  const parts=new Intl.DateTimeFormat("en-CA",{timeZone:businessTimezone||"Asia/Tokyo",year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",hourCycle:"h23"}).formatToParts(now);
  return Object.fromEntries(parts.filter(part=>part.type!=="literal").map(part=>[part.type,part.value]));
}
function shiftDateKey(key,days){const [year,month,day]=key.split("-").map(Number),date=new Date(Date.UTC(year,month-1,day));date.setUTCDate(date.getUTCDate()+days);return `${date.getUTCFullYear()}-${String(date.getUTCMonth()+1).padStart(2,"0")}-${String(date.getUTCDate()).padStart(2,"0")}`}
function calendarDateString(now=new Date()){const part=storeClockParts(now);return `${part.year}-${part.month}-${part.day}`}
function businessDateString(now=new Date()){const part=storeClockParts(now),calendar=`${part.year}-${part.month}-${part.day}`;return Number(part.hour)<Number(businessDayCutoffHour||7)?shiftDateKey(calendar,-1):calendar}
function isConfiguredOpenDate(key){const override=overrideFor(key);if(override)return Boolean(override.is_open);if(eventGoalForDate(key))return true;const plan=goalPlanForMonth(key.slice(0,7)),day=parseDateLocal(key).getDay();return Boolean(plan.open_weekdays?.includes(day))}
function latestCompletedBusinessDate(now=new Date()){let key=shiftDateKey(calendarDateString(now),-1);for(let count=0;count<31;count+=1){if(isConfiguredOpenDate(key))return key;key=shiftDateKey(key,-1)}return shiftDateKey(calendarDateString(now),-1)}

(() => {
  let initializedStoreId=null;
  const settingsPage=$("page-settings"),storeInfo=settingsPage?.querySelector(".card");
  if(settingsPage&&storeInfo){
    const card=document.createElement("div");card.id="businessClockSettings";card.className="card hidden";card.setAttribute("data-manager-only","");
    card.innerHTML='<div class="section-title">営業日の切替</div><div class="field"><label>営業日の切替時刻</label><select id="businessCutoffHour"></select></div><button class="secondary" id="saveBusinessCutoff">切替時刻を保存</button><div class="hint" id="businessCutoffHint"></div>';
    storeInfo.insertAdjacentElement("afterend",card);
    $("businessCutoffHour").innerHTML=Array.from({length:13},(_,hour)=>`<option value="${hour}">${String(hour).padStart(2,"0")}:00</option>`).join("");
    $("saveBusinessCutoff").onclick=async()=>{const hour=Number($("businessCutoffHour").value),button=$("saveBusinessCutoff");button.disabled=true;const{data,error}=await db.rpc("update_store_business_clock",{target_store_id:storeId,target_cutoff_hour:hour});button.disabled=false;if(error)return showStatus(error.message||"切替時刻を保存できませんでした","error");businessDayCutoffHour=Number(data?.business_day_cutoff_hour??hour);renderSettings();refreshBusinessDateDefaults(true);showStatus(`営業日の切替を${String(hour).padStart(2,"0")}:00に設定しました`,"success")};
  }

  function refreshBusinessDateDefaults(force=false){
    const today=businessDateString(),completed=latestCompletedBusinessDate();
    if(force||initializedStoreId!==storeId){
      initializedStoreId=storeId;selectedCalendarDate=today;currentCalendarDate=parseDateLocal(today);salesListMonth=today.slice(0,7);
      if($("businessDate"))$("businessDate").value=completed;
      if($("analyticsStartDate"))$("analyticsStartDate").value="";
      if($("analyticsEndDate"))$("analyticsEndDate").value="";
    }
  }

  const loadAllBeforeBusinessClock=loadAll;
  loadAll=async function(){await loadAllBeforeBusinessClock();refreshBusinessDateDefaults();if(currentPage==="home")renderHome();if(currentPage==="schedule")renderSchedules();if(currentPage==="sales-list")renderSalesList();if(currentPage==="analytics")renderAnalytics()};

  const renderSettingsBeforeBusinessClock=renderSettings;
  renderSettings=function(){renderSettingsBeforeBusinessClock();if($("businessCutoffHour"))$("businessCutoffHour").value=String(businessDayCutoffHour||7);if($("businessCutoffHint"))$("businessCutoffHint").textContent=`${String(businessDayCutoffHour||7).padStart(2,"0")}:00までは前日の営業日として表示します。登録・更新時刻は実時刻のまま残ります。`};

  const resetInputBeforeBusinessClock=resetInputImproved;
  resetInputImproved=function(){resetInputBeforeBusinessClock();$("businessDate").value=latestCompletedBusinessDate()};

  renderGoalSection=function(targetId="goalSection"){
    const today=businessDateString(),n=parseDateLocal(today),y=n.getFullYear(),m=n.getMonth(),mg=monthGoal(y,m),actual=settledNetForMonth(y,m),monthRemaining=Math.max(0,mg-actual),current=currentGoalDifference(y,m),todayActual=totalSales(recoveredSales(sales.filter(s=>s.business_date===today))),rawPct=mg?Math.max(0,actual/mg*100):0,pct=Math.min(100,rawPct),box=$(targetId);if(!box)return;
    const diffMarkup=value=>`<b class="${value>0?"positive":value<0?"negative":""}">${value>=0?"+":""}${signedYen(value)}</b>`;
    box.innerHTML=`<div class="home-goal-card"><div class="home-goal-head"><div class="home-goal-month">${y}年${m+1}月</div>${isOwnerOrManager()?'<button class="small-btn" data-open-goal-settings>設定</button>':""}</div><div class="home-goal-main"><span>月間目標</span><strong>${mg?yen(mg):"未設定"}</strong></div><div class="home-goal-today"><span>本日の売上</span><b>${yen(todayActual)}</b></div><div class="home-goal-stats"><div class="home-goal-stat"><span>現在の実績</span><b>${yen(actual)}</b></div><div class="home-goal-stat"><span>月間目標まで</span>${mg?`<b>${yen(monthRemaining)}</b>`:"<b>－</b>"}</div><div class="home-goal-stat" title="精算済みの日まで"><span>現在差額</span>${current.closedCount?diffMarkup(current.difference):"<b>－</b>"}</div></div><div class="home-goal-progress-label"><span>月間目標の達成率</span><b>${mg?rawPct.toFixed(1)+"%":"未設定"}</b></div><div class="home-goal-progress" aria-label="達成率 ${mg?rawPct.toFixed(1)+"%":"未設定"}"><div style="width:${pct}%"></div></div></div>`;
    box.querySelector("[data-open-goal-settings]")?.addEventListener("click",openGoalModal);
  };

  renderRoleHome=function(){const box=$("roleHomeSummary");if(!box)return;const today=businessDateString(),todaySchedules=schedules.filter(schedule=>schedule.schedule_date===today&&schedule.status!=="キャンセル").sort((a,b)=>String(a.schedule_time||"99:99").localeCompare(String(b.schedule_time||"99:99"))),target=configuredDailyTarget(today),targetText=target.label==="休業"?"休業":target.amount?yen(target.amount):"未設定";box.innerHTML=`<div class="home-today-card"><div class="home-today-grid"><div class="home-today-stat"><span>本日の予定</span><b>${todaySchedules.length}件</b></div><div class="home-today-stat"><span>本日の目標金額</span><b>${targetText}</b></div></div>${todaySchedules.length?`<div class="home-schedule-preview">${todaySchedules.slice(0,3).map(schedule=>`<button class="home-schedule-item" data-home-schedule><span>${esc(schedule.title)}</span><small>${schedule.schedule_time?esc(schedule.schedule_time.slice(0,5)):"時間未定"}</small></button>`).join("")}${todaySchedules.length>3?`<button class="home-schedule-more" data-home-schedule>ほか${todaySchedules.length-3}件を見る</button>`:""}</div>`:""}</div>`;box.querySelectorAll("[data-home-schedule]").forEach(button=>button.onclick=()=>goToPage("schedule","カレンダー"))};

  const renderCalendarBeforeBusinessClock=renderCalendar;
  renderCalendar=function(){renderCalendarBeforeBusinessClock();const today=businessDateString();$("calendarGrid")?.querySelectorAll("[data-calendar-date]").forEach(day=>day.classList.toggle("today",day.dataset.calendarDate===today))};
  renderTodayReservations=function(){const today=businessDateString(),rows=schedules.filter(s=>s.schedule_date===today&&s.schedule_type==="予約"&&s.status!=="キャンセル");$("todayReservations").innerHTML=rows.length?rows.map(s=>`<div class="today-reservation"><span class="badge reservation">予約</span> ${s.schedule_time?s.schedule_time.slice(0,5):""}<br><strong>${esc(s.title)}</strong><div class="item-sub">担当: ${esc(scheduleEmployeeLabel(s.employee_id))}${s.party_size?` ・ ${Number(s.party_size)}名`:""}</div></div>`).join(""):'<div class="empty">本日の予約はありません</div>'};
  $("newScheduleBtn").onclick=()=>openScheduleModal(businessDateString());
  $("addSelectedDateScheduleBtn").onclick=()=>openScheduleModal(selectedCalendarDate||businessDateString());

  const openGoalModalBeforeBusinessClock=openGoalModal;
  openGoalModal=function(){openGoalModalBeforeBusinessClock();const month=businessDateString().slice(0,7);if($("monthlyGoalMonth").value!==month){$("monthlyGoalMonth").value=month;populateGoalPlan()}$("overrideDate").value=businessDateString()};
  const resetEventGoalFormBeforeBusinessClock=resetEventGoalForm;
  resetEventGoalForm=function(){resetEventGoalFormBeforeBusinessClock();const month=selectedGoalMonth(),today=businessDateString(),base=month===today.slice(0,7)?today:`${month}-01`;$("eventGoalStart").value=base;$("eventGoalEnd").value=base};

  analyticsDateRange=function(){const today=businessDateString(),now=parseDateLocal(today),defaultStart=dateString(new Date(now.getFullYear(),now.getMonth(),1)),start=$("analyticsStartDate").value||defaultStart,end=$("analyticsEndDate").value||today;if(!$("analyticsStartDate").value)$("analyticsStartDate").value=start;if(!$("analyticsEndDate").value)$("analyticsEndDate").value=end;return start<=end?{start,end}:{start:end,end:start}};
  setAnalyticsPreset=function(preset){const now=parseDateLocal(businessDateString()),start=new Date(now),end=new Date(now);if(preset==="week"){const day=(now.getDay()+6)%7;start.setDate(now.getDate()-day)}else if(preset==="month")start.setDate(1);else if(preset==="last-month"){start.setMonth(now.getMonth()-1,1);end.setDate(0)}$("analyticsStartDate").value=dateString(start);$("analyticsEndDate").value=dateString(end);document.querySelectorAll("[data-analytics-preset]").forEach(button=>button.classList.toggle("active",button.dataset.analyticsPreset===preset));renderAnalytics()};

  monthDayData=function(){const now=parseDateLocal(businessDateString()),days=new Date(now.getFullYear(),now.getMonth()+1,0).getDate(),prefix=dateString(now).slice(0,7);return Array.from({length:days},(_,index)=>{const day=String(index+1).padStart(2,"0"),rows=sales.filter(s=>s.business_date===`${prefix}-${day}`);return{label:`${index+1}日`,value:settledActualForRows(rows)}})};
  renderSalesDates=function(){const defaultDate=latestCompletedBusinessDate(),dates=Array.from(new Set([...sales.map(s=>s.business_date),...businessDayClosures.map(row=>row.business_date),defaultDate])).sort().reverse();$("salesDateList").innerHTML=dates.map(date=>{const rows=sales.filter(s=>s.business_date===date),rec=recoveredSales(rows),pending=rec.filter(s=>!s.is_settled),un=rows.filter(s=>s.payment_status==="未収"),closed=businessDayClosures.some(row=>row.business_date===date)&&!pending.length;return `<div class="item clickable" data-sales-date="${date}"><div class="item-top"><div><div class="item-title">${date}</div><div class="item-sub">${rows.length}件 ${pending.length?`<span class="badge pending">未精算 ${pending.length}件</span>`:closed?'<span class="badge settled">精算済み</span>':'<span class="badge pending">未精算</span>'} ${un.length?`<span class="badge unpaid">未収 ${un.length}件</span>`:""}</div></div><div class="item-amount">${yen(settledActualForRows(rows))}</div></div></div>`}).join("");$("salesDateList").querySelectorAll("[data-sales-date]").forEach(row=>row.onclick=()=>renderSalesDay(row.dataset.salesDate))};
})();
