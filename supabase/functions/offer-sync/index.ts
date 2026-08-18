import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

/* ===========================================================
 * Provider offer-fetching adapters.
 * Each adapter fetches offers from a provider's API and normalizes
 * them into the common shape for upsert into the offers table.
 * These run server-side only — API keys are never exposed to the client.
 * =========================================================== */

interface NormalizedOffer {
  provider_offer_id: string;
  title: string;
  description: string;
  requirements: string;
  offer_type: string;
  reward: number;
  currency_code: string;
  icon_url: string;
  destination_url: string;
  platform: string;
  estimated_time_minutes: number;
  difficulty: string;
  category: string;
}

interface ProviderConfig {
  id: string;
  slug: string;
  display_name: string;
  publisher_id: string;
  currency_code: string;
  reward_margin_percent: number;
  config: Record<string, unknown>;
}

/* ---- CPX Research ----
 * API: https://offers.cpx-research.com/index.php
 * Returns survey offers. The API key is the app_id + secure_hash.
 * Docs: https://cpx-research.com/main/en/doc.php
 *
 * CPX provides a survey list API endpoint that returns available surveys
 * for a user. The publisher needs their app_id and secure_hash.
 */
async function fetchCpxOffers(
  apiKey: string,
  publisherId: string,
  config: Record<string, unknown>,
): Promise<NormalizedOffer[]> {
  const appId = config.app_id as string || publisherId;
  const apiUrl = `https://offers.cpx-research.com/index.php?app_id=${encodeURIComponent(appId)}&secure_hash=${encodeURIComponent(apiKey)}`;

  const resp = await fetch(apiUrl, {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  if (!resp.ok) {
    console.warn(`CPX API returned ${resp.status}`);
    return [];
  }

  const data = await resp.json();
  const surveys = data.surveys || [];

  return surveys.map((s: Record<string, unknown>) => {
    const payout = parseFloat(String(s.payout_publisher_usd || s.payout || 0));
    return {
      provider_offer_id: String(s.id),
      title: `Survey #${s.id} (${s.loi || "?"} min)`,
      description: `CPX Research survey — ${s.loi || "?"} min length, payout $${payout}`,
      requirements: "Complete the survey honestly. Disqualification may occur based on targeting criteria.",
      offer_type: "survey",
      reward: payout,
      currency_code: "USD",
      icon_url: "",
      destination_url: String(s.href || ""),
      platform: "web",
      estimated_time_minutes: parseInt(String(s.loi || 0), 10),
      difficulty: "medium",
      category: "survey",
    };
  });
}

/* ---- BitLabs ----
 * API: https://api.bitlabs.ai/v2/publisher/surveys
 * Returns survey offers. Requires the app's API key (publisher token).
 * Docs: https://developer.bitlabs.ai/docs
 *
 * BitLabs offers a survey feed API. The publisher needs their app token.
 */
async function fetchBitlabsOffers(
  apiKey: string,
  publisherId: string,
  _config: Record<string, unknown>,
): Promise<NormalizedOffer[]> {
  void _config;
  const apiUrl = `https://api.bitlabs/v2/publisher/surveys?token=${encodeURIComponent(apiKey)}&pubid=${encodeURIComponent(publisherId)}`;

  const resp = await fetch(apiUrl, {
    method: "GET",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
  });

  if (!resp.ok) {
    console.warn(`BitLabs API returned ${resp.status}`);
    return [];
  }

  const data = await resp.json();
  const surveys = data.data?.surveys || data.surveys || [];

  return surveys.map((s: Record<string, unknown>) => {
    const val = parseFloat(String(s.value || s.payout || 0)) / 1000;
    return {
      provider_offer_id: String(s.id || s.survey_id),
      title: `BitLabs Survey (${s.loi || s.length_minutes || "?"} min)`,
      description: `BitLabs survey — estimated ${s.loi || s.length_minutes || "?"} min`,
      requirements: "Complete the survey. You may be disqualified based on targeting.",
      offer_type: "survey",
      reward: val,
      currency_code: "USD",
      icon_url: String(s.icon || ""),
      destination_url: String(s.click_url || s.href || ""),
      platform: "web",
      estimated_time_minutes: parseInt(String(s.loi || s.length_minutes || 0), 10),
      difficulty: "medium",
      category: "survey",
    };
  });
}

/* ---- AdGem ----
 * AdGem Offer Wall API (deprecated but still functional for existing publishers).
 * Docs: https://docs.adgem.com
 * New publishers should use the offerwall embed. For API-based sync,
 * AdGem provides an offer feed endpoint.
 */
async function fetchAdgemOffers(
  apiKey: string,
  publisherId: string,
  _config: Record<string, unknown>,
): Promise<NormalizedOffer[]> {
  void _config;
  const apiUrl = `https://api.adgem.com/v1/offers?api_key=${encodeURIComponent(apiKey)}&publisher_id=${encodeURIComponent(publisherId)}`;

  const resp = await fetch(apiUrl, {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  if (!resp.ok) {
    console.warn(`AdGem API returned ${resp.status}`);
    return [];
  }

  const data = await resp.json();
  const offers = data.offers || [];

  return offers.map((o: Record<string, unknown>) => {
    const payout = parseFloat(String(o.payout || 0));
    return {
      provider_offer_id: String(o.id || o.campaign_id),
      title: String(o.name || o.title || "AdGem Offer"),
      description: String(o.description || ""),
      requirements: String(o.requirements || ""),
      offer_type: String(o.type || "other"),
      reward: payout,
      currency_code: String(o.currency || "USD"),
      icon_url: String(o.icon || o.image_url || ""),
      destination_url: String(o.tracking_url || o.url || ""),
      platform: String(o.platform || "all"),
      estimated_time_minutes: parseInt(String(o.time || 0), 10),
      difficulty: "easy",
      category: String(o.category || ""),
    };
  });
}

/* ---- OfferToro ----
 * Docs: https://www.offertoro.com/docs
 * OfferToro provides an offer feed API.
 */
async function fetchOffertoroOffers(
  apiKey: string,
  publisherId: string,
  _config: Record<string, unknown>,
): Promise<NormalizedOffer[]> {
  void _config;
  const apiUrl = `https://www.offertoro.com/api/v1/offers?api_key=${encodeURIComponent(apiKey)}&publisher_id=${encodeURIComponent(publisherId)}`;

  const resp = await fetch(apiUrl, {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  if (!resp.ok) {
    console.warn(`OfferToro API returned ${resp.status}`);
    return [];
  }

  const data = await resp.json();
  const offers = data.offers || [];

  return offers.map((o: Record<string, unknown>) => {
    const payout = parseFloat(String(o.payout || 0));
    return {
      provider_offer_id: String(o.offer_id || o.id),
      title: String(o.title || o.name || "OfferToro Offer"),
      description: String(o.description || ""),
      requirements: String(o.requirements || ""),
      offer_type: String(o.type || "other"),
      reward: payout,
      currency_code: String(o.currency || "USD"),
      icon_url: String(o.icon || ""),
      destination_url: String(o.tracking_url || o.url || ""),
      platform: String(o.platform || "all"),
      estimated_time_minutes: parseInt(String(o.estimated_time || 0), 10),
      difficulty: "easy",
      category: String(o.category || ""),
    };
  });
}

/* ---- MyLead ----
 * Docs: https://mylead.global
 * MyLead provides an offer feed API.
 */
async function fetchMyleadOffers(
  apiKey: string,
  publisherId: string,
  _config: Record<string, unknown>,
): Promise<NormalizedOffer[]> {
  void _config;
  const apiUrl = `https://api.mylead.global/v1/offers?api_key=${encodeURIComponent(apiKey)}&publisher_id=${encodeURIComponent(publisherId)}`;

  const resp = await fetch(apiUrl, {
    method: "GET",
    headers: { Accept: "application/json" },
  });

  if (!resp.ok) {
    console.warn(`MyLead API returned ${resp.status}`);
    return [];
  }

  const data = await resp.json();
  const offers = data.offers || [];

  return offers.map((o: Record<string, unknown>) => {
    const payout = parseFloat(String(o.payout || 0));
    return {
      provider_offer_id: String(o.id || o.offer_id),
      title: String(o.title || o.name || "MyLead Offer"),
      description: String(o.description || ""),
      requirements: String(o.requirements || ""),
      offer_type: String(o.type || "other"),
      reward: payout,
      currency_code: String(o.currency || "USD"),
      icon_url: String(o.icon || ""),
      destination_url: String(o.tracking_url || o.url || ""),
      platform: String(o.platform || "all"),
      estimated_time_minutes: parseInt(String(o.estimated_time || 0), 10),
      difficulty: "easy",
      category: String(o.category || ""),
    };
  });
}

const fetchers: Record<
  string,
  (apiKey: string, publisherId: string, config: Record<string, unknown>) => Promise<NormalizedOffer[]>
> = {
  cpx_research: fetchCpxOffers,
  bitlabs: fetchBitlabsOffers,
  adgem: fetchAdgemOffers,
  offertoro: fetchOffertoroOffers,
  mylead: fetchMyleadOffers,
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  // This function is callable by:
  // 1. The admin "Sync Now" button (sends the user's access token; verified via is_admin RPC)
  // 2. A cron job (sends the service role key)
  // It is NOT callable by anon/non-admin authenticated clients.
  const authHeader = req.headers.get("Authorization") || "";
  const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!bearerToken) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";

  if (!supabaseUrl || !serviceRoleKey || !anonKey) {
    console.error("Missing Supabase environment variables");
    return new Response(
      JSON.stringify({ error: "Server configuration error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Authorization check: either the service-role key (cron/scheduler) or an admin user.
  const isServiceRole = bearerToken === serviceRoleKey;

  if (!isServiceRole) {
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    });
    const { data: isAdmin, error: adminError } = await userClient.rpc("is_admin");
    if (adminError || !isAdmin) {
      return new Response(
        JSON.stringify({ error: "Forbidden" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Parse optional provider_slug from query or body
    let targetProviderSlug: string | null = null;
    if (req.method === "GET") {
      const url = new URL(req.url);
      targetProviderSlug = url.searchParams.get("provider_slug");
    } else if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      targetProviderSlug = body.provider_slug || null;
    }

    // Fetch enabled providers
    let providerQuery = supabase
      .from("offer_providers")
      .select("id, slug, display_name, publisher_id, currency_code, reward_margin_percent, config")
      .eq("enabled", true);

    if (targetProviderSlug) {
      providerQuery = providerQuery.eq("slug", targetProviderSlug);
    }

    const { data: providers, error: providerError } = await providerQuery;

    if (providerError || !providers || providers.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, synced: 0, message: "No enabled providers found" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const results: Array<{ slug: string; synced: number; error: string | null }> = [];

    for (const provider of providers as ProviderConfig[]) {
      const fetcher = fetchers[provider.slug];
      if (!fetcher) {
        results.push({ slug: provider.slug, synced: 0, error: "No fetcher implemented" });
        continue;
      }

      // Decrypt the API key via the service-role-only RPC
      const { data: apiKey, error: keyError } = await supabase.rpc(
        "offer_get_api_key",
        { p_provider_slug: provider.slug },
      );

      if (keyError || !apiKey) {
        results.push({ slug: provider.slug, synced: 0, error: "API key not configured" });
        continue;
      }

      try {
        // Fetch offers from the provider
        const offers = await fetcher(
          apiKey as string,
          provider.publisher_id,
          provider.config,
        );

        // Apply reward margin
        const margin = provider.reward_margin_percent / 100;
        const adjustedOffers = offers.map((o) => ({
          ...o,
          reward: o.reward * margin,
          currency_code: provider.currency_code || o.currency_code,
        }));

        // Upsert into the offers table via the service-role RPC
        const { data: upsertResult, error: upsertError } = await supabase.rpc(
          "offer_admin_upsert_offers",
          {
            p_provider_id: provider.id,
            p_offers: JSON.stringify(adjustedOffers),
          },
        );

        if (upsertError) {
          results.push({ slug: provider.slug, synced: 0, error: upsertError.message });
        } else {
          results.push({ slug: provider.slug, synced: (upsertResult as Record<string, number>)?.synced || 0, error: null });
        }
      } catch (err) {
        results.push({ slug: provider.slug, synced: 0, error: String(err) });
      }
    }

    return new Response(
      JSON.stringify({ ok: true, results }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Offer sync error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
