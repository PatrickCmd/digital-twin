import type { MetadataRoute } from 'next';
import { profile, siteUrl } from '@/content/profile';

export const dynamic = 'force-static';

export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: siteUrl, lastModified: new Date(profile.knowledge_updated), changeFrequency: 'monthly', priority: 1 }];
}
