'use client';

import { useState } from 'react';
import { Send } from 'lucide-react';
import { profile } from '@/content/profile';
import { errorFromUnknown, sendContact } from '@/lib/api';

type Status = { kind: 'idle' } | { kind: 'sending' } | { kind: 'sent' } | { kind: 'error'; message: string };

const inputClass =
  'w-full px-3 py-2 rounded-lg border border-gray-300 bg-white text-gray-800 placeholder:text-gray-500 dark:bg-slate-900 dark:border-slate-600 dark:text-slate-100 dark:placeholder:text-slate-400 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300';

export default function ContactForm() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [message, setMessage] = useState('');
  const [website, setWebsite] = useState(''); // honeypot; stays empty for humans
  const [status, setStatus] = useState<Status>({ kind: 'idle' });

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (status.kind === 'sending') return;
    setStatus({ kind: 'sending' });
    try {
      await sendContact({ name: name.trim(), email: email.trim(), message: message.trim(), website });
      setStatus({ kind: 'sent' });
      setName('');
      setEmail('');
      setMessage('');
    } catch (err: unknown) {
      setStatus({ kind: 'error', message: errorFromUnknown(err).message });
    }
  };

  if (status.kind === 'sent') {
    return (
      <p role="status" className="text-sm text-gray-800 dark:text-slate-100">
        Thanks, your message has been passed on to {profile.name}. He will reply by email.
      </p>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-3" aria-labelledby="contact-form-title">
      <h3 id="contact-form-title" className="font-semibold text-gray-800 dark:text-slate-100">
        Leave a message for {profile.name}
      </h3>
      <div className="grid sm:grid-cols-2 gap-3">
        <div>
          <label htmlFor="contact-name" className="block text-sm text-gray-600 dark:text-slate-300 mb-1">
            Your name
          </label>
          <input
            id="contact-name"
            name="name"
            required
            maxLength={100}
            autoComplete="name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className={inputClass}
          />
        </div>
        <div>
          <label htmlFor="contact-email" className="block text-sm text-gray-600 dark:text-slate-300 mb-1">
            Your email
          </label>
          <input
            id="contact-email"
            name="email"
            type="email"
            required
            maxLength={254}
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className={inputClass}
          />
        </div>
      </div>
      <div>
        <label htmlFor="contact-message" className="block text-sm text-gray-600 dark:text-slate-300 mb-1">
          Message
        </label>
        <textarea
          id="contact-message"
          name="message"
          required
          rows={4}
          maxLength={2000}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          className={`${inputClass} resize-y`}
        />
      </div>
      <div className="hidden" aria-hidden="true">
        <label htmlFor="contact-website">Website</label>
        <input id="contact-website" name="website" tabIndex={-1} autoComplete="off" value={website} onChange={(e) => setWebsite(e.target.value)} />
      </div>
      {status.kind === 'error' && (
        <p role="alert" className="text-sm text-red-700 dark:text-red-300">
          {status.message}
        </p>
      )}
      <button
        type="submit"
        disabled={status.kind === 'sending'}
        className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-slate-700 text-white hover:bg-slate-800 disabled:opacity-60 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300"
      >
        <Send className="w-4 h-4" aria-hidden="true" />
        {status.kind === 'sending' ? 'Sending…' : `Send to ${profile.name}`}
      </button>
    </form>
  );
}
