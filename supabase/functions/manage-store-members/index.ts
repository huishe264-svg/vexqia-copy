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

const failure = (code: string, message: string, status = 400, detail?: string) =>
  json({ error: message, code, ...(detail ? { detail } : {}) }, status);

const appUrl = "https://huishe264-svg.github.io/vexqia-copy/";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = namedKey("SUPABASE_PUBLISHABLE_KEYS")
    ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
    ?? Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = namedKey("SUPABASE_SECRET_KEYS")
    ?? Deno.env.get("SUPABASE_SECRET_KEY")
    ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");
  const accessToken = authorization?.replace(/^Bearer\s+/i, "").trim();

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization || !accessToken) {
    return json({ error: "Authentication is required" }, 401);
  }

  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const mailClient = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Verify the caller's current user token here. The legacy gateway JWT verifier is
  // intentionally disabled because it cannot validate Supabase's asymmetric JWTs.
  const { data: userData, error: userError } = await callerClient.auth.getUser(accessToken);
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = String(body.action || "");

  if (action === "claim") {
    const { data: claimed, error: claimError } = await callerClient.rpc("claim_store_invitations");
    if (claimError) {
      console.error("Failed to claim store invitations", {
        userId: userData.user.id,
        email: userData.user.email,
        code: claimError.code,
        message: claimError.message,
      });
      return json({ error: "Invitation claim failed", detail: claimError.message, code: claimError.code }, 409);
    }
    return json({ ok: true, claimed: claimed || [] });
  }

  const storeId = String(body.store_id || "");
  if (!storeId) return json({ error: "store_id is required" }, 400);

  // Check the caller's own membership with the same authenticated client used by
  // the app. This avoids treating an admin-client connection problem as if the
  // signed-in owner did not have permission.
  const { data: callerMember, error: callerError } = await callerClient
    .from("store_users")
    .select("role")
    .eq("store_id", storeId)
    .eq("user_id", userData.user.id)
    .maybeSingle();

  if (callerError) {
    console.error("Failed to verify store membership", {
      storeId,
      userId: userData.user.id,
      code: callerError.code,
      message: callerError.message,
    });
    return json({ error: "Member permission check failed" }, 500);
  }

  if (callerMember?.role !== "owner") {
    return json({ error: "Only store owners can manage members" }, 403);
  }

  if (action === "list") {
    // Membership rows are safe to read through the caller's authenticated client.
    // RLS already restricts them to the caller's own store, so the member list
    // remains available even if the separate admin email lookup is unavailable.
    const { data: members, error: membersError } = await callerClient
      .from("store_users")
      .select("store_id,user_id,role,employee_id,created_at,updated_at")
      .eq("store_id", storeId)
      .order("created_at");
    if (membersError) {
      console.error("Failed to load store members", {
        storeId,
        code: membersError.code,
        message: membersError.message,
      });
      return json({ error: "Member list query failed", code: membersError.code }, 500);
    }

    const { data: invitations, error: invitationsError } = await adminClient
      .from("store_invitations")
      .select("store_id,email,role,employee_id,status,created_at,updated_at")
      .eq("store_id", storeId)
      .eq("status", "pending")
      .order("created_at");
    if (invitationsError) {
      console.error("Failed to load pending invitations", {
        storeId,
        code: invitationsError.code,
        message: invitationsError.message,
      });
      return json({ error: "Invitation list query failed", code: invitationsError.code }, 500);
    }

    const { data: authData, error: authError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    if (authError) {
      console.error("Failed to load authentication users", {
        code: authError.code,
        message: authError.message,
      });
      return json({
        members: (members || []).map((member) => ({ ...member, email: "" })),
        invitations: invitations || [],
        warning: "Auth user list failed",
      });
    }

    const emailById = new Map(authData.users.map((user) => [user.id, user.email || ""]));

    return json({
      members: (members || []).map((member) => ({
        ...member,
        email: emailById.get(member.user_id) || "",
      })),
      invitations: invitations || [],
    });
  }

  if (action === "invite") {
    const email = String(body.email || "").trim().toLowerCase();
    const role = String(body.role || "staff");
    const employeeId = body.employee_id ? String(body.employee_id) : null;
    if (!email || !email.includes("@")) return failure("INVALID_EMAIL", "Valid email is required");
    if (!['manager', 'staff'].includes(role)) return failure("INVALID_ROLE", "Invalid role");
    if (role === "staff" && !employeeId) {
      return failure("STAFF_EMPLOYEE_REQUIRED", "Staff accounts must be linked to an employee account");
    }

    if (employeeId) {
      const { data: employee } = await adminClient
        .from("employees")
        .select("id")
        .eq("id", employeeId)
        .eq("store_id", storeId)
        .maybeSingle();
      if (!employee) return failure("EMPLOYEE_NOT_FOUND", "Employee does not belong to this store");
    }

    const { data: authData, error: authError } = await adminClient.auth.admin.listUsers({
      page: 1,
      perPage: 1000,
    });
    if (authError) {
      console.error("Failed to search authentication users", {
        code: authError.code,
        message: authError.message,
      });
      return failure("AUTH_LIST_FAILED", "Auth user list failed", 500, authError.message);
    }

    const targetUser = authData.users.find((user) => user.email?.toLowerCase() === email);

    if (employeeId) {
      const { data: linkedMember, error: linkedMemberError } = await adminClient
        .from("store_users")
        .select("user_id")
        .eq("store_id", storeId)
        .eq("employee_id", employeeId)
        .maybeSingle();
      if (linkedMemberError) return failure("MEMBERSHIP_CHECK_FAILED", "Member account check failed", 500, linkedMemberError.message);
      if (linkedMember && linkedMember.user_id !== targetUser?.id) {
        return failure("EMPLOYEE_ALREADY_LINKED", "Employee account is already linked to another member", 409);
      }

      const { data: pendingEmployee, error: pendingEmployeeError } = await adminClient
        .from("store_invitations")
        .select("email")
        .eq("store_id", storeId)
        .eq("employee_id", employeeId)
        .eq("status", "pending")
        .neq("email", email)
        .maybeSingle();
      if (pendingEmployeeError) return failure("INVITATION_CHECK_FAILED", "Pending invitation check failed", 500, pendingEmployeeError.message);
      if (pendingEmployee) {
        return failure("EMPLOYEE_ALREADY_RESERVED", "Employee account is already reserved by another invitation", 409);
      }
    }

    if (targetUser) {
      const { data: existing } = await adminClient
        .from("store_users")
        .select("role")
        .eq("store_id", storeId)
        .eq("user_id", targetUser.id)
        .maybeSingle();
      if (existing?.role === "owner") return failure("OWNER_ROLE_PROTECTED", "Owner permissions cannot be changed", 403);
    }

    // Every address follows the same flow: save a pending invitation first, then
    // let the recipient claim it with the verified email in their own session.
    // This avoids assigning a store to a different or not-yet-confirmed Auth user.
    const { error: pendingError } = await callerClient.rpc("save_store_invitation", {
      target_store_id: storeId,
      target_email: email,
      target_role: role,
      target_employee_id: employeeId,
      target_provisional_user_id: targetUser?.id ?? null,
    });
    if (pendingError) {
      console.error("Pending invitation could not be saved", {
        storeId,
        email,
        code: pendingError.code,
        message: pendingError.message,
      });
      return failure("INVITATION_SAVE_FAILED", "Pending invitation could not be saved", 500, pendingError.message);
    }

    // Magic links work for both existing and new Auth users. Google login with
    // the same email remains available if email delivery is delayed or blocked.
    const { error: emailError } = await mailClient.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
        emailRedirectTo: appUrl,
      },
    });
    if (emailError) {
      console.error("Invitation login email could not be sent", {
        email,
        code: emailError.code,
        message: emailError.message,
      });
      return json({
        ok: true,
        pending: true,
        email,
        email_delivery: "failed",
        code: "LOGIN_EMAIL_FAILED",
        warning: "Invitation was saved, but the login email could not be sent",
      });
    }

    return json({ ok: true, pending: true, email, email_delivery: "sent" });
  }

  return json({ error: "Unknown action" }, 400);
});

