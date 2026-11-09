import { FieldValue, type DocumentReference } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { defineSecret } from 'firebase-functions/params';
import nodemailer from 'nodemailer';

/**
 * Sends the documents queued in `mail` (invites, see invites/email.ts) through
 * Gmail SMTP as [MAIL_SENDER] (docs/DECISIONS.md D-045). Replaces the Trigger
 * Email extension, which Firebase shuts down in March 2027.
 */
export const MAIL_SENDER = 'infostandwise@gmail.com';
export const MAIL_FROM = `Standwise <${MAIL_SENDER}>`;

/** Gmail app password of [MAIL_SENDER] (Secret Manager, SETUP §8). */
const smtpPassword = defineSecret('SMTP_PASSWORD');

export interface MailDoc {
  to?: unknown;
  message?: { subject?: unknown; text?: unknown; html?: unknown };
  delivery?: unknown;
}

export interface OutgoingMail {
  from: string;
  to: string[];
  subject: string;
  text: string;
  html?: string;
}

export type SendMail = (mail: OutgoingMail) => Promise<void>;

/** The mail to send for a queued document, or `null` when it's malformed. */
export function outgoingMail(doc: MailDoc): OutgoingMail | null {
  const to = Array.isArray(doc.to) ? doc.to : [doc.to];
  const recipients = to.filter((t): t is string => typeof t === 'string' && t.includes('@'));
  const m = doc.message;
  if (recipients.length === 0 || !m) return null;
  if (typeof m.subject !== 'string' || typeof m.text !== 'string') return null;
  return {
    from: MAIL_FROM,
    to: recipients,
    subject: m.subject,
    text: m.text,
    ...(typeof m.html === 'string' ? { html: m.html } : {}),
  };
}

/**
 * Sends one queued document once and records the outcome in `delivery`. The
 * message body (it holds the invite code) is removed after a successful send
 * so codes don't stay in Firestore.
 */
export async function deliverMail(ref: DocumentReference, doc: MailDoc, send: SendMail): Promise<void> {
  if (doc.delivery) return; // Already handled (a retried event).
  const mail = outgoingMail(doc);
  if (!mail) {
    await ref.update({ delivery: { state: 'ERROR', error: 'malformed', time: FieldValue.serverTimestamp() } });
    return;
  }
  try {
    await send(mail);
    await ref.update({
      message: FieldValue.delete(),
      delivery: { state: 'SUCCESS', time: FieldValue.serverTimestamp() },
    });
  } catch (e) {
    const error = e instanceof Error ? e.message : String(e);
    logger.error('mail delivery failed', { id: ref.id, error });
    await ref.update({ delivery: { state: 'ERROR', error, time: FieldValue.serverTimestamp() } });
  }
}

export const sendMail = onDocumentCreated(
  { document: 'mail/{mailId}', secrets: [smtpPassword] },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const transport = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 465,
      secure: true,
      auth: { user: MAIL_SENDER, pass: smtpPassword.value() },
    });
    await deliverMail(snap.ref, snap.data() as MailDoc, async (m) => {
      await transport.sendMail(m);
    });
  },
);
