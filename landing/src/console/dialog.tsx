import React, { createContext, useCallback, useContext, useEffect, useId, useRef, useState } from 'react';

// ================= Accessible in-page dialog =================
// Replaces native alert()/confirm(): aria-modal, focus trap, Esc to close,
// focus returns to the element that opened it.

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface ConsoleDialogProps {
  title: React.ReactNode;
  onClose: () => void;
  children: React.ReactNode;
  /** Narrow layout for confirm/notice dialogs. */
  compact?: boolean;
  /** Role "alertdialog" for confirmations that need a decision. */
  alert?: boolean;
}

export const ConsoleDialog: React.FC<ConsoleDialogProps> = ({ title, onClose, children, compact, alert }) => {
  const ref = useRef<HTMLDivElement>(null);
  const titleId = useId();
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    const node = ref.current;
    if (node) {
      const first = node.querySelector<HTMLElement>('[data-autofocus]') ?? node.querySelector<HTMLElement>(FOCUSABLE);
      (first ?? node).focus();
    }
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prevOverflow;
      prev?.focus?.();
    };
  }, []);

  const onKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      onCloseRef.current();
      return;
    }
    if (e.key !== 'Tab' || !ref.current) return;
    const items = Array.from(ref.current.querySelectorAll<HTMLElement>(FOCUSABLE)).filter(
      (el) => el.offsetParent !== null || el === document.activeElement,
    );
    if (items.length === 0) {
      e.preventDefault();
      return;
    }
    const first = items[0];
    const last = items[items.length - 1];
    if (e.shiftKey && (document.activeElement === first || document.activeElement === ref.current)) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <div className="console-dialog-overlay" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div
        ref={ref}
        className={`console-dialog${compact ? ' console-dialog-compact' : ''}`}
        role={alert ? 'alertdialog' : 'dialog'}
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        onKeyDown={onKeyDown}
      >
        <h3 id={titleId}>{title}</h3>
        {children}
      </div>
    </div>
  );
};

// ================= confirm() / notify() replacements =================

interface ConfirmOptions {
  title: string;
  message?: React.ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  danger?: boolean;
}

interface DialogApi {
  confirm: (opts: ConfirmOptions) => Promise<boolean>;
  notify: (opts: { title: string; message?: React.ReactNode }) => Promise<void>;
}

const DialogContext = createContext<DialogApi>({
  confirm: async () => false,
  notify: async () => undefined,
});

interface Pending {
  kind: 'confirm' | 'notify';
  opts: ConfirmOptions;
  resolve: (ok: boolean) => void;
}

export const DialogProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [pending, setPending] = useState<Pending | null>(null);

  const confirm = useCallback(
    (opts: ConfirmOptions) => new Promise<boolean>((resolve) => setPending({ kind: 'confirm', opts, resolve })),
    [],
  );
  const notify = useCallback(
    (opts: { title: string; message?: React.ReactNode }) =>
      new Promise<void>((resolve) => setPending({ kind: 'notify', opts, resolve: () => resolve() })),
    [],
  );

  const settle = (ok: boolean) => {
    pending?.resolve(ok);
    setPending(null);
  };

  return (
    <DialogContext.Provider value={{ confirm, notify }}>
      {children}
      {pending && (
        <ConsoleDialog title={pending.opts.title} onClose={() => settle(false)} compact alert={pending.kind === 'confirm'}>
          {pending.opts.message && <div className="console-dialog-body">{pending.opts.message}</div>}
          <div className="console-row console-dialog-actions">
            {pending.kind === 'confirm' && (
              <button type="button" className="console-btn console-btn-ghost" onClick={() => settle(false)}>
                {pending.opts.cancelLabel ?? 'Cancel'}
              </button>
            )}
            <button
              type="button"
              data-autofocus={pending.kind === 'notify' || !pending.opts.danger ? '' : undefined}
              className={`console-btn ${pending.opts.danger ? 'console-btn-danger-solid' : 'console-btn-primary'}`}
              onClick={() => settle(true)}
            >
              {pending.kind === 'confirm' ? pending.opts.confirmLabel ?? 'Confirm' : 'OK'}
            </button>
          </div>
        </ConsoleDialog>
      )}
    </DialogContext.Provider>
  );
};

export const useDialogs = () => useContext(DialogContext);

// ================= Copy-to-clipboard button =================

export const CopyButton: React.FC<{ value: string; label?: string }> = ({ value, label = 'Copy' }) => {
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!copied) return;
    const t = window.setTimeout(() => setCopied(false), 2000);
    return () => window.clearTimeout(t);
  }, [copied]);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
    } catch {
      // Clipboard API blocked (insecure context): fall back to a hidden textarea.
      const ta = document.createElement('textarea');
      ta.value = value;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try {
        setCopied(document.execCommand('copy'));
      } finally {
        document.body.removeChild(ta);
      }
    }
  };

  return (
    <button type="button" className="console-btn console-btn-ghost console-btn-sm" onClick={copy}>
      <span aria-live="polite">{copied ? 'Copied' : label}</span>
    </button>
  );
};

/** Read-only value with a copy button (org code, PIN, org id). */
export const CopyField: React.FC<{ label: string; value: string; id?: string }> = ({ label, value, id }) => {
  const autoId = useId();
  const fieldId = id ?? autoId;
  return (
    <div className="console-field">
      <span className="console-label" id={`${fieldId}-label`}>{label}</span>
      <div className="console-copy">
        <code className="console-code" aria-labelledby={`${fieldId}-label`}>{value || '—'}</code>
        {value && <CopyButton value={value} />}
      </div>
    </div>
  );
};
