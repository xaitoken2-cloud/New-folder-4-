import type { ReactNode } from 'react';
import { Badge } from '@/components/ui';
import { MousePointerClick } from 'lucide-react';

export interface PtcAdCardProps {
  title: string;
  description: string;
  advertiser: string;
  category: string;
  image_url: string;
  reward: number;
  duration_seconds: number;
  ctaLabel?: string;
  interactive?: boolean;
  imageOverlay?: ReactNode;
  children?: ReactNode;
}

export function PtcAdCard({
  title,
  description,
  advertiser,
  category,
  image_url,
  reward,
  duration_seconds,
  ctaLabel = 'Start Viewing',
  interactive = true,
  imageOverlay,
  children,
}: PtcAdCardProps) {
  const xcEarningRate = Number.isFinite(reward) && Number.isFinite(duration_seconds) && duration_seconds > 0
    ? reward / duration_seconds
    : 0;

  return (
    <div className="card overflow-hidden break-words">
      {/* Ad content area */}
      <div className="relative h-64 bg-gradient-to-br from-ink-800 to-ink-850 flex items-center justify-center">
        {image_url ? (
          <img src={image_url} alt={title} className="w-full h-full object-cover" />
        ) : (
          <div className="text-center">
            <MousePointerClick size={48} className="text-brand-500/30 mx-auto mb-3" />
            <p className="text-sm text-gray-500">{advertiser || 'Advertisement'}</p>
          </div>
        )}
        {imageOverlay}
      </div>

      {/* Ad info */}
      <div className="p-5">
        <div className="flex items-center gap-2 mb-2">
          <Badge variant="brand">{category}</Badge>
          <Badge variant="neutral">{advertiser}</Badge>
        </div>
        <h2 className="text-lg font-bold text-gray-100 mb-1 break-words">{title}</h2>
        <p className="text-sm text-gray-500 mb-4 break-words">{description}</p>

        {/* Reward + duration */}
        <div className="flex items-center justify-between p-3 rounded-lg bg-ink-800 mb-3">
          <div>
            <div className="text-xs text-gray-500">Reward</div>
            <div className="text-lg font-mono font-bold text-brand-400">{Number(reward).toFixed(2)} XC</div>
          </div>
          <div className="text-right">
            <div className="text-xs text-gray-500">Duration</div>
            <div className="text-lg font-mono font-bold text-gray-200">{duration_seconds}s</div>
          </div>
        </div>

        <div className="flex items-center justify-between text-xs text-gray-500 mb-4">
          <span>Earning Rate</span>
          <span className="font-mono text-gray-300">{xcEarningRate.toFixed(4)} XC/sec</span>
        </div>

        {children ?? (
          <button type="button" disabled={!interactive} className="btn-primary w-full">
            <MousePointerClick size={18} /> {ctaLabel}
          </button>
        )}
      </div>
    </div>
  );
}
