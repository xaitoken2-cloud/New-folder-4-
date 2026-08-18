import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Client-Info, Apikey",
};

interface PostbackParams {
  provider_slug: string;
  tracking_id: string;
  conversion_id: string;
  reward: number;
  revenue: number;
  event_type: "conversion" | "reversal";
  signature: string;
  raw: Record<string, unknown>;
}

/* ===========================================================
 * Pure-JS MD5 implementation (dependency-free, Deno-compatible)
 * Used by CPX Research and other providers whose specs require MD5.
 * Based on the public-domain RFC 1321 reference algorithm.
 * =========================================================== */
function md5(input: string): string {
  function rh(n: number): string {
    let s = "", j: number;
    for (j = 0; j <= 3; j++)
      s += ((n >> (j * 8 + 4)) & 0x0f).toString(16) + ((n >> (j * 8)) & 0x0f).toString(16);
    return s;
  }
  function ad(n: number, m: number): number {
    const l = (n & 0xffff) + (m & 0xffff);
    const h = (n >> 16) + (m >> 16) + (l >> 16);
    return (h << 16) | (l & 0xffff);
  }
  function rl(n: number, c: number): number {
    return (n << c) | (n >>> (32 - c));
  }
  function cm(q: number, a: number, b: number, x: number, s: number, t: number): number {
    return ad(rl(ad(ad(a, q), ad(x, t)), s), b);
  }
  function ff(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return cm((b & c) | (~b & d), a, b, x, s, t);
  }
  function gg(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return cm((b & d) | (c & ~d), a, b, x, s, t);
  }
  function hh(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return cm(b ^ c ^ d, a, b, x, s, t);
  }
  function ii(a: number, b: number, c: number, d: number, x: number, s: number, t: number): number {
    return cm(c ^ (b | ~d), a, b, x, s, t);
  }
  function cb(s: string): number[] {
    const b: number[] = [];
    for (let i = 0; i < s.length * 8; i += 8) b[i >> 5] |= (s.charCodeAt(i / 8) & 0xff) << (i % 32);
    return b;
  }
  const x: number[] = cb(input);
  const len = input.length;
  x[len >> 5] |= 0x80 << (len % 32);
  x[(((len + 64) >>> 9) << 4) + 14] = len;

  let a = 1732584193, b = -271733879, c = -1732584194, d = 271733878;

  for (let i = 0; i < x.length; i += 16) {
    const oa = a, ob = b, oc = c, od = d;

    a = ff(a, b, c, d, x[i], 7, -680876936); d = ff(d, a, b, c, x[i + 1], 12, -389564586);
    c = ff(c, d, a, b, x[i + 2], 17, 606105819); b = ff(b, c, d, a, x[i + 3], 22, -1044525330);
    a = ff(a, b, c, d, x[i + 4], 7, -176418897); d = ff(d, a, b, c, x[i + 5], 12, 1200080426);
    c = ff(c, d, a, b, x[i + 6], 17, -1473231341); b = ff(b, c, d, a, x[i + 7], 22, -45705983);
    a = ff(a, b, c, d, x[i + 8], 7, 1770035416); d = ff(d, a, b, c, x[i + 9], 12, -1958414417);
    c = ff(c, d, a, b, x[i + 10], 17, -42063); b = ff(b, c, d, a, x[i + 11], 22, -1990404162);
    a = ff(a, b, c, d, x[i + 12], 7, 1804603682); d = ff(d, a, b, c, x[i + 13], 12, -40341101);
    c = ff(c, d, a, b, x[i + 14], 17, -1502002290); b = ff(b, c, d, a, x[i + 15], 22, 1236535329);

    a = gg(a, b, c, d, x[i + 1], 5, -165796510); d = gg(d, a, b, c, x[i + 6], 9, -1069501632);
    c = gg(c, d, a, b, x[i + 11], 14, 643717713); b = gg(b, c, d, a, x[i], 20, -373897302);
    a = gg(a, b, c, d, x[i + 5], 5, -701558691); d = gg(d, a, b, c, x[i + 10], 9, 38016083);
    c = gg(c, d, a, b, x[i + 15], 14, -660478375); b = gg(b, c, d, a, x[i + 4], 20, -405537848);
    a = gg(a, b, c, d, x[i + 9], 5, 568446438); d = gg(d, a, b, c, x[i + 14], 9, -1019803690);
    c = gg(c, d, a, b, x[i + 3], 14, -187363961); b = gg(b, c, d, a, x[i + 8], 20, 1163531501);
    a = gg(a, b, c, d, x[i + 13], 5, -1444681467); d = gg(d, a, b, c, x[i + 2], 9, -51403784);
    c = gg(c, d, a, b, x[i + 7], 14, 1735328473); b = gg(b, c, d, a, x[i + 12], 20, -1926607734);

    a = hh(a, b, c, d, x[i + 5], 4, -378558); d = hh(d, a, b, c, x[i + 8], 11, -2022574463);
    c = hh(c, d, a, b, x[i + 11], 16, 1839030562); b = hh(b, c, d, a, x[i + 14], 23, -35309556);
    a = hh(a, b, c, d, x[i + 1], 4, -1530992060); d = hh(d, a, b, c, x[i + 4], 11, 1272893353);
    c = hh(c, d, a, b, x[i + 7], 16, -155497632); b = hh(b, c, d, a, x[i + 10], 23, -1094730640);
    a = hh(a, b, c, d, x[i + 13], 4, 681279174); d = hh(d, a, b, c, x[i], 11, -358537222);
    c = hh(c, d, a, b, x[i + 3], 16, -722521979); b = hh(b, c, d, a, x[i + 6], 23, 76029189);
    a = hh(a, b, c, d, x[i + 9], 4, -640364487); d = hh(d, a, b, c, x[i + 12], 11, -421815835);
    c = hh(c, d, a, b, x[i + 15], 16, 530742520); b = hh(b, c, d, a, x[i + 2], 23, -995338651);

    a = ii(a, b, c, d, x[i], 6, -198630844); d = ii(d, a, b, c, x[i + 7], 10, 1126891415);
    c = ii(c, d, a, b, x[i + 14], 15, -1416354905); b = ii(b, c, d, a, x[i + 5], 21, -57434055);
    a = ii(a, b, c, d, x[i + 12], 6, 1700485571); d = ii(d, a, b, c, x[i + 3], 10, -1894986606);
    c = ii(c, d, a, b, x[i + 10], 15, -1051523); b = ii(b, c, d, a, x[i + 1], 21, -2054922799);
    a = ii(a, b, c, d, x[i + 8], 6, 1873313359); d = ii(d, a, b, c, x[i + 15], 10, -30611744);
    c = ii(c, d, a, b, x[i + 6], 15, -1560198380); b = ii(b, c, d, a, x[i + 13], 21, 1309151649);
    a = ii(a, b, c, d, x[i + 4], 6, -145523070); d = ii(d, a, b, c, x[i + 11], 10, -1120210379);
    c = ii(c, d, a, b, x[i + 2], 15, 718787259); b = ii(b, c, d, a, x[i + 9], 21, -343485551);

    a = ad(a, oa); b = ad(b, ob); c = ad(c, oc); d = ad(d, od);
  }
  return rh(a) + rh(b) + rh(c) + rh(d);
}

/* ===========================================================
 * HMAC helpers using Web Crypto API (SHA-1, SHA-256)
 * =========================================================== */
async function hmacHex(
  algorithm: "SHA-1" | "SHA-256",
  secret: string,
  message: string,
): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: algorithm },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/* ===========================================================
 * Provider-specific postback parsers.
 * Each parser extracts the common fields from the provider's
 * specific parameter names, per their official documentation.
 * =========================================================== */
const providerParsers: Record<
  string,
  (params: URLSearchParams | Record<string, string>) => PostbackParams | null
> = {
  // AdGem v3 POST: JSON body with conversion_id, player_id, payout, amount
  // AdGem v2 GET: query params with sub_id, transaction_id, payout
  adgem: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    return {
      provider_slug: "adgem",
      tracking_id: p.player_id || p.sub_id || p.s2 || "",
      conversion_id: p.conversion_id || p.transaction_id || "",
      reward: parseFloat(p.payout || p.reward || p.amount || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: (p.type === "reversal" || p.status === "reversed") ? "reversal" : "conversion",
      signature: p.verifier || p.signature || "",
      raw: p as Record<string, unknown>,
    };
  },

  // OfferToro: https://www.offertoro.com/docs
  // Parameters: id (user_id), offer_id, amount, sig
  offertoro: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    return {
      provider_slug: "offertoro",
      tracking_id: p.id || p.user_id || p.subid || "",
      conversion_id: p.offer_id || p.transaction_id || "",
      reward: parseFloat(p.amount || p.payout || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: p.status === "reversed" ? "reversal" : "conversion",
      signature: p.sig || p.signature || "",
      raw: p as Record<string, unknown>,
    };
  },

  // CPX Research: https://docs.cpx-research.com
  // Postback parameters: subid, transaction_id, reward, secure_hash
  cpx_research: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    return {
      provider_slug: "cpx_research",
      tracking_id: p.subid || p.sub_id || p.click_id || p.ext_user_id || "",
      conversion_id: p.transaction_id || p.session_id || "",
      reward: parseFloat(p.reward || p.payout || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: (p.type === "reversal" || p.status === "reversed") ? "reversal" : "conversion",
      signature: p.secure_hash || p.signature || p.hash || "",
      raw: p as Record<string, unknown>,
    };
  },

  // BitLabs: https://developer.bitlabs.ai/docs/securing-callbacks-through-hashing
  // GET callback with hash param (HMAC-SHA1 of URL minus hash)
  bitlabs: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    return {
      provider_slug: "bitlabs",
      tracking_id: p.uid || p.subid || p.sub_id || p.click_id || "",
      conversion_id: p.transaction_id || p.offer_id || p.id || "",
      reward: parseFloat(p.val || p.payout || p.reward || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: p.type === "reversal" ? "reversal" : "conversion",
      signature: p.hash || p.signature || "",
      raw: p as Record<string, unknown>,
    };
  },

  // MyLead: https://mylead.global/en/blog/postback-api-configuration
  // Parameters: click_id, transaction_id, payout, security_token
  mylead: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    return {
      provider_slug: "mylead",
      tracking_id: p.click_id || p.sub_id || p.aff_sub || "",
      conversion_id: p.transaction_id || p.conversion_id || "",
      reward: parseFloat(p.payout || p.reward || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: (p.status === "reversed" || p.type === "reversal") ? "reversal" : "conversion",
      signature: p.security_token || p.signature || "",
      raw: p as Record<string, unknown>,
    };
  },

  // Generic/fallback parser
  generic: (params) => {
    const p = params instanceof URLSearchParams
      ? Object.fromEntries(params.entries())
      : params;
    const slug = p.provider || p.provider_slug || p.source || "generic";
    return {
      provider_slug: slug,
      tracking_id: p.sub_id || p.subid || p.click_id || p.tracking_id || p.s2 || "",
      conversion_id: p.transaction_id || p.conversion_id || p.tx_id || "",
      reward: parseFloat(p.payout || p.reward || p.amount || "0"),
      revenue: parseFloat(p.revenue || "0"),
      event_type: (p.type === "reversal" || p.status === "reversed") ? "reversal" : "conversion",
      signature: p.signature || p.sig || p.hash || p.security_token || "",
      raw: p as Record<string, unknown>,
    };
  },
};

/* ===========================================================
 * Verify provider signature.
 * Each provider has a different signature scheme per their docs.
 * Returns true only if the signature is valid.
 * =========================================================== */
async function verifySignature(
  supabase: ReturnType<typeof createClient>,
  parsed: PostbackParams,
  rawQuery: string,
  rawBody: string,
  requestUrl: string,
  signatureHeader: string,
): Promise<boolean> {
  // Fetch the provider's postback secret from the database
  const { data: secretData, error: secretError } = await supabase.rpc(
    "offer_get_postback_secret",
    { p_provider_slug: parsed.provider_slug, p_secret_type: "postback_secret" },
  );

  if (secretError || !secretData) {
    console.warn(
      `No postback secret configured for provider: ${parsed.provider_slug}`,
    );
    return false;
  }

  const secret = secretData as string;

  switch (parsed.provider_slug) {
    /* ---- AdGem ----
     * v3 (POST): HMAC-SHA256 of the raw request body vs the `Signature` header.
     * v2 (GET): HMAC-SHA256 of the full URL minus the `verifier` param vs `verifier`.
     * Docs: https://docs.adgem.com/docs/integrate/reward-mechanism/postbacks-v3
     */
    case "adgem": {
      if (signatureHeader) {
        // v3 POST: hash the raw body
        const expected = await hmacHex("SHA-256", secret, rawBody);
        return expected.toLowerCase() === signatureHeader.toLowerCase();
      }
      if (parsed.signature) {
        // v2 GET: hash the URL minus the verifier param
        const url = new URL(requestUrl);
        const params = new URLSearchParams(url.search);
        const verifier = params.get("verifier") || "";
        params.delete("verifier");
        const baseUrl = `${url.origin}${url.pathname}`;
        const queryString = params.toString();
        const urlToHash = queryString
          ? `${baseUrl}?${queryString}`
          : baseUrl;
        const expected = await hmacHex("SHA-256", secret, urlToHash);
        return expected.toLowerCase() === verifier.toLowerCase();
      }
      return false;
    }

    /* ---- OfferToro ----
     * MD5 of (secret + user_id + transaction_id + amount)
     * The exact field order could not be confirmed from public docs.
     * If this fails, the user must verify the exact hash scheme from
     * their OfferToro dashboard and adjust accordingly.
     */
    case "offertoro": {
      if (!parsed.signature) return false;
      const msg = `${secret}${parsed.tracking_id}${parsed.conversion_id}${parsed.reward}`;
      const expected = md5(msg);
      return expected.toLowerCase() === parsed.signature.toLowerCase();
    }

    /* ---- CPX Research ----
     * CPX uses MD5 of ({ext_user_id}-{app_secure_hash}) for iframe auth.
     * For postbacks, the secure_hash is MD5 of a combination of
     * transaction parameters and the app secret.
     * Docs: https://cpx-research.com/main/en/doc.php
     * The exact postback hash format may vary — confirm in your
     * CPX publisher dashboard.
     */
    case "cpx_research": {
      if (!parsed.signature) return false;
      // CPX secure_hash = md5(ext_user_id + '-' + app_secure_hash)
      // For postback verification, try the common scheme:
      const msg = `${parsed.tracking_id}-${secret}`;
      const expected = md5(msg);
      return expected.toLowerCase() === parsed.signature.toLowerCase();
    }

    /* ---- BitLabs ----
     * HMAC-SHA1 (not SHA-256!) of the full URL minus the hash param.
     * Docs: https://developer.bitlabs.ai/docs/securing-callbacks-through-hashing
     * "This hash consists of a HEX-encoded SHA1 HMAC. The whole URL is
     * hashed with the secret key of the App."
     */
    case "bitlabs": {
      if (!parsed.signature) return false;
      // Remove the hash param from the URL and hash the remainder
      const url = new URL(requestUrl);
      const params = new URLSearchParams(url.search);
      params.delete("hash");
      const baseUrl = `${url.origin}${url.pathname}`;
      const queryString = params.toString();
      const urlToHash = queryString
        ? `${baseUrl}?${queryString}`
        : baseUrl;
      const expected = await hmacHex("SHA-1", secret, urlToHash);
      return expected.toLowerCase() === parsed.signature.toLowerCase();
    }

    /* ---- MyLead ----
     * MyLead uses a security_token for postback verification.
     * The exact hash scheme could not be confirmed from public docs.
     * MyLead's docs mention IP-restricted security as the primary method.
     * If the security_token is present and matches the configured secret,
     * we accept it. Otherwise, reject.
     * Docs: https://mylead.global/en/blog/postback-api-configuration
     */
    case "mylead": {
      if (!parsed.signature) return false;
      // MyLead's security_token is compared directly to the configured secret
      return parsed.signature === secret;
    }

    default: {
      // Generic: HMAC-SHA256 of the raw query string
      if (!parsed.signature) return false;
      const expected = await hmacHex("SHA-256", secret, rawQuery);
      return expected.toLowerCase() === parsed.signature.toLowerCase();
    }
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const pathSegments = url.pathname.split("/").filter(Boolean);
    const providerSlug = pathSegments[pathSegments.length - 1] ||
      pathSegments[0] || "";

    const providerFromQuery = url.searchParams.get("provider") ||
      url.searchParams.get("source") || "";
    const finalProviderSlug = providerSlug || providerFromQuery || "generic";

    let params: URLSearchParams | Record<string, string>;
    let rawQuery = url.search;
    let rawBody = "";

    if (req.method === "GET") {
      params = url.searchParams;
    } else if (req.method === "POST") {
      rawBody = await req.text();
      const contentType = req.headers.get("content-type") || "";
      if (contentType.includes("application/json")) {
        const json = JSON.parse(rawBody);
        params = json as Record<string, string>;
        rawQuery = rawBody;
      } else {
        params = new URLSearchParams(rawBody);
        rawQuery = rawBody;
      }
    } else {
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const parser = providerParsers[finalProviderSlug] ||
      providerParsers["generic"];
    const parsed = parser(params);

    if (!parsed) {
      return new Response(
        JSON.stringify({ error: "Failed to parse postback parameters" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Override provider_slug with the URL-specified one if it was set explicitly
    if (providerSlug && providerSlug !== "offer-webhook") {
      parsed.provider_slug = providerSlug;
    }

    // Validate required fields
    if (!parsed.tracking_id || !parsed.conversion_id) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: tracking_id, conversion_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (parsed.reward <= 0 && parsed.event_type === "conversion") {
      return new Response(
        JSON.stringify({ error: "Invalid reward amount" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Create service-role Supabase client
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

    if (!supabaseUrl || !serviceRoleKey) {
      console.error("Missing Supabase environment variables");
      return new Response(
        JSON.stringify({ error: "Server configuration error" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    });

    // Verify provider signature
    const signatureHeader = req.headers.get("Signature") || "";
    const signatureValid = await verifySignature(
      supabase,
      parsed,
      rawQuery,
      rawBody,
      url.href,
      signatureHeader,
    );

    if (!signatureValid) {
      console.warn(
        `Signature verification failed for provider: ${parsed.provider_slug}`,
      );
      // Record the rejected attempt for audit
      await supabase.rpc("offer_log_rejected_postback", {
        p_provider_slug: parsed.provider_slug,
        p_tracking_id: parsed.tracking_id,
        p_conversion_id: parsed.conversion_id,
        p_reward: parsed.reward,
        p_revenue: parsed.revenue || 0,
        p_event_type: parsed.event_type,
        p_raw: { ...parsed.raw, _signature_valid: false },
      }).then(({ error }) => {
        if (error) console.error("Failed to record rejected conversion:", error);
      });
      return new Response(
        JSON.stringify({ error: "Signature verification failed" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Process the conversion via the SECURITY DEFINER function
    const { data: result, error: rpcError } = await supabase.rpc(
      "offer_process_conversion",
      {
        p_provider_slug: parsed.provider_slug,
        p_tracking_id: parsed.tracking_id,
        p_conversion_id: parsed.conversion_id,
        p_reward: parsed.reward,
        p_revenue: parsed.revenue || 0,
        p_event_type: parsed.event_type,
        p_raw: parsed.raw,
      },
    );

    if (rpcError) {
      console.error("RPC error:", rpcError);
      return new Response(
        JSON.stringify({ error: "Failed to process conversion" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const status = (result as Record<string, string>)?.status || "processed";

    return new Response(
      JSON.stringify({ status, provider: parsed.provider_slug }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Webhook error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
