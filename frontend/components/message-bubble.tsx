'use client';

import Image from 'next/image';
import { ThumbsDown, ThumbsUp, User } from 'lucide-react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import remarkBreaks from 'remark-breaks';
import type { ChatMessage } from '@/lib/chat-storage';
import type { Rating } from '@/lib/api';
import { profile } from '@/content/profile';

const markdownComponents = {
  a: ({ href, children }: { href?: string; children?: React.ReactNode }) => (
    <a href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  ),
};

function formatTime(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? '' : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function Avatar({ size = 32 }: { size?: number }) {
  return (
    <Image
      src="/avatar.png"
      alt=""
      width={size}
      height={size}
      className="rounded-full border border-slate-300 dark:border-slate-600 shrink-0"
      style={{ width: size, height: size }}
    />
  );
}

interface Props {
  message: ChatMessage;
  streaming?: boolean;
  onFeedback?: (rating: Rating) => void;
}

export default function MessageBubble({ message, streaming = false, onFeedback }: Props) {
  const isUser = message.role === 'user';

  return (
    <div className={`flex gap-3 ${isUser ? 'justify-end' : 'justify-start'}`}>
      {!isUser && <Avatar />}

      <div
        className={`max-w-[85%] sm:max-w-[75%] rounded-2xl px-4 py-3 ${
          isUser
            ? 'bg-slate-700 text-white rounded-br-md'
            : 'bg-white border border-gray-200 text-gray-800 rounded-bl-md dark:bg-slate-800 dark:border-slate-700 dark:text-slate-100'
        }`}
      >
        {isUser ? (
          <p className="whitespace-pre-wrap break-words">{message.content}</p>
        ) : (
          <div className="prose prose-sm max-w-none break-words dark:prose-invert prose-p:my-1 prose-ul:my-1 prose-ol:my-1 prose-li:my-0 prose-headings:my-2 prose-a:text-blue-700 dark:prose-a:text-blue-300 prose-pre:bg-gray-100 prose-pre:text-gray-800 dark:prose-pre:bg-slate-900 dark:prose-pre:text-slate-100 prose-code:before:content-none prose-code:after:content-none">
            {message.content ? (
              <ReactMarkdown remarkPlugins={[remarkGfm, remarkBreaks]} components={markdownComponents}>
                {message.content}
              </ReactMarkdown>
            ) : streaming ? (
              <TypingDots />
            ) : null}
          </div>
        )}

        <div
          className={`flex items-center gap-3 mt-1 text-xs ${
            isUser ? 'text-slate-300 justify-end' : 'text-gray-500 dark:text-slate-400'
          }`}
        >
          <span>
            {formatTime(message.timestamp)}
            {message.stopped ? ' · stopped' : ''}
          </span>
          {!isUser && !streaming && message.content && onFeedback && (
            <span className="inline-flex items-center gap-1 ml-auto" role="group" aria-label="Rate this answer">
              <FeedbackButton
                label="Helpful"
                active={message.feedback === 'up'}
                onClick={() => onFeedback('up')}
                Icon={ThumbsUp}
              />
              <FeedbackButton
                label="Not helpful"
                active={message.feedback === 'down'}
                onClick={() => onFeedback('down')}
                Icon={ThumbsDown}
              />
            </span>
          )}
        </div>
      </div>

      {isUser && (
        <div
          className="w-8 h-8 bg-gray-600 dark:bg-slate-600 rounded-full flex items-center justify-center shrink-0"
          aria-hidden="true"
        >
          <User className="w-5 h-5 text-white" />
        </div>
      )}
    </div>
  );
}

function FeedbackButton({
  label,
  active,
  onClick,
  Icon,
}: {
  label: string;
  active: boolean;
  onClick: () => void;
  Icon: typeof ThumbsUp;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      aria-pressed={active}
      title={label}
      className={`p-1 rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300 ${
        active
          ? 'text-slate-900 dark:text-white'
          : 'text-gray-400 hover:text-gray-700 dark:text-slate-500 dark:hover:text-slate-200'
      }`}
    >
      <Icon className="w-4 h-4" aria-hidden="true" fill={active ? 'currentColor' : 'none'} />
    </button>
  );
}

export function TypingDots() {
  return (
    <span className="inline-flex items-center gap-1.5 py-1" role="status" aria-label={`${profile.name} is typing`}>
      <span className="typing-dot" />
      <span className="typing-dot" style={{ animationDelay: '0.15s' }} />
      <span className="typing-dot" style={{ animationDelay: '0.3s' }} />
    </span>
  );
}
