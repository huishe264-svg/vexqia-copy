const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {chromium}=require("C:/Users/jojoj/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright");
(async()=>{
  const root=path.resolve(__dirname,".."),html=fs.readFileSync(path.join(root,"index.html"),"utf8"),clock=fs.readFileSync(path.join(root,"business-time.js"),"utf8"),finance=fs.readFileSync(path.join(root,"owner-finance.js"),"utf8"),sql=fs.readFileSync(path.join(root,"supabase/migrations/20260905100000_store_business_clock.sql"),"utf8");
  assert.match(html,/business_day_cutoff_hour,business_timezone/);assert.match(html,/business-time\.js/);assert.match(clock,/latestCompletedBusinessDate/);assert.match(clock,/登録・更新時刻は実時刻のまま/);assert.match(finance,/businessDateString\(\)/);assert.match(sql,/business_day_cutoff_hour smallint not null default 7/);assert.match(sql,/update_store_business_clock/);
  const browser=await chromium.launch({headless:true,executablePath:"C:/Program Files/Google/Chrome/Application/chrome.exe"}),page=await browser.newPage();
  await page.route("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2",route=>route.fulfill({contentType:"application/javascript",body:`window.supabase={createClient(){return {auth:{getSession:async()=>({data:{session:null},error:null}),onAuthStateChange:()=>({data:{subscription:{unsubscribe(){}}}})}}}};`}));
  await page.route("https://cdn.jsdelivr.net/npm/chart.js@4.4.7/dist/chart.umd.min.js",route=>route.fulfill({contentType:"application/javascript",body:"window.Chart=class{destroy(){}update(){}}"}));
  await page.goto(`file:///${path.join(root,"index.html").replaceAll("\\","/")}`);
  const result=await page.evaluate(()=>{
    businessDayCutoffHour=7;businessTimezone="Asia/Tokyo";goalSettings={closed_weekdays:[0,6]};monthlyGoals=[];eventGoals=[];businessOverrides=[];
    return{
      fridayNight:businessDateString(new Date("2026-09-04T12:00:00Z")),
      saturdayEarly:businessDateString(new Date("2026-09-04T18:00:00Z")),
      cutoffBoundary:businessDateString(new Date("2026-09-04T22:00:00Z")),
      fridayNightInput:latestCompletedBusinessDate(new Date("2026-09-04T12:00:00Z")),
      saturdayEarlyInput:latestCompletedBusinessDate(new Date("2026-09-04T18:00:00Z")),
      mondayInput:latestCompletedBusinessDate(new Date("2026-09-07T12:00:00Z")),
      settingVisible:Boolean(document.getElementById("businessClockSettings")),
      cutoffOptions:document.getElementById("businessCutoffHour").options.length
    };
  });
  assert.deepEqual(result,{fridayNight:"2026-09-04",saturdayEarly:"2026-09-04",cutoffBoundary:"2026-09-05",fridayNightInput:"2026-09-03",saturdayEarlyInput:"2026-09-04",mondayInput:"2026-09-04",settingVisible:true,cutoffOptions:13});
  console.log("Business clock smoke test passed.");await browser.close();
})().catch(error=>{console.error(error);process.exit(1)});
