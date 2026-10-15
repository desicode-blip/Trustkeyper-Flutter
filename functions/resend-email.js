export function createResendEmailSender({ apiKey, from, fetchRequest = fetch }) {
  return async ({ email, code, challengeId }) => {
    if (!apiKey || !from || !/^\d{6}$/.test(code) || !challengeId) {
      throw new Error('Email delivery is not configured.');
    }
    const response = await fetchRequest('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': challengeId },
      body: JSON.stringify({
        from, to: [email], subject: 'Your TrustKeyper verification code',
        text: `Your TrustKeyper verification code is ${code}. It expires in 5 minutes. Do not share this code. If you did not request it, ignore this email.`,
        html: `<h2>Verify your TrustKeyper email</h2><p>Your verification code:</p><p style="font-size:32px;font-weight:bold;letter-spacing:8px">${code}</p><p>Expires in 5 minutes. Do not share this code.</p><p>If you did not request it, ignore this email.</p>`,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('Email provider rejected delivery.');
    const result = await response.json();
    if (typeof result.id !== 'string' || !result.id) throw new Error('Email provider did not confirm acceptance.');
    return { id: result.id };
  };
}
