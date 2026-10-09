const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require('C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 try{
  const page=await browser.newPage();
  await page.route('https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',route=>route.fulfill({contentType:'application/javascript',body:'window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};'}));
  await page.route('https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js',route=>route.fulfill({contentType:'application/javascript',body:'window.Chart=class{constructor(){}destroy(){}};'}));
  await page.goto('file:///'+path.resolve(__dirname,'../index.html').replaceAll('\\','/'));
  const result=await page.evaluate(()=>{
   currentAuthUser={id:'owner'};currentStoreMember={user_id:'owner',role:'owner'};
   const month=businessDateString().slice(0,7),closedDate=`${month}-01`;
   goalSettings={weekday_goal:10000,weekend_goal:10000,closed_weekdays:[]};monthlyGoals=[];eventGoals=[];businessOverrides=[];businessDayClosures=[{business_date:closedDate}];sales=[];settlements=[{business_date:closedDate,settled_net_amount:15000}];schedules=[];
   renderGoalSection('homeGoalSection');
   const unset=[...$('homeGoalSection').querySelectorAll('.home-goal-stat')].find(row=>row.textContent.includes('現在差額'))?.querySelector('b')?.textContent;
   monthlyGoals=[{goal_month:`${month}-01`,target_amount:300000}];renderGoalSection('homeGoalSection');
   const configured=[...$('homeGoalSection').querySelectorAll('.home-goal-stat')].find(row=>row.textContent.includes('現在差額'))?.querySelector('b')?.textContent;
   return{unset,configured,monthLabel:$('homeGoalSection').textContent};
  });
  assert.equal(result.unset,'－');assert.notEqual(result.configured,'－');assert.match(result.monthLabel,/月間目標/);
  console.log('PASS: current difference stays blank until the monthly goal is configured.');
 }finally{await browser.close()}
})().catch(error=>{console.error(error);process.exit(1)});