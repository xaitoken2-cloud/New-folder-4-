import { useEffect, useState, useCallback } from 'react';
import { Link, useRouter } from '@/lib/router';
import {
  getPublicProfile, followUser, unfollowUser, listFollowers, listFollowing, getErrorMessage,
} from '@/lib/api';
import { LoadingScreen, ErrorState, PageHeader, Modal, EmptyState, Spinner } from '@/components/ui';
import { formatXc, formatDate, timeAgo } from '@/lib/format';
import {
  MapPin, Calendar, Coins, Users, UserPlus, UserMinus, MessageSquare, ArrowLeft,
  CircleDot, Search,
} from 'lucide-react';
import { useToast } from '@/lib/toast';
import type { PublicProfile, FollowListRow } from '@/types';

function Avatar({ username, avatarUrl, size = 80 }: { username: string; avatarUrl?: string | null; size?: number }) {
  if (avatarUrl) {
    return <img src={avatarUrl} alt="" className="rounded-full object-cover" style={{ width: size, height: size }} />;
  }
  return (
    <div
      className="rounded-full bg-gradient-to-br from-brand-500/20 to-brand-700/20 flex items-center justify-center text-brand-400 font-bold"
      style={{ width: size, height: size, fontSize: size * 0.35 }}
    >
      {username.charAt(0).toUpperCase()}
    </div>
  );
}

function OnlineIndicator({ lastSeenAt }: { lastSeenAt: string | null | undefined }) {
  if (!lastSeenAt) {
    return (
      <span className="inline-flex items-center gap-1.5 text-xs text-gray-500">
        <CircleDot size={10} className="text-gray-600" /> offline
      </span>
    );
  }
  const diff = Date.now() - new Date(lastSeenAt).getTime();
  const isOnline = diff < 5 * 60 * 1000;
  return (
    <span className="inline-flex items-center gap-1.5 text-xs">
      <CircleDot size={10} className={isOnline ? 'text-success-500' : 'text-gray-600'} />
      <span className={isOnline ? 'text-success-500' : 'text-gray-500'}>
        {isOnline ? 'online' : `last seen ${timeAgo(lastSeenAt)}`}
      </span>
    </span>
  );
}

function FollowListModal({
  open, onClose, title, username, mode,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  username: string;
  mode: 'followers' | 'following';
}) {
  const { navigate } = useRouter();
  const [rows, setRows] = useState<FollowListRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [offset, setOffset] = useState(0);
  const [hasMore, setHasMore] = useState(false);

  const load = useCallback(async (newOffset: number) => {
    setLoading(true);
    setError('');
    try {
      const fetcher = mode === 'followers' ? listFollowers : listFollowing;
      const data = await fetcher(username, 50, newOffset);
      if (newOffset === 0) {
        setRows(data);
      } else {
        setRows((prev) => [...prev, ...data]);
      }
      setHasMore(data.length === 50);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load list'));
    } finally {
      setLoading(false);
    }
  }, [username, mode]);

  useEffect(() => {
    if (open) {
      setRows([]);
      setOffset(0);
      load(0);
    }
  }, [open, load]);

  const handleLoadMore = () => {
    const next = offset + 50;
    setOffset(next);
    load(next);
  };

  const handleNavigate = (uname: string) => {
    onClose();
    navigate(`/profile/${uname}`);
  };

  return (
    <Modal open={open} onClose={onClose} title={title} maxWidth="max-w-md">
      {loading && rows.length === 0 ? (
        <div className="flex justify-center py-8"><Spinner size={24} /></div>
      ) : error ? (
        <ErrorState message={error} onRetry={() => load(offset)} />
      ) : rows.length === 0 ? (
        <EmptyState
          title={mode === 'followers' ? 'No followers yet' : 'Not following anyone yet'}
          message={mode === 'followers' ? 'This user has no followers.' : 'This user is not following anyone.'}
          icon={<Users size={24} />}
        />
      ) : (
        <>
          <div className="space-y-1">
            {rows.map((r) => (
              <button
                key={r.username}
                onClick={() => handleNavigate(r.username)}
                className="w-full flex items-center gap-3 p-2.5 rounded-lg hover:bg-ink-800 transition-colors text-left"
              >
                <Avatar username={r.username} avatarUrl={r.avatar_url} size={36} />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-gray-200 truncate">@{r.username}</div>
                  {r.is_following && (
                    <div className="text-xs text-brand-400">Following</div>
                  )}
                </div>
              </button>
            ))}
          </div>
          {hasMore && (
            <div className="mt-4 text-center">
              <button onClick={handleLoadMore} disabled={loading} className="btn-secondary text-sm">
                {loading ? <Spinner size={16} /> : 'Load more'}
              </button>
            </div>
          )}
        </>
      )}
    </Modal>
  );
}

export function PublicProfilePage({ username }: { username: string }) {
  const { navigate } = useRouter();
  const { toast } = useToast();
  const [profile, setProfile] = useState<PublicProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [followPending, setFollowPending] = useState(false);
  const [showFollowers, setShowFollowers] = useState(false);
  const [showFollowing, setShowFollowing] = useState(false);

  const load = useCallback(async () => {
    setError('');
    setLoading(true);
    try {
      const data = await getPublicProfile(username);
      setProfile(data);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load profile'));
    } finally {
      setLoading(false);
    }
  }, [username]);

  useEffect(() => { load(); }, [load]);

  const handleFollow = async () => {
    if (!profile || profile.is_self) return;
    setFollowPending(true);
    const wasFollowing = profile.is_following;
    setProfile((p) => p ? {
      ...p,
      is_following: !wasFollowing,
      follower_count: (p.follower_count ?? 0) + (wasFollowing ? -1 : 1),
    } : p);
    try {
      const result = wasFollowing
        ? await unfollowUser(username)
        : await followUser(username);
      setProfile((p) => p ? { ...p, follower_count: result.follower_count } : p);
    } catch (err) {
      setProfile((p) => p ? {
        ...p,
        is_following: wasFollowing,
        follower_count: (p.follower_count ?? 0) + (wasFollowing ? 1 : -1),
      } : p);
      toast(getErrorMessage(err, 'Failed to update follow status'), 'error');
    } finally {
      setFollowPending(false);
    }
  };

  if (loading) return <LoadingScreen label="Loading profile..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!profile || !profile.found) {
    return (
      <div>
        <PageHeader title="Profile" />
        <EmptyState
          title="User not found"
          message={`@${username} doesn't exist or the username is incorrect.`}
          icon={<Users size={24} />}
        />
      </div>
    );
  }

  return (
    <div>
      <div className="mb-4">
        <button
          onClick={() => navigate('/referrals')}
          className="inline-flex items-center gap-1.5 text-sm text-gray-500 hover:text-gray-300 transition-colors"
        >
          <ArrowLeft size={16} /> Back
        </button>
      </div>

      <div className="card p-6 mb-5 sm:mb-6">
        <div className="flex flex-col sm:flex-row items-center sm:items-start gap-5">
          <Avatar username={profile.username ?? ''} avatarUrl={profile.avatar_url} size={88} />
          <div className="flex-1 min-w-0 text-center sm:text-left">
            <h1 className="text-lg sm:text-xl font-bold text-gray-100 truncate">
              @{profile.username}
            </h1>
            {profile.bio && (
              <p className="text-sm text-gray-400 mt-2 max-w-md">{profile.bio}</p>
            )}
            <div className="mt-3">
              <OnlineIndicator lastSeenAt={profile.last_seen_at} />
            </div>
            <div className="flex flex-wrap items-center justify-center sm:justify-start gap-4 mt-3 text-sm text-gray-400">
              {profile.country && (
                <span className="inline-flex items-center gap-1.5">
                  <MapPin size={14} className="text-gray-500" /> {profile.country}
                </span>
              )}
              <span className="inline-flex items-center gap-1.5">
                <Calendar size={14} className="text-gray-500" /> Joined {formatDate(profile.created_at)}
              </span>
              <span className="inline-flex items-center gap-1.5">
                <Coins size={14} className="text-brand-400" /> {formatXc(profile.xc_balance)} XC
              </span>
            </div>
          </div>
          {!profile.is_self && (
            <div className="flex gap-2 shrink-0">
              <button
                onClick={handleFollow}
                disabled={followPending}
                className={profile.is_following ? 'btn-secondary text-sm' : 'btn-primary text-sm'}
              >
                {followPending ? (
                  <Spinner size={16} />
                ) : profile.is_following ? (
                  <><UserMinus size={16} /> Unfollow</>
                ) : (
                  <><UserPlus size={16} /> Follow</>
                )}
              </button>
              <button
                disabled
                title="Messaging coming in a future update"
                className="btn-secondary text-sm opacity-50 cursor-not-allowed"
              >
                <MessageSquare size={16} /> Message
              </button>
            </div>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:gap-4 mb-5 sm:mb-6">
        <button
          onClick={() => setShowFollowers(true)}
          className="stat-card text-left hover:border-brand-500/30 transition-colors"
        >
          <div className="flex items-start justify-between mb-2">
            <span className="text-[10px] sm:text-xs font-medium text-gray-500 uppercase tracking-wide">Followers</span>
            <div className="w-8 h-8 rounded-lg bg-brand-500/10 flex items-center justify-center">
              <Users size={16} className="text-brand-400" />
            </div>
          </div>
          <div className="text-lg sm:text-2xl font-bold text-gray-100 font-mono">
            {profile.follower_count ?? 0}
          </div>
        </button>
        <button
          onClick={() => setShowFollowing(true)}
          className="stat-card text-left hover:border-brand-500/30 transition-colors"
        >
          <div className="flex items-start justify-between mb-2">
            <span className="text-[10px] sm:text-xs font-medium text-gray-500 uppercase tracking-wide">Following</span>
            <div className="w-8 h-8 rounded-lg bg-ink-800 flex items-center justify-center">
              <Users size={16} className="text-gray-400" />
            </div>
          </div>
          <div className="text-lg sm:text-2xl font-bold text-gray-100 font-mono">
            {profile.following_count ?? 0}
          </div>
        </button>
      </div>

      <FollowListModal
        open={showFollowers}
        onClose={() => setShowFollowers(false)}
        title={`@${profile.username}'s Followers`}
        username={profile.username ?? ''}
        mode="followers"
      />
      <FollowListModal
        open={showFollowing}
        onClose={() => setShowFollowing(false)}
        title={`@${profile.username} is Following`}
        username={profile.username ?? ''}
        mode="following"
      />
    </div>
  );
}
