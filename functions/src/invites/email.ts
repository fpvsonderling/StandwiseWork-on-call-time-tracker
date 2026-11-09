const REPO = 'https://github.com/fpvsonderling/StandwiseWork-on-call-time-tracker';
const DOWNLOAD_URL = `${REPO}/releases`;

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!,
  );
}

export interface InviteEmailInput {
  to: string;
  orgName: string;
  inviterName: string;
  code: string;
}

/**
 * A document for the `mail` collection, in the format of the Firebase
 * "Trigger Email" extension (docs/SETUP.md). Without the extension the
 * document just stays there; admins can still share the code shown in the
 * app.
 */
export function inviteEmail({ to, orgName, inviterName, code }: InviteEmailInput) {
  const link = `standwise://join?code=${encodeURIComponent(code)}`;
  const subject = `${inviterName} invited you to ${orgName} on Standwise`;
  const text = [
    `${inviterName} invited you to join ${orgName} on Standwise, the work and standby time tracker.`,
    '',
    '1. Install Standwise: ' + DOWNLOAD_URL,
    `2. Sign in with Google as ${to}.`,
    `3. The invitation to ${orgName} appears in the app: tap "Join". No code needed.`,
    '',
    `If the invitation does not show up, use "Join with an invite code" and type: ${code}`,
    `If the app is already installed, this link opens it: ${link}`,
    '',
    'The invitation is valid for 7 days. If you did not expect this email, ignore it.',
  ].join('\n');
  const e = escapeHtml;
  const html = `<p>${e(inviterName)} invited you to join <b>${e(orgName)}</b> on Standwise, the work and standby time tracker.</p>
<ol>
<li>Install Standwise: <a href="${DOWNLOAD_URL}">${DOWNLOAD_URL}</a></li>
<li>Sign in with Google as <b>${e(to)}</b>.</li>
<li>The invitation to <b>${e(orgName)}</b> appears in the app: tap <b>Join</b>. No code needed.</li>
</ol>
<p>If the invitation does not show up, use “Join with an invite code” and type:</p>
<p style="font-size:24px;font-family:monospace;letter-spacing:2px"><b>${e(code)}</b></p>
<p>If the app is already installed: <a href="${e(link)}">open the invite in Standwise</a>.</p>
<p style="color:#666">The invitation is valid for 7 days. If you did not expect this email, ignore it.</p>`;
  return { to: [to], message: { subject, text, html } };
}
