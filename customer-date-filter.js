(function setupCustomerVisitDatePicker(){
 const input=$('customerVisitDate'),clearButton=$('clearCustomerVisitDate');if(!input)return;
 input.classList.add('hidden');input.onchange=null;
 const openButton=document.createElement('button');openButton.type='button';openButton.id='openCustomerVisitDate';openButton.className='customer-date-button';
 input.insertAdjacentElement('beforebegin',openButton);
 const modal=document.createElement('div');modal.id='customerVisitDateModal';modal.className='modal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-labelledby','customerCalendarTitle');
 modal.innerHTML=`<div class="modal-card customer-calendar-card"><div class="modal-head"><h2 id="customerCalendarTitle">来店日を選択</h2><button type="button" class="close-btn" data-date-cancel aria-label="閉じる">×</button></div><div class="customer-calendar-nav"><button type="button" data-month-shift="-1" aria-label="前の月">‹</button><strong id="customerCalendarMonth"></strong><button type="button" data-month-shift="1" aria-label="次の月">›</button></div><div class="customer-calendar-week"><span>日</span><span>月</span><span>火</span><span>水</span><span>木</span><span>金</span><span>土</span></div><div id="customerCalendarDays" class="customer-calendar-days"></div><div class="customer-calendar-actions"><button type="button" class="secondary" data-date-cancel>キャンセル</button><button type="button" class="customer-calendar-confirm" id="confirmCustomerVisitDate" aria-label="選択した日付で検索">✓</button></div></div>`;
 document.body.appendChild(modal);
 let draftDate='',shownMonth='';
 const today=()=>dateString(new Date());
 function buttonLabel(){openButton.innerHTML=input.value?`<span>📅 来店日</span><strong>${input.value.replaceAll('-','/')}</strong>`:'<span>📅 来店日を選ぶ</span><strong>日付から顧客を検索</strong>';clearButton.classList.toggle('hidden',!input.value)}
 function monthLabel(month){const[y,m]=month.split('-');return`${y}年${Number(m)}月`}
 function shiftMonth(offset){const[y,m]=shownMonth.split('-').map(Number),next=new Date(y,m-1+offset,1);shownMonth=dateString(next).slice(0,7);renderCalendar()}
 function renderCalendar(){
  $('customerCalendarMonth').textContent=monthLabel(shownMonth);const[y,m]=shownMonth.split('-').map(Number),first=new Date(y,m-1,1).getDay(),last=new Date(y,m,0).getDate(),cells=[];
  for(let i=0;i<first;i++)cells.push('<span></span>');
  for(let day=1;day<=last;day++){const date=`${shownMonth}-${String(day).padStart(2,'0')}`,selected=date===draftDate,isToday=date===today();cells.push(`<button type="button" data-customer-calendar-date="${date}" class="${selected?'selected ':''}${isToday?'today':''}" aria-pressed="${selected}">${day}</button>`)}
  $('customerCalendarDays').innerHTML=cells.join('');
  $('customerCalendarDays').querySelectorAll('[data-customer-calendar-date]').forEach(button=>button.onclick=()=>{draftDate=button.dataset.customerCalendarDate;renderCalendar()});
  $('confirmCustomerVisitDate').disabled=!draftDate;
 }
 function openPicker(){draftDate=input.value||today();shownMonth=draftDate.slice(0,7);renderCalendar();openModal(modal.id)}
 function cancelPicker(){closeModal(modal.id)}
 function confirmPicker(){if(!draftDate)return;input.value=draftDate;closeModal(modal.id);buttonLabel();renderCustomerList()}
 openButton.onclick=openPicker;
 modal.querySelectorAll('[data-date-cancel]').forEach(button=>button.onclick=cancelPicker);
 modal.querySelectorAll('[data-month-shift]').forEach(button=>button.onclick=()=>shiftMonth(Number(button.dataset.monthShift)));
 modal.onclick=event=>{if(event.target===modal)cancelPicker()};
 modal.onkeydown=event=>{if(event.key==='Escape')cancelPicker()};
 $('confirmCustomerVisitDate').onclick=confirmPicker;
 clearButton.onclick=()=>{input.value='';buttonLabel();renderCustomerList()};
 buttonLabel();
 const style=document.createElement('style');style.textContent=`.customer-date-button{display:flex;flex:1;min-height:52px;padding:8px 12px;border:1px solid #cfd6df;border-radius:11px;background:#fff;color:#132238;text-align:left;flex-direction:column;justify-content:center}.customer-date-button span{font-size:13px;font-weight:850}.customer-date-button strong{margin-top:2px;color:#657084;font-size:11px}.customer-calendar-card{max-width:390px}.customer-calendar-nav{display:grid;grid-template-columns:48px 1fr 48px;align-items:center;margin-bottom:10px;text-align:center}.customer-calendar-nav button{height:44px;border:0;border-radius:10px;background:#f3f5f7;color:#132238;font-size:28px}.customer-calendar-week,.customer-calendar-days{display:grid;grid-template-columns:repeat(7,1fr);gap:4px}.customer-calendar-week span{padding:5px 0;text-align:center;color:#6b7280;font-size:12px}.customer-calendar-days button,.customer-calendar-days>span{aspect-ratio:1;border:0;border-radius:50%;background:transparent;color:#132238}.customer-calendar-days button.today{box-shadow:inset 0 0 0 1px #9aa5b5}.customer-calendar-days button.selected{background:#132238;color:#fff;box-shadow:none;font-weight:850}.customer-calendar-actions{display:grid;grid-template-columns:1fr 58px;gap:10px;margin-top:16px}.customer-calendar-confirm{min-height:48px;border:0;border-radius:12px;background:#1769e0;color:#fff;font-size:23px;font-weight:900}.customer-calendar-confirm:disabled{opacity:.4}`;document.head.appendChild(style);
 window.customerVisitDatePicker={openPicker,cancelPicker,confirmPicker};
})();
