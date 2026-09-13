import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://huishe264-svg.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
});

const namedKey = (environmentName: string) => {
  const raw = Deno.env.get(environmentName);
  if (!raw) return null;
  try {
    const keys = JSON.parse(raw) as Record<string, unknown>;
    const preferred = keys.default;
    if (typeof preferred === "string" && preferred) return preferred;
    return Object.values(keys).find((value): value is string => typeof value === "string" && Boolean(value)) ?? null;
  } catch {
    return null;
  }
};

const validDate = (value: unknown) => {
  const text = String(value ?? "");
  if (!/^20\d{2}-\d{2}-\d{2}$/.test(text)) return null;
  const date = new Date(`${text}T00:00:00Z`);
  return Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== text ? null : text;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "この操作には対応していません。" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = namedKey("SUPABASE_PUBLISHABLE_KEYS")
    ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
    ?? Deno.env.get("SUPABASE_ANON_KEY");
  const authorization = req.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "").trim();
  if (!supabaseUrl || !anonKey || !authorization || !accessToken) {
    return json({ error: "ログイン状態を確認できませんでした。もう一度ログインしてください。" }, 401);
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await caller.auth.getUser(accessToken);
  if (userError || !userData.user) return json({ error: "ログインの有効期限が切れました。もう一度ログインしてください。" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "画像を受け取れませんでした。もう一度選択してください。" }, 400);
  }

  const storeId = String(body.store_id ?? "");
  const mimeType = String(body.mime_type ?? "");
  const imageData = String(body.image_data ?? "");
  if (!storeId || !["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
    return json({ error: "読み取り可能な領収書画像を選択してください。" }, 400);
  }
  if (!imageData.startsWith(`data:${mimeType};base64,`) || imageData.length > 8_500_000) {
    return json({ error: "画像が大きすぎます。6MB以下の写真を選択してください。" }, 413);
  }

  const [{ data: member, error: memberError }, { data: settings, error: settingsError }] = await Promise.all([
    caller.from("store_users").select("role").eq("store_id", storeId).eq("user_id", userData.user.id).maybeSingle(),
    caller.from("store_operating_settings").select("expense_management_mode").eq("store_id", storeId).maybeSingle(),
  ]);
  if (memberError || settingsError) return json({ error: "店舗の権限を確認できませんでした。" }, 500);
  if (member?.role !== "owner" || settings?.expense_management_mode !== "full") {
    return json({ error: "領収書の読み取りは、完全管理を利用中のオーナーのみ使用できます。" }, 403);
  }

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return json({ error: "領収書読み取りの初期設定が完了していません。管理者へお知らせください。" }, 503);

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("RECEIPT_OCR_MODEL") || "gpt-4o-mini",
      store: false,
      max_output_tokens: 300,
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: "この日本の領収書・レシート画像から、取引日、支払先（店名）、支払総額を読み取ってください。税込合計・合計・領収金額を優先し、釣銭や預り金、小計は選ばないでください。読めない項目はnullにしてください。" },
          { type: "input_image", image_url: imageData, detail: "high" },
        ],
      }],
      text: {
        format: {
          type: "json_schema",
          name: "receipt_data",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            properties: {
              date: { type: ["string", "null"], description: "YYYY-MM-DD形式の取引日" },
              vendor: { type: ["string", "null"], description: "支払先または店舗名" },
              amount: { type: ["integer", "null"], description: "日本円の支払総額。通貨記号や桁区切りなし" },
            },
            required: ["date", "vendor", "amount"],
          },
        },
      },
    }),
  });

  if (!response.ok) {
    console.error("Receipt OCR API failed", { status: response.status, body: (await response.text()).slice(0, 500) });
    const message = response.status === 429
      ? "読み取りが混み合っています。少し待ってからもう一度お試しください。"
      : "領収書を読み取れませんでした。写真を撮り直すか、手入力してください。";
    return json({ error: message }, response.status === 429 ? 429 : 502);
  }

  const result = await response.json();
  const outputText = String(result.output_text ?? result.output?.flatMap((item: { content?: Array<{ type?: string; text?: string }> }) => item.content ?? []).find((item: { type?: string }) => item.type === "output_text")?.text ?? "");
  let receipt: Record<string, unknown>;
  try {
    receipt = JSON.parse(outputText);
  } catch {
    return json({ error: "文字は確認できましたが、項目へ分けられませんでした。手入力してください。" }, 422);
  }

  const amount = Number(receipt.amount);
  return json({
    receipt: {
      date: validDate(receipt.date),
      vendor: typeof receipt.vendor === "string" ? receipt.vendor.trim().slice(0, 120) || null : null,
      amount: Number.isSafeInteger(amount) && amount > 0 ? amount : null,
    },
  });
});
