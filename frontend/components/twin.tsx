'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { Bot, RotateCcw, Send, SquarePen, Square } from 'lucide-react';
import { profile } from '@/content/profile';
import { createId, now } from '@/lib/ids';
import { ApiError, errorFromUnknown, sendFeedback, streamChat, type Rating } from '@/lib/api';
import { clearChat, loadChat, saveChat, type ChatMessage } from '@/lib/chat-storage';
import MessageBubble, { Avatar } from '@/components/message-bubble';
import RecruiterCard from '@/components/recruiter-card';

interface ChatError {
  message: string;
  code: string;
  retryText: string | null;
}

const MAX_INPUT_CHARS = 2000;

export default function Twin() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [input, setInput] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<ChatError | null>(null);
  const [hydrated, setHydrated] = useState(false);

  const paneRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const stickToBottomRef = useRef(true);

  // Restore a previous conversation (versioned localStorage key).
  useEffect(() => {
    const stored = loadChat();
    if (stored) {
      setMessages(stored.messages);
      setSessionId(stored.sessionId);
    }
    setHydrated(true);
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    saveChat({ version: 1, sessionId, messages });
  }, [hydrated, sessionId, messages]);

  // Auto-scroll the message pane (not the page) while the reader is near the bottom.
  useEffect(() => {
    const pane = paneRef.current;
    if (pane && stickToBottomRef.current && (messages.length > 0 || error)) {
      pane.scrollTop = pane.scrollHeight;
    }
  }, [messages, error, isStreaming]);

  const handlePaneScroll = () => {
    const pane = paneRef.current;
    if (!pane) return;
    const distance = pane.scrollHeight - pane.scrollTop - pane.clientHeight;
    stickToBottomRef.current = distance < 80;
  };

  const resizeTextarea = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
  }, []);

  useEffect(() => {
    resizeTextarea();
  }, [input, resizeTextarea]);

  const focusComposer = () => {
    window.setTimeout(() => textareaRef.current?.focus(), 50);
  };

  const sendMessage = async (text?: string) => {
    const messageText = (text ?? input).trim();
    if (!messageText || isStreaming) return;
    if (messageText.length > MAX_INPUT_CHARS) {
      setError({
        message: `Messages are limited to ${MAX_INPUT_CHARS} characters.`,
        code: 'message_too_long',
        retryText: null,
      });
      return;
    }

    setError(null);
    setInput('');
    stickToBottomRef.current = true;

    const userMessage: ChatMessage = { id: createId(), role: 'user', content: messageText, timestamp: now().toISOString() };
    const assistantId = createId();
    const assistantMessage: ChatMessage = { id: assistantId, role: 'assistant', content: '', timestamp: now().toISOString() };
    setMessages((prev) => [...prev, userMessage, assistantMessage]);
    setIsStreaming(true);

    const controller = new AbortController();
    abortRef.current = controller;
    let received = '';

    try {
      await streamChat(messageText, sessionId, controller.signal, {
        onSession: (id) => setSessionId(id),
        onChunk: (chunk) => {
          received += chunk;
          const snapshot = received;
          setMessages((prev) => prev.map((m) => (m.id === assistantId ? { ...m, content: snapshot } : m)));
        },
      });
      if (controller.signal.aborted) {
        setMessages((prev) =>
          prev
            .map((m) => (m.id === assistantId ? { ...m, stopped: true } : m))
            .filter((m) => m.id !== assistantId || m.content),
        );
      }
    } catch (err: unknown) {
      const apiError: ApiError = errorFromUnknown(err);
      // Drop the empty assistant bubble; keep the user's message so Retry can re-send it.
      setMessages((prev) => prev.filter((m) => m.id !== assistantId));
      setError({ message: apiError.message, code: apiError.code, retryText: messageText });
      if (received === '') {
        setMessages((prev) => prev.filter((m) => m.id !== userMessage.id));
      }
    } finally {
      abortRef.current = null;
      setIsStreaming(false);
      focusComposer();
    }
  };

  const stopStreaming = () => {
    abortRef.current?.abort();
  };

  const newChat = () => {
    abortRef.current?.abort();
    clearChat();
    setMessages([]);
    setSessionId(null);
    setError(null);
    setInput('');
    focusComposer();
  };

  const retry = () => {
    if (!error?.retryText) return;
    const text = error.retryText;
    setError(null);
    void sendMessage(text);
  };

  const rate = async (message: ChatMessage, rating: Rating) => {
    if (!sessionId) return;
    const next: Rating | undefined = message.feedback === rating ? undefined : rating;
    setMessages((prev) => prev.map((m) => (m.id === message.id ? { ...m, feedback: next } : m)));
    if (!next) return;
    const index = messages.findIndex((m) => m.id === message.id);
    try {
      await sendFeedback({
        session_id: sessionId,
        message_index: index,
        rating: next,
        assistant_preview: message.content.slice(0, 200),
      });
    } catch {
      // Feedback is best effort; the UI already reflects the click.
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      void sendMessage();
    }
  };

  const isEmpty = messages.length === 0 && !error;
  const lastMessage = messages[messages.length - 1];

  return (
    <section
      className="flex flex-col h-full min-h-0 bg-gray-50 dark:bg-slate-900 rounded-lg shadow-lg border border-gray-200 dark:border-slate-700"
      aria-label="Chat with the digital twin"
    >
      {/* Header */}
      <div className="flex items-center justify-between gap-3 bg-gradient-to-r from-slate-700 to-slate-800 text-white px-4 py-3 rounded-t-lg">
        <div className="min-w-0">
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Bot className="w-5 h-5" aria-hidden="true" />
            AI Digital Twin
          </h2>
          <p className="text-xs text-slate-300 truncate">{profile.full_name}&apos;s AI Digital Twin</p>
        </div>
        <button
          type="button"
          onClick={newChat}
          className="inline-flex items-center gap-1.5 text-sm px-3 py-1.5 rounded-md bg-white/10 hover:bg-white/20 focus:outline-none focus-visible:ring-2 focus-visible:ring-white"
        >
          <SquarePen className="w-4 h-4" aria-hidden="true" />
          New chat
        </button>
      </div>

      {/* Messages */}
      <div
        ref={paneRef}
        onScroll={handlePaneScroll}
        className="flex-1 min-h-0 overflow-y-auto overscroll-contain px-3 sm:px-4 py-4 space-y-4"
        aria-live="polite"
        aria-relevant="additions text"
        aria-busy={isStreaming}
      >
        {isEmpty && (
          <div className="text-center text-gray-600 dark:text-slate-300 mt-6">
            <div className="flex justify-center mb-3">
              <Avatar size={80} />
            </div>
            <p className="text-lg">Hello! I&apos;m {profile.full_name}&apos;s Digital Twin.</p>
            <p className="text-sm mt-2">Ask me anything about {profile.name}, or start with one of these:</p>
            <ul className="flex flex-wrap justify-center gap-2 mt-4 px-2" aria-label="Suggested questions">
              {profile.suggested_questions.map((q) => (
                <li key={q}>
                  <button
                    type="button"
                    onClick={() => void sendMessage(q)}
                    className="px-3 py-1.5 text-sm rounded-full border border-gray-300 bg-white text-gray-700 hover:bg-gray-100 dark:bg-slate-800 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300"
                  >
                    {q}
                  </button>
                </li>
              ))}
            </ul>
            <p className="text-xs mt-4 text-gray-500 dark:text-slate-400">
              What this twin knows: {profile.name}&apos;s resume/LinkedIn and project notes, last updated {profile.knowledge_updated}.
            </p>
            <div className="mt-6 max-w-2xl mx-auto">
              <RecruiterCard compact />
            </div>
          </div>
        )}

        {messages.map((message) => (
          <MessageBubble
            key={message.id}
            message={message}
            streaming={isStreaming && message.id === lastMessage?.id && message.role === 'assistant'}
            onFeedback={message.role === 'assistant' ? (rating) => void rate(message, rating) : undefined}
          />
        ))}

        {error && (
          <div role="alert" className="flex gap-3 justify-start">
            <Avatar />
            <div className="max-w-[85%] sm:max-w-[75%] rounded-2xl rounded-bl-md px-4 py-3 bg-red-50 border border-red-200 text-red-900 dark:bg-red-950 dark:border-red-900 dark:text-red-100">
              <p>{error.message}</p>
              <div className="flex gap-2 mt-2">
                {error.retryText && error.code !== 'session_full' && (
                  <button
                    type="button"
                    onClick={retry}
                    className="inline-flex items-center gap-1 text-sm px-3 py-1 rounded-md bg-white border border-red-300 text-red-900 hover:bg-red-100 dark:bg-red-900 dark:border-red-700 dark:text-red-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
                  >
                    <RotateCcw className="w-4 h-4" aria-hidden="true" />
                    Retry
                  </button>
                )}
                {error.code === 'session_full' && (
                  <button
                    type="button"
                    onClick={newChat}
                    className="text-sm px-3 py-1 rounded-md bg-white border border-red-300 text-red-900 hover:bg-red-100 dark:bg-red-900 dark:border-red-700 dark:text-red-50 focus:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
                  >
                    Start a new chat
                  </button>
                )}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Composer */}
      <form
        onSubmit={(e) => {
          e.preventDefault();
          void sendMessage();
        }}
        className="border-t border-gray-200 dark:border-slate-700 p-3 sm:p-4 bg-white dark:bg-slate-800 rounded-b-lg"
        style={{ paddingBottom: 'max(0.75rem, env(safe-area-inset-bottom))' }}
      >
        <div className="flex gap-2 items-end">
          <label htmlFor="chat-input" className="sr-only">
            Message the digital twin
          </label>
          <textarea
            id="chat-input"
            ref={textareaRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={`Ask ${profile.name} something…`}
            rows={1}
            maxLength={MAX_INPUT_CHARS}
            disabled={isStreaming}
            autoFocus
            enterKeyHint="send"
            className="flex-1 resize-none px-4 py-2.5 border border-gray-300 dark:border-slate-600 rounded-xl bg-white dark:bg-slate-900 text-gray-800 dark:text-slate-100 placeholder:text-gray-500 dark:placeholder:text-slate-400 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300 disabled:opacity-60"
          />
          {isStreaming ? (
            <button
              type="button"
              onClick={stopStreaming}
              aria-label="Stop generating"
              className="h-11 w-11 shrink-0 inline-flex items-center justify-center bg-gray-200 dark:bg-slate-700 text-gray-800 dark:text-slate-100 rounded-xl hover:bg-gray-300 dark:hover:bg-slate-600 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600"
            >
              <Square className="w-4 h-4" aria-hidden="true" fill="currentColor" />
            </button>
          ) : (
            <button
              type="submit"
              aria-label="Send message"
              disabled={!input.trim()}
              className="h-11 w-11 shrink-0 inline-flex items-center justify-center bg-slate-700 text-white rounded-xl hover:bg-slate-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <Send className="w-5 h-5" aria-hidden="true" />
            </button>
          )}
        </div>
        <p className="mt-1.5 text-xs text-gray-500 dark:text-slate-400">
          Enter to send, Shift+Enter for a new line.
          <span className="sr-only"> Maximum {MAX_INPUT_CHARS} characters.</span>
        </p>
      </form>
    </section>
  );
}
