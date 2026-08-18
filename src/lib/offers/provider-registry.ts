import type { Offer, OfferPlatform, OfferType } from '@/types';

/**
 * Normalized offer shape that all providers must convert to.
 * This is the internal representation stored in the `offers` table
 * and returned by `offer_list_available`.
 */
export interface NormalizedOffer {
  provider_offer_id: string;
  title: string;
  description: string;
  requirements: string;
  offer_type: OfferType;
  reward: number;
  currency_code: string;
  icon_url: string;
  destination_url: string;
  platform: OfferPlatform;
  estimated_time_minutes: number;
  difficulty: 'easy' | 'medium' | 'hard';
  category: string;
}

/**
 * Provider interface — each real provider implements this.
 * No fake providers are registered. Providers are only activated
 * after their credentials are configured in the admin panel.
 */
export interface OfferProviderAdapter {
  /** Unique slug matching the `offer_providers.slug` column */
  slug: string;
  /** Human-readable name for display */
  displayName: string;
  /** Category: survey, app_install, offerwall, game */
  type: 'survey' | 'app_install' | 'offerwall' | 'game';

  /**
   * Fetch available offers from the provider API.
   * Returns normalized offers. Called server-side only (edge function)
   * to keep API keys secret. Returns empty array if provider is not
   * configured or the API call fails.
   */
  fetchOffers(apiKey: string, publisherId: string, userId: string): Promise<NormalizedOffer[]>;

  /**
   * Build the provider tracking URL for a given offer.
   * Replaces placeholders with the platform's tracking_id and user_id.
   */
  createTrackingUrl(
    destinationUrlTemplate: string,
    trackingId: string,
    userId: string,
    publisherId: string,
    offerId: string,
  ): string;

  /**
   * Verify a provider postback signature.
   * Returns true if the signature is valid for the given secret.
   */
  verifyPostback(
    secret: string,
    params: Record<string, string>,
    rawQuery: string,
  ): Promise<boolean>;

  /**
   * Parse a provider postback into common fields.
   */
  parsePostback(
    params: Record<string, string>,
  ): {
    tracking_id: string;
    conversion_id: string;
    reward: number;
    revenue: number;
    event_type: 'conversion' | 'reversal';
    raw: Record<string, unknown>;
  } | null;
}

/**
 * Registry of provider adapters.
 * In the current state, no providers are registered because no
 * provider credentials have been configured. When a real provider
 * is added, its adapter is imported and registered here.
 *
 * To add a provider:
 * 1. Create src/lib/offers/providers/{slug}.ts implementing OfferProviderAdapter
 * 2. Import and register it in the registry below
 * 3. Configure credentials in the admin panel (API key + postback secret)
 * 4. Enable the provider in the admin panel
 */
export const providerRegistry: Record<string, OfferProviderAdapter> = {};

/**
 * Get a provider adapter by slug.
 * Returns undefined if the provider is not registered.
 */
export function getProviderAdapter(slug: string): OfferProviderAdapter | undefined {
  return providerRegistry[slug];
}

/**
 * List all registered provider slugs.
 */
export function listRegisteredProviders(): string[] {
  return Object.keys(providerRegistry);
}

/**
 * Default tracking URL builder — replaces common placeholder patterns.
 * Providers can override this with their own implementation.
 */
export function defaultCreateTrackingUrl(
  template: string,
  trackingId: string,
  userId: string,
  publisherId: string,
  offerId: string,
): string {
  return template
    .replace(/\[SUB_ID\]/g, trackingId)
    .replace(/\[USER_ID\]/g, userId)
    .replace(/\[PUBLISHER_ID\]/g, publisherId)
    .replace(/\[OFFER_ID\]/g, offerId)
    .replace(/\{sub_id\}/g, trackingId)
    .replace(/\{user_id\}/g, userId)
    .replace(/\{publisher_id\}/g, publisherId)
    .replace(/\{offer_id\}/g, offerId);
}

/**
 * Convert a NormalizedOffer to the Offer type used by the frontend.
 */
export function toOfferType(
  n: NormalizedOffer,
  providerId: string,
  providerSlug: string,
  providerName: string,
  offerId: string,
): Offer {
  return {
    id: offerId,
    provider_id: providerId,
    provider_slug: providerSlug,
    provider_name: providerName,
    provider_offer_id: n.provider_offer_id,
    title: n.title,
    description: n.description,
    requirements: n.requirements,
    offer_type: n.offer_type,
    reward: n.reward,
    currency_code: n.currency_code,
    icon_url: n.icon_url,
    destination_url: n.destination_url,
    platform: n.platform,
    estimated_time_minutes: n.estimated_time_minutes,
    difficulty: n.difficulty,
    category: n.category,
  };
}
