import { fetchEventSource } from '@microsoft/fetch-event-source';

export const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000';

export interface ApiErrorBody {
  error?: string;
  detail?: string;
}

/** Error raised for non-2xx responses; carries the backend's error code. */
export class ApiError extends Error {
  status: number;
  code: string;

  constructor(status: number, body: ApiErrorBody | null) {
    super(friendlyMessage(status, body));
    this.status = status;
    this.code = body?.error ?? (status >= 500 ? 'server_error' : 'error');
  }
}

export function friendlyMessage(status: number, body: ApiErrorBody | null): string {
  if (body?.detail && (status === 422 || status === 429 || status === 409)) {
    return body.detail;
  }
  if (status === 429) return 'You have sent a lot of messages in a short time. Please wait a few minutes and try again.';
  if (status === 409) return 'This conversation has reached its length limit. Please start a new chat.';
  if (status === 422) return 'That message could not be sent. Try shortening it.';
  return 'The twin is busy right now. Please try again in a minute.';
}

export function errorFromUnknown(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  return new ApiError(0, { error: 'network', detail: undefined });
}

async function readErrorBody(response: Response): Promise<ApiErrorBody | null> {
  try {
    return (await response.json()) as ApiErrorBody;
  } catch {
    return null;
  }
}

export interface StreamHandlers {
  onSession: (sessionId: string) => void;
  onChunk: (text: string) => void;
}

/**
 * Streams one chat turn. Resolves when the server sends `done`, rejects with
 * ApiError on an HTTP error, and resolves quietly when `signal` aborts.
 * Note: on the current Lambda + API Gateway deployment the whole response
 * arrives at once; the client handles both buffered and true streaming.
 */
export async function streamChat(
  message: string,
  sessionId: string | null,
  signal: AbortSignal,
  handlers: StreamHandlers,
): Promise<void> {
  let failure: ApiError | null = null;

  await fetchEventSource(`${API_URL}/chat/stream`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ message, session_id: sessionId || undefined }),
    signal,
    openWhenHidden: true,
    async onopen(response) {
      if (response.ok) return;
      failure = new ApiError(response.status, await readErrorBody(response));
      throw failure;
    },
    onmessage(ev) {
      if (!ev.data) return;
      const data = JSON.parse(ev.data) as { type: string; session_id?: string; content?: string; message?: string };
      if (data.type === 'session' && data.session_id) handlers.onSession(data.session_id);
      else if (data.type === 'chunk' && typeof data.content === 'string') handlers.onChunk(data.content);
      else if (data.type === 'error') {
        failure = new ApiError(502, { error: 'upstream', detail: data.message });
        throw failure;
      }
    },
    onerror(err) {
      // Rethrow so fetchEventSource does not retry forever.
      throw failure ?? err;
    },
  }).catch((err: unknown) => {
    if (signal.aborted) return;
    throw errorFromUnknown(failure ?? err);
  });
}

export type Rating = 'up' | 'down';

export async function sendFeedback(payload: {
  session_id: string;
  message_index: number;
  rating: Rating;
  comment?: string;
  assistant_preview?: string;
}): Promise<void> {
  const response = await fetch(`${API_URL}/feedback`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new ApiError(response.status, await readErrorBody(response));
}
