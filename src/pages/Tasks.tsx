import { useEffect, useState } from 'react';
import { Link } from '@/lib/router';
import { listTasks, getTask, getMyTaskCompletions, submitTask, getSettings, getErrorMessage } from '@/lib/api';
import { useToast } from '@/lib/toast';
import { LoadingScreen, ErrorState, PageHeader, EmptyState, Badge, Spinner } from '@/components/ui';
import { formatMoney, formatXc } from '@/lib/format';
import {
  ListChecks, ExternalLink, CheckCircle2, Clock, Tag,
  Globe, UserPlus, Share2, Smartphone, FileText, Upload, FileCheck,
} from 'lucide-react';
import type { Task, TaskCompletion } from '@/types';

const taskTypeIcons: Record<string, React.ReactNode> = {
  visit_website: <Globe size={16} />,
  registration: <UserPlus size={16} />,
  social_follow: <Share2 size={16} />,
  app_install: <Smartphone size={16} />,
  survey: <FileText size={16} />,
  submit_proof: <Upload size={16} />,
  custom: <FileCheck size={16} />,
};

export function TasksListPage() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [completions, setCompletions] = useState<TaskCompletion[]>([]);
  const [multiplier, setMultiplier] = useState(10);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [taskList, compList, settings] = await Promise.all([listTasks(), getMyTaskCompletions(), getSettings()]);
      setTasks(taskList);
      setCompletions(compList);
      setMultiplier(settings.reward_multiplier || 10);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load tasks'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  if (loading) return <LoadingScreen label="Loading tasks..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;

  const completedMap = new Map(completions.map((c) => [c.task_id, c.status]));

  return (
    <div>
      <PageHeader title="Tasks" subtitle="Complete actions to earn rewards" />
      {tasks.length === 0 ? (
        <EmptyState
          title="No tasks available"
          message="New tasks will appear here when available."
          icon={<ListChecks size={24} />}
        />
      ) : (
        <div className="grid sm:grid-cols-2 gap-4">
          {tasks.map((task) => {
            const status = completedMap.get(task.id);
            return (
              <Link key={task.id} to={`/tasks/${task.id}`}>
                <div className="card card-hover p-5 h-full">
                  <div className="flex items-center justify-between mb-3">
                    <div className="flex items-center gap-2.5">
                      <div className="w-9 h-9 rounded-lg bg-brand-500/10 text-brand-400 flex items-center justify-center shrink-0">
                        {taskTypeIcons[task.task_type] ?? <FileCheck size={16} />}
                      </div>
                      <h3 className="text-sm font-semibold text-gray-100">{task.title}</h3>
                    </div>
                    <span className="text-base font-mono font-bold text-brand-400 shrink-0">{(task.reward * multiplier).toFixed(2)} <span className="text-[10px] text-gray-500">XC</span></span>
                  </div>
                  <p className="text-xs text-gray-500 mb-3 line-clamp-2">{task.description}</p>
                  <div className="flex items-center justify-between">
                    <span className="flex items-center gap-1 text-xs text-gray-500">
                      <Tag size={12} /> {task.category}
                    </span>
                    {status === 'approved' && <Badge variant="success"><CheckCircle2 size={11} /> Completed</Badge>}
                    {status === 'pending' && <Badge variant="warning"><Clock size={11} /> Pending</Badge>}
                    {status === 'rejected' && <Badge variant="danger">Rejected</Badge>}
                    {!status && <span className="text-xs text-brand-400 font-medium">Start →</span>}
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function TaskDetailPage({ taskId }: { taskId: string }) {
  const { toast } = useToast();
  const [task, setTask] = useState<Task | null>(null);
  const [completions, setCompletions] = useState<TaskCompletion[]>([]);
  const [multiplier, setMultiplier] = useState(10);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [proofText, setProofText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<{ status: string; reward?: number } | null>(null);

  const load = async () => {
    setError('');
    setLoading(true);
    try {
      const [t, comps, settings] = await Promise.all([getTask(taskId), getMyTaskCompletions(), getSettings()]);
      setTask(t);
      setCompletions(comps);
      setMultiplier(settings.reward_multiplier || 10);
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to load task'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, [taskId]);

  if (loading) return <LoadingScreen label="Loading task..." />;
  if (error) return <ErrorState message={error} onRetry={load} />;
  if (!task) return <ErrorState message="Task not found" />;

  const myCompletion = completions.find((c) => c.task_id === taskId);

  const handleSubmit = async () => {
    if (task.proof_required && !proofText.trim()) {
      toast('Please provide the required proof', 'error');
      return;
    }
    setSubmitting(true);
    setError('');
    try {
      const res = await submitTask(taskId, proofText);
      setResult({ status: res.status, reward: res.reward });
      if (res.status === 'approved') {
        toast(`Task approved! You earned ${formatXc(res.reward ?? 0)} XC`, 'success');
      } else {
        toast('Task submitted! Waiting for admin review.', 'success');
      }
    } catch (err) {
      setError(getErrorMessage(err, 'Failed to submit task'));
    } finally {
      setSubmitting(false);
    }
  };

  const isDone = myCompletion?.status === 'approved' || result?.status === 'approved';
  const isPending = myCompletion?.status === 'pending' || result?.status === 'pending';
  const isRejected = myCompletion?.status === 'rejected';

  return (
    <div className="max-w-2xl mx-auto">
      <Link to="/tasks" className="text-sm text-gray-500 hover:text-gray-300 mb-4 inline-flex items-center gap-1">
        ← Back to Tasks
      </Link>

      <div className="card p-6">
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="w-12 h-12 rounded-xl bg-brand-500/10 text-brand-400 flex items-center justify-center">
              {taskTypeIcons[task.task_type] ?? <FileCheck size={20} />}
            </div>
            <div>
              <h2 className="text-lg font-bold text-gray-100">{task.title}</h2>
            </div>
          </div>
          <div className="text-right">
            <div className="text-xs text-gray-500">Reward</div>
            <div className="text-xl font-mono font-bold text-brand-400">{formatXc(task.reward * multiplier)} <span className="text-[10px] text-gray-500">XC</span></div>
          </div>
        </div>

        <p className="text-sm text-gray-400 mb-4">{task.description}</p>

        {/* Instructions */}
        <div className="p-4 rounded-lg bg-ink-800 mb-4">
          <h3 className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2">Instructions</h3>
          <p className="text-sm text-gray-300 whitespace-pre-wrap">{task.instructions || 'Follow the task requirements and submit your proof below.'}</p>
        </div>

        {/* Proof requirements */}
        {task.proof_required && (
          <div className="p-4 rounded-lg bg-brand-500/5 border border-brand-500/20 mb-4">
            <h3 className="text-xs font-semibold text-brand-400 uppercase tracking-wide mb-2 flex items-center gap-1.5">
              <Upload size={12} /> Proof Required
            </h3>
            <p className="text-sm text-gray-400">{task.proof_instructions || 'Submit your proof below.'}</p>
          </div>
        )}

        {/* Action URL */}
        {task.action_url && !isDone && !isPending && (
          <a
            href={task.action_url}
            target="_blank"
            rel="noopener noreferrer"
            className="btn-secondary w-full mb-4"
          >
            <ExternalLink size={16} /> Open Task Link
          </a>
        )}

        {/* Status states */}
        {isDone && (
          <div className="px-4 py-3 rounded-lg bg-success-500/10 border border-success-500/20 text-success-500 text-sm text-center mb-4">
            <CheckCircle2 size={16} className="inline mr-1.5" /> Task completed! You earned {formatXc(task.reward * multiplier)} XC
          </div>
        )}
        {isPending && (
          <div className="px-4 py-3 rounded-lg bg-warning-500/10 border border-warning-500/20 text-warning-500 text-sm text-center mb-4">
            <Clock size={16} className="inline mr-1.5" /> Submission pending review. You'll be notified once approved.
          </div>
        )}
        {isRejected && (
          <div className="px-4 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm text-center mb-4">
            Your submission was rejected. Please contact support if you believe this is an error.
          </div>
        )}

        {error && (
          <div className="px-3.5 py-3 rounded-lg bg-danger-500/10 border border-danger-500/20 text-danger-500 text-sm mb-4">
            {error}
          </div>
        )}

        {/* Submit form */}
        {!isDone && !isPending && !isRejected && (
          <div className="space-y-3">
            {task.proof_required && (
              <div>
                <label className="label">Your Proof</label>
                <textarea
                  value={proofText}
                  onChange={(e) => setProofText(e.target.value)}
                  placeholder="Enter your proof here..."
                  rows={4}
                  className="input resize-none"
                />
              </div>
            )}
            <button onClick={handleSubmit} disabled={submitting} className="btn-primary w-full">
              {submitting ? <Spinner size={18} /> : task.proof_required ? 'Submit Proof' : 'Complete Task'}
            </button>
          </div>
        )}

        {/* Meta */}
        <div className="flex items-center justify-between mt-4 pt-4 border-t border-ink-700 text-xs text-gray-500">
          <span className="flex items-center gap-1"><Tag size={12} /> {task.category}</span>
          <span>{task.total_completions} completions</span>
        </div>
      </div>
    </div>
  );
}
