import Image from 'next/image';
import { Globe, FileText, Mail } from 'lucide-react';
import { GitHubIcon, LinkedInIcon } from '@/components/brand-icons';
import Twin from '@/components/twin';
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
    <main className="min-h-screen bg-gradient-to-br from-slate-50 to-gray-100">
      <div className="container mx-auto px-4 py-8">
        <div className="max-w-4xl mx-auto">
          <header className="flex flex-col items-center text-center mb-8">
            <Image
              src="/avatar.png"
              alt={profile.full_name}
              width={96}
              height={96}
              priority
              className="w-24 h-24 rounded-full border-2 border-slate-300 shadow mb-4"
            />
            <h1 className="text-4xl font-bold text-gray-800 mb-1">
              {profile.full_name}
            </h1>
            <p className="text-gray-600">{profile.title} · {profile.location}</p>
            <p className="text-gray-700 mt-3 max-w-2xl">{profile.headline}</p>

            <nav aria-label="Patrick's links" className="flex flex-wrap justify-center gap-2 mt-4">
              {links.map(({ href, label, Icon }) => (
                <a
                  key={label}
                  href={href}
                  target={href.startsWith('mailto:') ? undefined : '_blank'}
                  rel={href.startsWith('mailto:') ? undefined : 'noopener noreferrer'}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-full border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600"
                >
                  <Icon className="w-4 h-4" aria-hidden="true" />
                  {label}
                </a>
              ))}
            </nav>
          </header>

          <div className="h-[600px]">
            <Twin />
          </div>

          <footer className="mt-6 text-center text-sm text-gray-500 space-y-1">
            <p>{disclosure}</p>
          </footer>
        </div>
      </div>
    </main>
  );
}
