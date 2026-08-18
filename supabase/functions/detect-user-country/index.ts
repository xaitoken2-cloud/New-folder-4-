import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userError } = await adminClient.auth.getUser(token);
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const callerId = userData.user.id;

    // Resolve client IP from headers (do not store it)
    let clientIp: string | null = null;
    const xff = req.headers.get("x-forwarded-for");
    if (xff) {
      clientIp = xff.split(",")[0].trim();
    } else {
      const xRealIp = req.headers.get("x-real-ip");
      if (xRealIp) {
        clientIp = xRealIp.trim();
      } else {
        const cfIp = req.headers.get("cf-connecting-ip");
        if (cfIp) clientIp = cfIp.trim();
      }
    }

    if (!clientIp) {
      return new Response(JSON.stringify({ country: null, detected: false }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Geolocate using free API, pass client IP explicitly
    let countryCode: string | null = null;
    try {
      const resp = await fetch(`https://ip-api.com/json/${clientIp}?fields=countryCode`);
      if (resp.ok) {
        const body = await resp.json();
        if (body?.countryCode) countryCode = body.countryCode;
      }
    } catch {
      // fall through to fallback
    }

    if (!countryCode) {
      try {
        const resp = await fetch(`https://ipapi.co/${clientIp}/country/`);
        if (resp.ok) {
          const code = (await resp.text()).trim();
          if (code && code.length === 2) countryCode = code;
        }
      } catch {
        // both geolocation attempts failed
      }
    }

    if (!countryCode) {
      return new Response(JSON.stringify({ country: null, detected: false }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    countryCode = countryCode.toUpperCase();

    // Only set country once automatically — guard with country_detected = false
    const { error: updateError } = await adminClient
      .from("profiles")
      .update({ country: countryCode, country_detected: true })
      .eq("id", callerId)
      .eq("country_detected", false);

    if (updateError) {
      console.error("Failed to update country:", updateError);
    }

    return new Response(JSON.stringify({ country: countryCode, detected: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("detect-user-country error:", err);
    return new Response(JSON.stringify({ country: null, detected: false }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
