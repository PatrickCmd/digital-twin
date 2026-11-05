'use client';

import { useEffect, useRef, useState } from 'react';
import { Briefcase, X } from 'lucide-react';
import RecruiterCard from '@/components/recruiter-card';
import ContactForm from '@/components/contact-form';

/** Header button that opens the recruiter facts + contact form in a modal dialog. */
export default function RecruiterDialog() {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-sm rounded-full border border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:bg-slate-800 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600 dark:focus-visible:ring-slate-300"
      >
        <Briefcase className="w-4 h-4" aria-hidden="true" />
        <span className="hidden sm:inline">For recruiters</span>
        <span className="sr-only sm:hidden">For recruiters</span>
      </button>

      <dialog
        ref={dialogRef}
        onClose={() => setOpen(false)}
        onClick={(e) => {
          if (e.target === dialogRef.current) setOpen(false); // backdrop click
        }}
        aria-label="Information for recruiters"
        className="m-auto w-[min(42rem,calc(100%-2rem))] max-h-[90dvh] overflow-y-auto rounded-2xl p-0 bg-transparent backdrop:bg-black/50"
      >
        <div className="bg-gray-50 dark:bg-slate-900 text-gray-800 dark:text-slate-100 rounded-2xl p-4 sm:p-6 space-y-4">
          <div className="flex items-start justify-between gap-3">
            <h2 className="text-lg font-semibold">Hiring? Start here.</h2>
            <button
              type="button"
              onClick={() => setOpen(false)}
              aria-label="Close"
              className="p-1 rounded-md hover:bg-gray-200 dark:hover:bg-slate-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-slate-600"
            >
              <X className="w-5 h-5" aria-hidden="true" />
            </button>
          </div>
          <RecruiterCard />
          <div className="rounded-xl border border-gray-200 bg-white dark:bg-slate-800 dark:border-slate-700 p-4">
            <ContactForm />
          </div>
        </div>
      </dialog>
    </>
  );
}
