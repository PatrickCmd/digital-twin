import { Briefcase } from 'lucide-react';
import { profile, yearsOfExperience } from '@/content/profile';

/** Quick facts for recruiters. Fields that are null in profile.json are omitted. */
export default function RecruiterCard({ compact = false }: { compact?: boolean }) {
  const facts = profile.recruiter_facts;
  const rows: Array<{ label: string; value: string | null }> = [
    { label: 'Role targets', value: facts.role_targets.length ? facts.role_targets.join(', ') : null },
    { label: 'Stack', value: facts.stack.length ? facts.stack.join(', ') : null },
    { label: 'Experience', value: `${yearsOfExperience()}+ years` },
    { label: 'Location', value: `${profile.location} (${profile.timezone})` },
    { label: 'Remote', value: facts.remote_preference },
    { label: 'Work authorization', value: facts.work_authorization },
    { label: 'Notice period', value: facts.notice_period },
    { label: 'Availability', value: facts.availability },
    { label: 'Certifications', value: profile.certifications.length ? profile.certifications.join(', ') : null },
  ];
  const visible = rows.filter((r): r is { label: string; value: string } => Boolean(r.value));

  return (
    <section
      aria-labelledby="recruiter-card-title"
      className={`text-left rounded-xl border border-gray-200 bg-white dark:bg-slate-800 dark:border-slate-700 ${
        compact ? 'p-3 sm:p-4' : 'p-4'
      }`}
    >
      <h3 id="recruiter-card-title" className="flex items-center gap-2 font-semibold text-gray-800 dark:text-slate-100">
        <Briefcase className="w-4 h-4" aria-hidden="true" />
        For recruiters
      </h3>
      <dl className={`mt-2 grid gap-x-4 gap-y-1.5 text-sm ${compact ? 'sm:grid-cols-2' : ''}`}>
        {visible.map(({ label, value }) => (
          <div key={label} className="grid grid-cols-[7.5rem_1fr] gap-2">
            <dt className="text-gray-500 dark:text-slate-400">{label}</dt>
            <dd className="text-gray-800 dark:text-slate-100">{value}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-3 text-xs text-gray-500 dark:text-slate-400">
        Anything not listed here (for example notice period or work authorization) is best confirmed with {profile.name}{' '}
        directly at{' '}
        <a href={`mailto:${profile.email}`} className="underline">
          {profile.email}
        </a>
        .
      </p>
    </section>
  );
}
