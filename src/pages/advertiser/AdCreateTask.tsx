import { useState, useEffect } from 'react';
import { Link } from '@/lib/router';
import { useAuth } from '@/lib/auth';
import { useToast } from '@/lib/toast';
import { adCreateTaskCampaign, getSettings, getErrorMessage } from '@/lib/api';
import { PageHeader, Spinner } from '@/components/ui';
import { formatMoney, formatXc } from '@/lib/format';
import { ListChecks, ExternalLink, Globe, FileCheck, Upload, Tag } from 'lucide-react';
import { COUNTRY_LIST, COUNTRY_NAME_MAP } from '@/lib/countries';

export function AdCreateTaskPage() {
  const { profile } = useAuth();
  const { toast } = useToast();
  const [submitting, setSubmitting] = useState(false);
  const [multiplier, setMultiplier] = useState(10);

  const [form, setForm] = useState({
    title: '',
    description: '',
    instructions: '',
    reward: '0.01',
    action_url: '',
    proof_instructions: '',
    daily_limit: '0',
    total_limit: '0',
    budget: String(profile?.advertising_balance ?? 0),
  });

  const [targetMode, setTargetMode] = useState<'worldwide' | 'countries'>('worldwide');
  const [targetCountries, setTargetCountries] = useState<string[]>([]);
  const [countrySearch, setCountrySearch] = useState('');
  const [budgetError, setBudgetError] = useState('');

  useEffect(() => {
    getSettings().then((s) => setMultiplier(s.reward_multiplier || 10)).catch(() => {});
  }, []);

  const update = (key: keyof typeof form, val: string) => {
    if (key === 'budget') {
      const valNum = parseFloat(val);
      const maxBalance = profile?.advertising_balance ?? 0;
      if (!isNaN(valNum) && valNum > maxBalance) {
        setBudgetError(`Budget cannot exceed your advertising balance (${formatMoney(maxBalance)})`);
      } else {
        setBudgetError('');
      }
    }
    setForm((f) => ({ ...f, [key]: val }));
  };

  const toggleCountry = (code: string) => {
    setTargetCountries((prev) =>
      prev.includes(code) ? prev.filter((c) => c !== code) : [...prev, code]
    );
  };

  const filteredCountries = COUNTRY_LIST.filter((c) =>
    c.name.toLowerCase().includes(countrySearch.toLowerCase()) || c.code.toLowerCase().includes(countrySearch.toLowerCase())
  );

  const rewardNum = parseFloat(form.reward);
  const budgetNum = parseFloat(form.budget);
  const estimatedCompletions =
    !isNaN(budgetNum) && budgetNum > 0 && !isNaN(rewardNum) && rewardNum > 0
      ? Math.floor(budgetNum / rewardNum)
      : null;

  const proofRequired = form.proof_instructions.trim().length > 0;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.title.trim()) { toast('Title is required', 'error'); return; }
    if (form.title.trim().length > 42) { toast('Title must be 42 characters or less', 'error'); return; }
    if (form.description.trim().length > 200) { toast('Description must be 200 characters or less', 'error'); return; }
    if (form.instructions.trim().length > 350) { toast('Instructions must be 350 characters or less', 'error'); return; }
    if (form.proof_instructions.trim().length > 350) { toast('Proof Instructions must be 350 characters or less', 'error'); return; }
    if (!form.proof_instructions.trim()) { toast('Proof Instructions is required', 'error'); return; }
    if (targetMode === 'countries' && targetCountries.length === 0) {
      toast('Select at least one country or switch to Worldwide', 'error');
      return;
    }
    const budgetVal = parseFloat(form.budget);
    if (!isNaN(budgetVal) && budgetVal > (profile?.advertising_balance ?? 0)) {
      toast('Budget exceeds your advertising balance', 'error');
      return;
    }

    setSubmitting(true);
    try {
      await adCreateTaskCampaign({
        title: form.title.trim(),
        description: form.description.trim(),
        instructions: form.instructions.trim(),
        category: 'general',
        task_type: 'custom',
        reward: parseFloat(form.reward),
        action_url: form.action_url.trim(),
        proof_required: proofRequired,
        proof_instructions: form.proof_instructions.trim(),
        proof_image_url: null,
        daily_limit: parseInt(form.daily_limit),
        total_limit: parseInt(form.total_limit),
        budget: parseFloat(form.budget),
        target_countries: targetMode === 'worldwide' ? null : targetCountries,
      });
      toast('Task campaign created! Awaiting admin approval.', 'success');
      window.location.hash = '#/advertiser/campaigns';
    } catch (err) {
      toast(getErrorMessage(err, 'Failed to create campaign'), 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const previewTitle = (form.title.trim() || 'Your Task Title').slice(0, 42);
  const previewDescription = form.description.trim() || 'Your task description will appear here...';
  const previewInstructions = form.instructions.trim() || 'Follow the task requirements and submit your proof below.';
  const previewReward = (parseFloat(form.reward) || 0) * multiplier;
  const previewTargetLabel = targetMode === 'worldwide'
    ? 'Worldwide'
    : targetCountries.length === 0
      ? 'Worldwide'
      : targetCountries.map((c) => COUNTRY_NAME_MAP[c] ?? c).join(', ');

  return (
    <div className="max-w-[1400px] mx-auto">
      <Link to="/advertiser" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
        ← Back to Advertiser Dashboard
      </Link>

      <PageHeader title="Create Task Campaign" subtitle="Pay users to complete actions on your site" />

      <div className="grid lg:grid-cols-[676px_672px] gap-6 items-start">
        <div className="card p-6">
          <form onSubmit={handleSubmit} className="flex flex-col">
            {/* Budget summary */}
            <div className="flex items-center justify-between px-3 pt-[21px] pb-[21px] rounded-lg bg-ink-800">
              <div>
                <div className="text-xs text-gray-500">Advertising Balance</div>
                <div className="text-lg font-mono font-bold text-brand-400">{formatMoney(profile?.advertising_balance ?? 0)}</div>
              </div>
              <div className="text-right">
                <div className="text-xs text-gray-500">Estimated Completions</div>
                <div className="text-lg font-mono font-bold text-gray-200">
                  {estimatedCompletions !== null ? estimatedCompletions.toLocaleString() : '–'}
                </div>
              </div>
            </div>

            <div className="mt-6">
              <label className="label flex items-center justify-between">
                <span>Task Title *</span>
                <span className="text-xs text-gray-500 font-normal">{form.title.length}/42</span>
              </label>
              <input value={form.title} onChange={(e) => update('title', e.target.value)} maxLength={42} className="input" placeholder="Visit our website and sign up" disabled={submitting} />
            </div>

            <div className="mt-6">
              <label className="label flex items-center justify-between">
                <span>Description</span>
                <span className="text-xs text-gray-500 font-normal">{form.description.length}/200</span>
              </label>
              <textarea value={form.description} onChange={(e) => update('description', e.target.value)} maxLength={200} rows={2} className="input resize-none block" placeholder="Short description shown on the task card" disabled={submitting} />
            </div>

            <div className="mt-6">
              <label className="label flex items-center justify-between">
                <span>Instructions</span>
                <span className="text-xs text-gray-500 font-normal">{form.instructions.length}/350</span>
              </label>
              <textarea value={form.instructions} onChange={(e) => update('instructions', e.target.value)} maxLength={350} rows={3} className="input resize-none block" placeholder="Step-by-step instructions for users" disabled={submitting} />
            </div>

            <div className="mt-6">
              <label className="label">Action URL</label>
              <input value={form.action_url} onChange={(e) => update('action_url', e.target.value)} className="input" placeholder="https://your-site.com/action" disabled={submitting} />
            </div>

            <div className="mt-6">
              <label className="label flex items-center justify-between">
                <span>Proof Instructions *</span>
                <span className="text-xs text-gray-500 font-normal">{form.proof_instructions.length}/350</span>
              </label>
              <textarea value={form.proof_instructions} onChange={(e) => update('proof_instructions', e.target.value)} maxLength={350} rows={2} className="input resize-none block" placeholder="Tell users what proof to submit (e.g. screenshot, username). Leave empty for auto-approval." disabled={submitting} />
              <p className="text-xs text-gray-500 mt-1.5">
                {proofRequired
                  ? 'Proof will be required — submissions go to admin review before reward is credited.'
                  : 'No proof instructions — completions are auto-approved and rewarded instantly.'}
              </p>
            </div>

            {/* Country Targeting */}
            <div className="mt-6">
              <div>
                <label className="label">Countries</label>
                <div className={`flex gap-2 ${targetMode === 'countries' ? 'mb-3' : ''}`}>
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
            </div>

            <div className="mt-6 grid grid-cols-2 gap-4">
              <div>
                <label className="label">Cost per Task</label>
                <input type="number" step="0.01" min="0.01" value={form.reward} onChange={(e) => update('reward', e.target.value)} className="input" disabled={submitting} />
              </div>
              <div>
                <label className="label">Total Budget</label>
                <input
                  type="number"
                  step="0.01"
                  min="0.01"
                  max={profile?.advertising_balance ?? 0}
                  value={form.budget}
                  onChange={(e) => update('budget', e.target.value)}
                  className="input"
                  disabled={submitting}
                />
                {budgetError && <p className="text-xs text-danger-500 mt-1">{budgetError}</p>}
              </div>
            </div>

            <div className="mt-6 grid grid-cols-2 gap-4">
              <div>
                <label className="label">Daily Limit (0 = unlimited)</label>
                <input type="number" min="0" value={form.daily_limit} onChange={(e) => update('daily_limit', e.target.value)} className="input" disabled={submitting} />
              </div>
              <div>
                <label className="label">Total Limit (0 = unlimited)</label>
                <input type="number" min="0" value={form.total_limit} onChange={(e) => update('total_limit', e.target.value)} className="input" disabled={submitting} />
              </div>
            </div>

            <div className="mt-6 p-3 rounded-lg bg-brand-500/5 border border-brand-500/20 text-xs text-gray-400">
              Campaign will be submitted for admin approval. If proof instructions are provided, each submission will be reviewed by admin before reward is credited. Budget is deducted from your advertising balance immediately and held until the campaign completes or is stopped.
            </div>

            <button type="submit" disabled={submitting} className="mt-6 btn-primary w-full">
              {submitting ? <Spinner size={18} /> : <><ListChecks size={18} /> Create Task Campaign</>}
            </button>
          </form>
        </div>

        {/* Live Preview Panel */}
        <div className="lg:sticky lg:top-4">
          <div className="text-sm font-semibold text-gray-300 mb-3">Live Preview</div>
          <div className="card p-6 overflow-hidden">
            <div className="flex items-start justify-between gap-4 mb-4">
              <div className="flex items-center gap-3 min-w-0 flex-1">
                <div className="w-12 h-12 rounded-xl bg-brand-500/10 text-brand-400 flex items-center justify-center">
                  <FileCheck size={20} />
                </div>
                <div className="min-w-0">
                  <h2 className="text-lg font-bold text-gray-100 break-words">{previewTitle}</h2>
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-gray-500">Reward</div>
                <div className="text-xl font-mono font-bold text-brand-400">{formatXc(previewReward)} <span className="text-[10px] text-gray-500">XC</span></div>
              </div>
            </div>

            <p className="text-sm text-gray-400 mb-4 break-words">{previewDescription}</p>

            {/* Instructions */}
            <div className="p-4 rounded-lg bg-ink-800 mb-4">
              <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Instructions</h3>
              <p className="text-sm text-gray-300 whitespace-pre-wrap break-words">{previewInstructions}</p>
            </div>

            {/* Proof Required */}
            {proofRequired && (
              <div className="p-4 rounded-lg bg-brand-500/5 border border-brand-500/20 mb-4">
                <h3 className="text-xs font-semibold text-brand-400 uppercase tracking-wide mb-2 flex items-center gap-1.5">
                  <Upload size={12} /> Proof Required
                </h3>
                <p className="text-sm text-gray-400 break-words">{form.proof_instructions.trim()}</p>
              </div>
            )}

            {/* Action URL */}
            {form.action_url.trim() && (
              <a
                href={form.action_url.trim()}
                target="_blank"
                rel="noopener noreferrer"
                className="btn-secondary w-full mb-4"
              >
                <ExternalLink size={16} /> Open Task Link
              </a>
            )}

            {/* Meta */}
            <div className="space-y-2 text-xs text-gray-500 mt-4 pt-4 border-t border-ink-700">
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-1"><Tag size={12} /> Budget</span>
                <span className="font-mono text-gray-300">{formatMoney(budgetNum || 0)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span>Estimated Completions</span>
                <span className="font-mono text-gray-300">
                  {estimatedCompletions !== null ? estimatedCompletions.toLocaleString() : '–'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="flex items-center gap-1"><Globe size={12} /> Targeting</span>
                <span className="text-gray-300 text-right max-w-[60%] truncate">{previewTargetLabel}</span>
              </div>
            </div>
          </div>

          <div className="w-[504px] max-w-full">
          <div className="text-sm font-semibold text-gray-300 mb-3 mt-6">Campaign Summary</div>
          <div className="card p-6">
            <div className="space-y-2 text-xs text-gray-500">
              <div className="flex items-center justify-between">
                <span>Cost per Task</span>
                <span className="font-mono text-gray-300">{formatMoney(rewardNum || 0)}</span>
              </div>
              <div className="flex items-center justify-between">
                <span>Estimated Completions</span>
                <span className="font-mono text-gray-300">
                  {estimatedCompletions !== null ? estimatedCompletions.toLocaleString() : '–'}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span>Countries</span>
                <span className="text-gray-300 text-right max-w-[60%] truncate">{previewTargetLabel}</span>
              </div>
              <div className="flex items-center justify-between">
                <span>Proof</span>
                <span className={proofRequired ? 'text-brand-400' : 'text-gray-300'}>
                  {proofRequired ? 'Required' : 'Not required'}
                </span>
              </div>
            </div>

            <div className="space-y-2 text-xs text-gray-500 mt-4 pt-4 border-t border-ink-700">
              <div className="flex items-center justify-between">
                <span>Daily Limit</span>
                <span className="font-mono text-gray-300">
                  {form.daily_limit === '0' ? 'Unlimited' : form.daily_limit}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span>Total Limit</span>
                <span className="font-mono text-gray-300">
                  {form.total_limit === '0' ? 'Unlimited' : form.total_limit}
                </span>
              </div>
            </div>

            <div className="mt-4 pt-4 border-t border-ink-700">
              <div className="flex items-center justify-between text-xs">
                <span className="text-gray-500">Budget</span>
                <span className="font-mono font-bold text-lg text-brand-400">{formatMoney(budgetNum || 0)}</span>
              </div>
            </div>
          </div>
          </div>
        </div>
      </div>
    </div>
  );
}
