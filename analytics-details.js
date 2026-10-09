// Detailed sales analysis built from the records already loaded by the app.
(function(){
 const style=document.createElement('style');
 style.textContent=`
  .analytics-detail-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin-bottom:12px}
  .analytics-detail-stat{padding:12px;border:1px solid var(--line);border-radius:13px;background:#fff}
  .analytics-detail-stat span{display:block;color:var(--muted);font-size:10px;font-weight:800}
  .analytics-detail-stat strong{display:block;margin-top:4px;color:var(--navy);font-size:18px;font-weight:950}
  .analytics-detail-stat small{display:block;margin-top:3px;color:var(--muted);font-size:10px;line-height:1.4}
  .analytics-detail-card{margin-bottom:11px;padding:0;overflow:hidden;border:1px solid var(--line);border-radius:15px;background:#fff}
  .analytics-detail-card summary{display:flex;align-items:center;justify-content:space-between;min-height:52px;padding:0 14px;cursor:pointer;font-size:13px;font-weight:900;list-style:none}
  .analytics-detail-card summary::-webkit-details-marker{display:none}.analytics-detail-card summary:after{content:'＋';font-size:18px}.analytics-detail-card[open] summary:after{content:'−'}
  .analytics-table-wrap{overflow-x:auto;border-top:1px solid var(--line)}
  .analytics-detail-table{width:100%;min-width:560px;border-collapse:collapse;font-size:11px}
  .analytics-detail-table th,.analytics-detail-table td{padding:10px 9px;border-bottom:1px solid #eef0f2;text-align:right;white-space:nowrap}
  .analytics-detail-table th{position:sticky;top:0;background:#f7f8fa;color:var(--muted);font-size:10px}
  .analytics-detail-table th:first-child,.analytics-detail-table td:first-child{text-align:left}
  .analytics-detail-table tr:last-child td{border-bottom:0}.analytics-rank{display:inline-grid;width:22px;height:22px;margin-right:6px;place-items:center;border-radius:50%;background:#eef1f5;font-size:10px;font-weight:900}
  .analytics-share{display:inline-block;min-width:44px;color:var(--muted)}
  .analytics-detail-empty{padding:24px;text-align:center;color:var(--muted);font-size:12px}
  @media(min-width:560px){.analytics-detail-grid{grid-template-columns:repeat(4,minmax(0,1fr))}}
 `;
 document.head.appendChild(style);

 function sum(rows,key){return rows.reduce((total,row)=>total+Number(row?.[key]||0),0)}
 function share(value,total){return total?`${(value/total*100).toFixed(1)}%`:'0.0%'}
 function table(headers,rows){return rows.length?`<div class="analytics-table-wrap"><table class="analytics-detail-table"><thead><tr>${headers.map(header=>`<th>${esc(header)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`:'<div class="analytics-detail-empty">この期間のデータはありません</div>'}
 function detail(title,headers,rows,open=false){return `<details class="analytics-detail-card"${open?' open':''}><summary>${esc(title)}</summary>${table(headers,rows)}</details>`}
 function renderAnalyticsDetails(){
  let root=$('analyticsDetailRoot');
  if(!root){root=document.createElement('div');root.id='analyticsDetailRoot';$('page-analytics')?.appendChild(root)}
  if(!root)return;
  const{start,end}=analyticsDateRange(),period=salesInRange(start,end),recovered=recoveredSales(period),gross=totalSales(recovered),extras=sum(recovered,'delivery_tobacco_amount'),storeSales=gross-extras,people=sum(recovered,'party_size'),unpaid=period.filter(row=>row.payment_status==='未収'),pending=recovered.filter(row=>!row.is_settled),expenseRows=(typeof expenses==='undefined'?[]:expenses).filter(row=>!row.deleted_at&&row.expense_date>=start&&row.expense_date<=end),expenseTotal=sum(expenseRows,'amount');
  const activeDates=[...new Set(period.map(row=>row.business_date).filter(Boolean))].sort().reverse();
  const dailyRows=activeDates.map(date=>{const rows=period.filter(row=>row.business_date===date),paid=recoveredSales(rows),dayGross=totalSales(paid),dayPeople=sum(paid,'party_size'),dayUnpaid=rows.filter(row=>row.payment_status==='未収');return`<tr><td>${esc(businessDateWithWeekday(date))}</td><td>${paid.length}</td><td>${dayPeople}</td><td>${yen(dayGross)}</td><td>${yen(totalSales(paid.filter(row=>row.payment_method==='現金')))}</td><td>${yen(totalSales(paid.filter(row=>row.payment_method==='カード')))}</td><td>${yen(totalSales(dayUnpaid))}</td></tr>`});
  const weekdayNames=['日','月','火','水','木','金','土'],weekdayData=weekdayNames.map((name,index)=>{const rows=recovered.filter(row=>parseDateLocal(row.business_date).getDay()===index),dates=new Set(rows.map(row=>row.business_date)),value=totalSales(rows);return{name,rows,dates:dates.size,value,people:sum(rows,'party_size')}}).filter(item=>item.rows.length).sort((a,b)=>b.value-a.value);
  const weekdayRows=weekdayData.map(item=>`<tr><td>${item.name}曜日</td><td>${item.dates}</td><td>${item.rows.length}</td><td>${yen(item.value)}</td><td>${yen(item.dates?item.value/item.dates:0)}</td><td>${yen(item.people?item.value/item.people:0)}</td></tr>`);
  const employeeRows=employees.map(employee=>{const rows=recovered.filter(row=>row.employee_id===employee.id),value=totalSales(rows);return{employee,rows,value,people:sum(rows,'party_size')}}).filter(item=>item.rows.length).sort((a,b)=>b.value-a.value).map((item,index)=>`<tr><td><span class="analytics-rank">${index+1}</span>${esc(item.employee.name)}</td><td>${item.rows.length}</td><td>${item.people}</td><td>${yen(item.value)}</td><td><span class="analytics-share">${share(item.value,gross)}</span></td><td>${yen(item.rows.length?item.value/item.rows.length:0)}</td></tr>`);
  const customerRows=activeCustomers().map(customer=>{const rows=recovered.filter(row=>row.customer_id===customer.id),value=totalSales(rows);return{customer,rows,value,people:sum(rows,'party_size')}}).filter(item=>item.rows.length).sort((a,b)=>b.value-a.value).slice(0,20).map((item,index)=>`<tr><td><span class="analytics-rank">${index+1}</span>${esc(item.customer.name)}</td><td>${item.rows.length}</td><td>${item.people}</td><td>${yen(item.value)}</td><td><span class="analytics-share">${share(item.value,gross)}</span></td><td>${yen(item.rows.length?item.value/item.rows.length:0)}</td></tr>`);
  root.innerHTML=`<div class="section-title">詳しい数値</div><div class="analytics-detail-grid">
   <div class="analytics-detail-stat"><span>会計件数</span><strong>${recovered.length}件</strong><small>回収済み</small></div>
   <div class="analytics-detail-stat"><span>来店人数</span><strong>${people}名</strong><small>会計の人数合計</small></div>
   <div class="analytics-detail-stat"><span>平均会計額</span><strong>${yen(recovered.length?gross/recovered.length:0)}</strong><small>1会計あたり</small></div>
   <div class="analytics-detail-stat"><span>店舗売上</span><strong>${yen(storeSales)}</strong><small>回収済み − 出前等</small></div>
   <div class="analytics-detail-stat"><span>出前・タバコ等</span><strong>${yen(extras)}</strong><small>${recovered.filter(row=>Number(row.delivery_tobacco_amount)>0).length}件</small></div>
   <div class="analytics-detail-stat"><span>未精算</span><strong>${yen(totalSales(pending))}</strong><small>${pending.length}件</small></div>
   <div class="analytics-detail-stat"><span>未収残高</span><strong>${yen(totalSales(unpaid))}</strong><small>${unpaid.length}件</small></div>
   <div class="analytics-detail-stat"><span>登録済み経費</span><strong>${yen(expenseTotal)}</strong><small>${expenseRows.length}件</small></div>
  </div>
  ${detail('日別明細',['営業日','会計','人数','売上','現金','カード','未収'],dailyRows,true)}
  ${detail('曜日別の傾向',['曜日','営業日','会計','売上','1日平均','客単価'],weekdayRows)}
  ${detail('口座別の詳細',['口座','会計','人数','売上','構成比','会計単価'],employeeRows)}
  ${detail('顧客別の詳細 TOP20',['顧客','会計','人数','売上','構成比','会計単価'],customerRows)}
  `;
 }
 const renderAnalyticsBeforeDetails=renderAnalytics;
 renderAnalytics=function(){renderAnalyticsBeforeDetails();renderAnalyticsDetails()};
})();