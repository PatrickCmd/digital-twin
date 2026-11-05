// Typed view over backend/data/profile.json, the single source of truth for
// facts about Patrick. `npm run sync-profile` (run automatically before dev
// and build) copies that file to ./profile.json; do not edit the copy.
import raw from './profile.json';

export interface RecruiterFacts {
  role_targets: string[];
  stack: string[];
  remote_preference: string | null;
  work_authorization: string | null;
  notice_period: string | null;
  availability: string | null;
}

export interface Profile {
  full_name: string;
  name: string;
  headline: string;
  title: string;
  location: string;
  timezone: string;
  email: string;
  links: {
    github: string;
    linkedin: string;
    website: string;
    resume_pdf: string | null;
  };
  specialties: string[];
  career_start: string;
  certifications: string[];
  recruiter_facts: RecruiterFacts;
  suggested_questions: string[];
  knowledge_updated: string;
}

export const profile: Profile = raw as Profile;

/** Whole years since career_start (YYYY-MM). */
export function yearsOfExperience(now: Date = new Date()): number {
  const [year, month] = profile.career_start.split('-').map(Number);
  let years = now.getFullYear() - year;
  if (now.getMonth() + 1 < month) years -= 1;
  return Math.max(years, 0);
}

export const siteUrl = 'https://digital-twin.patrickcmd.dev';

export const disclosure = `This is an AI trained on ${profile.name}'s resume and notes. It can be wrong. For anything that matters, email him at ${profile.email}.`;
