import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminToken = authHeader.replace("Bearer ", "");

    const { data: { user }, error: userError } = await adminClient.auth.getUser(adminToken);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: adminProfile, error: profileError } = await adminClient
      .from("profiles")
      .select("role, status, username")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError || !adminProfile || adminProfile.role !== "admin") {
      return new Response(JSON.stringify({ error: "Not authorized" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { targetUserId } = await req.json();
    if (!targetUserId) {
      return new Response(JSON.stringify({ error: "Target user ID required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: targetProfile, error: targetError } = await adminClient
      .from("profiles")
      .select("id, username, email, status, role")
      .eq("id", targetUserId)
      .maybeSingle();

    if (targetError || !targetProfile) {
      return new Response(JSON.stringify({ error: "Target user not found" }), {
        status: 404,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (targetProfile.role === "admin") {
      return new Response(JSON.stringify({ error: "Cannot impersonate an admin" }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (!targetProfile.email) {
      return new Response(JSON.stringify({ error: "Target user has no email on file" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Generate a magic link token for the target user
    const redirectUrl = Deno.env.get("REDIRECT_URL") || undefined;
    const { data: linkData, error: linkError } = await adminClient.auth.admin.generateLink({
      type: "magiclink",
      email: targetProfile.email,
      options: redirectUrl ? { redirectTo: redirectUrl } : undefined,
    });

    if (linkError || !linkData) {
      console.error(linkError);
      return new Response(
        JSON.stringify({ error: "Failed to generate session: " + (linkError?.message ?? "unknown") }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const properties = linkData.properties as Record<string, string>;
    const hashedToken = properties?.hashed_token;
    if (!hashedToken) {
      return new Response(
        JSON.stringify({ error: "Failed to generate session: no hashed token in response" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Use an anon-key client to verify the OTP and get a session
    const anonClient = createClient(supabaseUrl, anonKey);
    const { data: verifyData, error: verifyError } = await anonClient.auth.verifyOtp({
      token_hash: hashedToken,
      type: "magiclink",
    });

    if (verifyError || !verifyData.session) {
      console.error(verifyError);
      return new Response(
        JSON.stringify({ error: "Failed to establish session: " + (verifyError?.message ?? "no session returned") }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    await adminClient.from("audit_logs").insert({
      actor_id: user.id,
      action: "impersonate_user",
      target_type: "profile",
      target_id: targetUserId,
      details: { username: targetProfile.username, admin_username: adminProfile.username },
    });

    return new Response(JSON.stringify({
      access_token: verifyData.session.access_token,
      refresh_token: verifyData.session.refresh_token,
      user_id: targetUserId,
      username: targetProfile.username,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
