// Copies backend/data/profile.json into frontend/content/profile.json so the
// static export can import it. Runs automatically via the predev/prebuild hooks.
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const source = resolve(here, '../../backend/data/profile.json');
const target = resolve(here, '../content/profile.json');

mkdirSync(dirname(target), { recursive: true });
copyFileSync(source, target);
console.log(`profile.json synced from ${source}`);
