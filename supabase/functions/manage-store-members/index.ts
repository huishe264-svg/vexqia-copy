import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://huishe264-svg.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });

const appUrl = "https://huishe264-svg.github.io/vexqia-copy/";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SECRET_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return json({ error: "Authentication is required" }, 401);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = String(body.action || "");
  const storeId = String(body.store_id || "");
  if (!storeId) return json({ error: "store_id is required" }, 400);

  const { data: callerMember, error: callerError } = await adminClient
    .from("store_users")
    .select("role")
    .eq("store_id", storeId)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (callerError || callerMember?.role !== "owner") {
    return json({ error: "Only store owners can manage members" }, 403);
  }

  if (action === "list") {
    const { data: members, error: membersError } = await adminClient
      .from("store_users")
      .select("store_id,user_id,role,employee_id,created_at,updated_at")
      .eq("store_id", storeId)
      .order("created_at");
    if (membersError) return json({ error: membersError.message }, 400);

    const { data: authData, error: authError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    if (authError) return json({ error: authError.message }, 400);

    const emailById = new Map(authData.users.map((user) => [user.id, user.email || ""]));
    return json({
      members: (members || []).map((member) => ({
        ...member,
        email: emailById.get(member.user_id) || "",
      })),
    });
  }

  if (action === "invite") {
    const email = String(body.email || "").trim().toLowerCase();
    const role = String(body.role || "staff");
    const employeeId = body.employee_id ? String(body.employee_id) : null;
    if (!email || !email.includes("@")) return json({ error: "Valid email is required" }, 400);
    if (!['manager', 'staff'].includes(role)) return json({ error: "Invalid role" }, 400);

    if (employeeId) {
      const { data: employee } = await adminClient
        .from("employees")
        .select("id")
        .eq("id", employeeId)
        .eq("store_id", storeId)
        .maybeSingle();
      if (!employee) return json({ error: "Employee does not belong to this store" }, 400);
    }

    const { data: authData, error: authError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    if (authError) return json({ error: authError.message }, 400);

    let targetUser = authData.users.find((user) => user.email?.toLowerCase() === email);
    let invited = false;
    if (!targetUser) {
      const { data: inviteData, error: inviteError } = await adminClient.auth.admin.inviteUserByEmail(
        email,
        { redirectTo: appUrl },
      );
      if (inviteError || !inviteData.user) return json({ error: inviteError?.message || "Invite failed" }, 400);
      targetUser = inviteData.user;
      invited = true;
    }

    const { data: existing } = await adminClient
      .from("store_users")
      .select("role")
      .eq("store_id", storeId)
      .eq("user_id", targetUser.id)
      .maybeSingle();
    if (existing?.role === "owner") return json({ error: "Owner permissions cannot be changed" }, 403);

    const { error: membershipError } = await adminClient.from("store_users").upsert(
      {
        store_id: storeId,
        user_id: targetUser.id,
        role,
        employee_id: employeeId,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "store_id,user_id" },
    );
    if (membershipError) return json({ error: membershipError.message }, 400);

    return json({ ok: true, invited, user_id: targetUser.id, email });
  }

  return json({ error: "Unknown action" }, 400);
});

