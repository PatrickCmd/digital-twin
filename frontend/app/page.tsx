import Image from 'next/image';
import { Globe, FileText, Mail } from 'lucide-react';
import { GitHubIcon, LinkedInIcon } from '@/components/brand-icons';
import Twin from '@/components/twin';
import RecruiterDialog from '@/components/recruiter-dialog';
import { profile, disclosure } from '@/content/profile';

export default function Home() {
  const links = [
    { href: profile.links.github, label: 'GitHub', Icon: GitHubIcon },
    { href: profile.links.linkedin, label: 'LinkedIn', Icon: LinkedInIcon },
    { href: profile.links.website, label: 'Website', Icon: Globe },
    { href: profile.links.resume_pdf, label: 'Resume', Icon: FileText },
    { href: `mailto:${profile.email}`, label: 'Email', Icon: Mail },
  ].filter((l): l is { href: string; label: string; Icon: typeof Globe } => Boolean(l.href));

  return (
    <main className="h-dvh flex flex-col bg-gradient-to-br from-slate-50 to-gray-100 dark:from-slate-950 dark:to-slate-900 text-gray-800 dark:text-slate-100">
      <div className="flex flex-col flex-1 min-h-0 w-full max-w-4xl mx-auto px-4 pt-4 sm:pt-6 pb-2">
        <header className="flex items-center gap-3 sm:gap-4 mb-3 sm:mb-4">
          <Image
            src="/avatar.png"
            alt={profile.full_name}
            width={64}
            height={64}
            priority
            className="w-12 h-12 sm:w-16 sm:h-16 rounded-full border-2 border-slate-300 dark:border-slate-600 shadow shrink-0"
          />
          <div className="min-w-0 flex-1">
            <h1 className="text-xl sm:text-2xl font-bold leading-tight">{profile.full_name}</h1>
            <p className="text-sm text-gray-600 dark:text-slate-300 truncate">
              {profile.title} · {profile.location}
            </p>
            <p className="hidden sm:block text-sm text-gray-700 dark:text-slate-200 mt-1">{profile.headline}</p>
          </div>
          <nav aria-label="Patrick's links" className="flex flex-wrap justify-end gap-1.5 sm:gap-2 shrink-0 max-w-[40%]">
            <RecruiterDialog />
            {links.map(({ href, label, Icon }) => (
              <a
                key={label}
                href={href}
                target={href.startsWith('mailto:') ? undefined : '_blank'}
                rel={href.startsWith('mailto:') ? undefined : 'noopener noreferrer'}
                title={label}
                className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-sm rounded-full border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:bg-slate-800 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300"
              >
                <Icon className="w-4 h-4" aria-hidden="true" />
                <span className="hidden sm:inline">{label}</span>
                <span className="sr-only sm:hidden">{label}</span>
              </a>
            ))}
          </nav>
        </header>

        <div className="flex-1 min-h-0">
          <Twin />
        </div>

        <footer className="mt-2 text-center text-xs text-gray-500 dark:text-slate-400">
          <p>{disclosure}</p>
        </footer>
      </div>
    </main>
  );
}
