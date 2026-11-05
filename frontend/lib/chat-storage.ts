import type { Rating } from './api';

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: string; // ISO 8601
  feedback?: Rating;
  stopped?: boolean;
}

export interface StoredChat {
  version: 1;
  sessionId: string | null;
  messages: ChatMessage[];
}

const KEY = 'digital-twin:v1';

export function loadChat(): StoredChat | null {
  try {
    const raw = window.localStorage.getItem(KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<StoredChat>;
    if (parsed.version !== 1 || !Array.isArray(parsed.messages)) return null;
    return { version: 1, sessionId: parsed.sessionId ?? null, messages: parsed.messages };
  } catch {
    return null;
  }
}

export function saveChat(chat: StoredChat): void {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(chat));
  } catch {
    // Storage can be unavailable (private mode, quota). The chat still works.
  }
}

export function clearChat(): void {
  try {
    window.localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}
