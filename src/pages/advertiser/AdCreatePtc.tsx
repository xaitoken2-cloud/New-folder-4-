import { useState, useEffect } from 'react';
import { Link } from '@/lib/router';
import { useAuth } from '@/lib/auth';
import { useToast } from '@/lib/toast';
import { adCreatePtcCampaign, uploadCampaignImage, getSettings, getErrorMessage } from '@/lib/api';
import { PageHeader, Spinner } from '@/components/ui';
import { PtcAdCard } from '@/components/PtcAdCard';
import { formatMoney, formatXc } from '@/lib/format';
import { MousePointerClick, Image as ImageIcon, Globe, Smartphone, Monitor, Tablet, Upload } from 'lucide-react';
import { COUNTRY_LIST } from '@/lib/countries';
import { CAMPAIGN_CATEGORIES } from '@/lib/categories';

const ALL_DEVICES = ['desktop', 'mobile', 'tablet'];

export function AdCreatePtcPage() {
  const { profile } = useAuth();
  const { toast } = useToast();
  const [submitting, setSubmitting] = useState(false);

  const [form, setForm] = useState({
    title: '',
    description: '',
    advertiser: '',
    category: 'general',
    reward: '0.005',
    duration_seconds: '10',
    destination_url: '',
    image_url: '',
    daily_view_limit: '0',
    total_view_limit: '0',
    budget: '1.00',
  });

  const [targetMode, setTargetMode] = useState<'worldwide' | 'countries'>('worldwide');
  const [targetCountries, setTargetCountries] = useState<string[]>([]);
  const [targetDevices, setTargetDevices] = useState<string[]>(ALL_DEVICES);
  const [countrySearch, setCountrySearch] = useState('');
  const [imageMode, setImageMode] = useState<'url' | 'upload'>('url');
  const [uploadingImage, setUploadingImage] = useState(false);
  const [multiplier, setMultiplier] = useState(10);

  useEffect(() => {
    getSettings().then((s) => setMultiplier(s.reward_multiplier || 10)).catch(() => {});
  }, []);

  useEffect(() => {
    if (profile?.advertising_balance !== undefined && profile.advertising_balance > 0) {
      setForm((f) => ({ ...f, budget: profile.advertising_balance.toFixed(2) }));
    }
  }, [profile?.advertising_balance]);

  const update = (key: keyof typeof form, val: string) => setForm((f) => ({ ...f, [key]: val }));

  const estimatedViews = parseFloat(form.budget) > 0 && parseFloat(form.reward) > 0
    ? Math.floor(parseFloat(form.budget) / parseFloat(form.reward))
    : 0;

  const rewardNum = parseFloat(form.reward);
  const durationNum = parseInt(form.duration_seconds);
  const earningRate = Number.isFinite(rewardNum) && Number.isFinite(durationNum) && durationNum > 0
    ? rewardNum / durationNum
    : 0;

  const toggleCountry = (code: string) => {
    setTargetCountries((prev) =>
      prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code]
    );
  };

  const toggleDevice = (device: string) => {
    setTargetDevices((prev) => {
      if (prev.length === ALL_DEVICES.length) return [device];
      return prev.includes(device) ? prev.filter((d) => d !== device) : [...prev, device];
    });
  };

  const allDevicesActive = targetDevices.length === ALL_DEVICES.length;

  const filteredCountries = COUNTRY_LIST.filter((c) =>
    c.name.toLowerCase().includes(countrySearch.toLowerCase()) || c.code.toLowerCase().includes(countrySearch.toLowerCase())
  );

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.title.trim()) { toast('Title is required', 'error'); return; }
    if (form.title.trim().length > 50) { toast('Title must be 50 characters or less', 'error'); return; }
    if (form.description.trim().length > 200) { toast('Description must be 200 characters or less', 'error'); return; }
    if (!form.destination_url.trim()) { toast('Destination URL is required', 'error'); return; }
    if (targetMode === 'countries' && targetCountries.length === 0) {
      toast('Select at least one country or switch to Worldwide', 'error');
      return;
    }
    if (targetDevices.length === 0) { toast('Select at least one device type', 'error'); return; }

    setSubmitting(true);
    try {
      await adCreatePtcCampaign({
        title: form.title.trim(),
        description: form.description.trim(),
        advertiser: form.advertiser.trim() || profile?.username || '',
        category: form.category,
        reward: parseFloat(form.reward),
        duration_seconds: parseInt(form.duration_seconds),
        destination_url: form.destination_url.trim(),
        image_url: form.image_url.trim(),
        daily_view_limit: parseInt(form.daily_view_limit),
        total_view_limit: parseInt(form.total_view_limit),
        budget: parseFloat(form.budget),
        target_countries: targetMode === 'worldwide' ? null : targetCountries,
        target_devices: allDevicesActive ? ALL_DEVICES : targetDevices,
      });
      toast('PTC campaign created! Awaiting admin approval.', 'success');
      window.location.hash = '#/advertiser/campaigns';
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to create campaign'), 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const previewProps = {
    title: (form.title.trim() || 'Your Ad Title').slice(0, 50),
    description: (form.description.trim() || 'Your advertisement description will appear here...').slice(0, 200),
    advertiser: form.advertiser.trim() || 'Your Brand',
    category: form.category,
    image_url: form.image_url.trim(),
    reward: (parseFloat(form.reward) || 0) * multiplier,
    duration_seconds: parseInt(form.duration_seconds) || 0,
  };

  return (
    <div className="max-w-[1400px] mx-auto">
      <Link to="/advertiser" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
        ← Back to Advertiser Dashboard
      </Link>

      <PageHeader title="Create PTC Campaign" subtitle="Pay-per-view advertisement with server-verified viewing" />

      <div className="grid lg:grid-cols-[676px_672px] gap-6 items-start">
      <div className="card p-6">
        {/* Budget summary */}
        <div className="flex items-center justify-between px-3 pt-[21px] pb-[21px] rounded-lg bg-ink-800">
          <div>
            <div className="text-xs text-gray-500">Advertising Balance</div>
            <div className="text-lg font-mono font-bold text-brand-400">{formatMoney(profile?.advertising_balance ?? 0)}</div>
          </div>
          <div className="text-right">
            <div className="text-xs text-gray-500">Estimated Views</div>
            <div className="text-lg font-mono font-bold text-gray-200">{estimatedViews.toLocaleString()}</div>
          </div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6 mt-6">
          <div>
            <label className="label flex items-center justify-between">
              <span>Campaign Title *</span>
              <span className="text-xs text-gray-500 font-normal">{form.title.length}/50</span>
            </label>
            <input value={form.title} onChange={(e) => update('title', e.target.value)} maxLength={50} className="input" placeholder="My Awesome Product" disabled={submitting} />
          </div>

          <div>
            <label className="label flex items-center justify-between">
              <span>Description</span>
              <span className="text-xs text-gray-500 font-normal">{form.description.length}/200</span>
            </label>
            <textarea value={form.description} onChange={(e) => update('description', e.target.value)} maxLength={200} rows={2} className="input resize-none block" placeholder="Short description shown on the ad card" disabled={submitting} />
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="label">Advertiser Name</label>
              <input value={form.advertiser} onChange={(e) => update('advertiser', e.target.value)} className="input" placeholder="Your brand" disabled={submitting} />
            </div>
            <div>
              <label className="label">Category</label>
              <select value={form.category} onChange={(e) => update('category', e.target.value)} className="input" disabled={submitting}>
                {CAMPAIGN_CATEGORIES.map((c) => (
                  <option key={c.value} value={c.value}>{c.label}</option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label className="label">Campaign URL *</label>
            <input value={form.destination_url} onChange={(e) => update('destination_url', e.target.value)} className="input" placeholder="https://your-site.com" disabled={submitting} />
          </div>

          <div>
            <label className="label">Banner Image (Optional)</label>
            <div className="flex gap-2 mb-3">
              <button
                type="button"
                onClick={() => setImageMode('url')}
                className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition flex items-center justify-center gap-1.5 ${imageMode === 'url' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
              >
                <ImageIcon size={14} /> Image URL
              </button>
              <button
                type="button"
                onClick={() => setImageMode('upload')}
                className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition flex items-center justify-center gap-1.5 ${imageMode === 'upload' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
              >
                <Upload size={14} /> Upload Image
              </button>
            </div>

            {imageMode === 'url' ? (
              <input value={form.image_url} onChange={(e) => update('image_url', e.target.value)} className="input" placeholder="https://your-site.com/banner.jpg" disabled={submitting} />
            ) : (
              <div>
                <div className="flex items-center gap-2">
                  <input
                    type="file"
                    accept="image/jpeg,image/png,image/webp,image/gif"
                    className="input text-sm file:mr-3 file:py-1.5 file:px-3 file:rounded-md file:border-0 file:text-xs file:font-medium file:bg-brand-500/15 file:text-brand-400 file:cursor-pointer"
                    disabled={uploadingImage || submitting}
                    onChange={async (e) => {
                      const file = e.target.files?.[0];
                      if (!file) return;
                      if (file.size > 2097152) {
                        toast('Image must be under 2 MB', 'error');
                        e.target.value = '';
                        return;
                      }
                      setUploadingImage(true);
                      try {
                        const url = await uploadCampaignImage(file);
                        update('image_url', url);
                      } catch (err) {
                        toast(getErrorMessage(err, 'Failed to upload image'), 'error');
                      } finally {
                        setUploadingImage(false);
                      }
                    }}
                  />
                  {uploadingImage && <Spinner size={18} />}
                </div>
                {form.image_url && !uploadingImage && (
                  <img src={form.image_url} alt="Banner preview" className="mt-2 rounded-lg max-h-20 object-cover border border-ink-700" />
                )}
              </div>
            )}
            <p className="text-xs text-gray-500 mt-1.5 flex items-center gap-1">
              <ImageIcon size={11} /> Optional banner image shown on the ad
            </p>
          </div>

          {/* Targeting Section */}
          <div>
            {/* Country targeting */}
            <div className="mb-5">
              <label className="label">Countries</label>
              <div className="flex gap-2 mb-3">
                <button
                  type="button"
                  onClick={() => setTargetMode('worldwide')}
                  className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition flex items-center justify-center gap-1.5 ${targetMode === 'worldwide' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  <Globe size={14} /> Worldwide
                </button>
                <button
                  type="button"
                  onClick={() => setTargetMode('countries')}
                  className={`flex-1 py-2 px-3 rounded-lg text-sm font-medium border transition ${targetMode === 'countries' ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  Select Countries
                </button>
              </div>

              {targetMode === 'countries' && (
                <div>
                  <input
                    value={countrySearch}
                    onChange={(e) => setCountrySearch(e.target.value)}
                    placeholder="Search countries..."
                    className="input mb-2"
                  />
                  <div className="max-h-40 overflow-y-auto rounded-lg border border-ink-700 bg-ink-800 p-2">
                    <div className="flex flex-wrap gap-1.5">
                      {filteredCountries.map((c) => (
                        <button
                          key={c.code}
                          type="button"
                          onClick={() => toggleCountry(c.code)}
                          className={`px-2.5 py-1 rounded-md text-xs font-medium border transition ${targetCountries.includes(c.code) ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-700'}`}
                        >
                          {c.name}
                        </button>
                      ))}
                    </div>
                  </div>
                  {targetCountries.length > 0 && (
                    <p className="text-xs text-gray-500 mt-1.5">{targetCountries.length} selected</p>
                  )}
                </div>
              )}
            </div>

            {/* Device targeting */}
            <div>
              <label className="label">Devices</label>
              <div className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => setTargetDevices(ALL_DEVICES)}
                  className={`px-3 py-2 rounded-lg text-sm font-medium border transition flex items-center gap-1.5 ${allDevicesActive ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  All Devices
                </button>
                <button
                  type="button"
                  onClick={() => toggleDevice('desktop')}
                  className={`px-3 py-2 rounded-lg text-sm font-medium border transition flex items-center gap-1.5 ${targetDevices.includes('desktop') && !allDevicesActive ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  <Monitor size={14} /> Desktop
                </button>
                <button
                  type="button"
                  onClick={() => toggleDevice('mobile')}
                  className={`px-3 py-2 rounded-lg text-sm font-medium border transition flex items-center gap-1.5 ${targetDevices.includes('mobile') && !allDevicesActive ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  <Smartphone size={14} /> Mobile
                </button>
                <button
                  type="button"
                  onClick={() => toggleDevice('tablet')}
                  className={`px-3 py-2 rounded-lg text-sm font-medium border transition flex items-center gap-1.5 ${targetDevices.includes('tablet') && !allDevicesActive ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                >
                  <Tablet size={14} /> Tablet
                </button>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-3 gap-4">
            <div>
              <label className="label">Cost per view</label>
              <input type="number" step="0.005" min="0.005" value={form.reward} onChange={(e) => update('reward', e.target.value)} className="input" disabled={submitting} />
            </div>
            <div>
              <label className="label">Duration (sec)</label>
              <div className="flex flex-wrap gap-2">
                {['10', '15', '20', '30', '60', '90', '120'].map((sec) => (
                  <button
                    key={sec}
                    type="button"
                    onClick={() => update('duration_seconds', sec)}
                    className={`px-3 py-2 rounded-lg text-sm font-medium border transition flex items-center gap-1.5 ${form.duration_seconds === sec ? 'bg-brand-500/15 border-brand-500 text-brand-400' : 'border-ink-700 text-gray-400 hover:bg-ink-800'}`}
                  >
                    {sec} sec
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="label">Total Budget</label>
              <input type="number" step="0.01" min="0.01" value={form.budget} onChange={(e) => update('budget', e.target.value)} className="input" disabled={submitting} />
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="label">Daily View Limit (0 = unlimited)</label>
              <input type="number" min="0" value={form.daily_view_limit} onChange={(e) => update('daily_view_limit', e.target.value)} className="input" disabled={submitting} />
            </div>
            <div>
              <label className="label">Total View Limit (0 = unlimited)</label>
              <input type="number" min="0" value={form.total_view_limit} onChange={(e) => update('total_view_limit', e.target.value)} className="input" disabled={submitting} />
            </div>
          </div>

          <div className="p-3 rounded-lg bg-brand-500/5 border border-brand-500/20 text-xs text-gray-400">
            Campaign will be submitted for admin approval. Once approved, it goes live and users can start viewing.
            Budget is deducted from your advertising balance immediately and held until the campaign completes or is stopped.
          </div>

          <button type="submit" disabled={submitting} className="btn-primary w-full">
            {submitting ? <Spinner size={18} /> : <><MousePointerClick size={18} /> Create PTC Campaign</>}
          </button>
        </form>
      </div>

      <div className="lg:sticky lg:top-4">
        <div className="text-sm font-semibold text-gray-300 mb-3">Live Preview</div>
        <PtcAdCard {...previewProps} interactive={false} ctaLabel="Start Viewing" />

        <div className="w-[504px] max-w-full">
        <div className="text-sm font-semibold text-gray-300 mb-3 mt-6">Campaign Summary</div>
        <div className="card p-6">
          <div className="space-y-2 text-xs text-gray-500">
            <div className="flex items-center justify-between">
              <span>Estimated Views</span>
              <span className="font-mono text-gray-300">{estimatedViews.toLocaleString()}</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Cost per View</span>
              <span className="font-mono text-gray-300">{formatMoney(parseFloat(form.reward) || 0)}</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Duration</span>
              <span className="font-mono text-gray-300">{`${form.duration_seconds}s`}</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Earning Rate</span>
              <span className="font-mono text-gray-300">{`$${earningRate.toFixed(4)}/sec`}</span>
            </div>
            <div className="flex items-center justify-between">
              <span>Devices</span>
              <span className="text-gray-300 text-right max-w-[60%] truncate">
                {allDevicesActive ? 'All Devices' : targetDevices.map((d) => d.charAt(0).toUpperCase() + d.slice(1)).join(', ')}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span>Countries</span>
              <span className="text-gray-300 text-right max-w-[60%] truncate">
                {targetMode === 'worldwide' || targetCountries.length === 0
                  ? 'Worldwide'
                  : targetCountries.map((code) => COUNTRY_LIST.find((c) => c.code === code)?.name ?? code).join(', ')}
              </span>
            </div>
          </div>

          <div className="space-y-2 text-xs text-gray-500 mt-4 pt-4 border-t border-ink-700">
            <div className="flex items-center justify-between">
              <span>Watcher earns / view</span>
              <span className="font-mono text-gray-300">{formatXc(previewProps.reward)} XC</span>
            </div>
          </div>

          <div className="mt-4 pt-4 border-t border-ink-700">
            <div className="flex items-center justify-between text-xs">
              <span className="text-gray-500">Budget</span>
              <span className="font-mono font-bold text-lg text-brand-400">{formatMoney(parseFloat(form.budget) || 0)}</span>
            </div>
          </div>
        </div>
        </div>
      </div>
      </div>
    </div>
  );
}
