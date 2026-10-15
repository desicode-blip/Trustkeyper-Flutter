export function linkedInProfile(value) {
  if (value?.skipped === true && !value.url) return { skipped: true, url: '' };
  if (typeof value?.url !== 'string' || value.url.length > 500) throw new Error('Invalid LinkedIn profile');
  const url = new URL(/^https?:\/\//i.test(value.url.trim()) ? value.url.trim() : `https://${value.url.trim()}`);
  if (!['https:', 'http:'].includes(url.protocol) || !['linkedin.com', 'www.linkedin.com'].includes(url.hostname.toLowerCase()) ||
    url.username || url.password || url.port || !/^\/in\/[a-z0-9_%.-]+\/?$/i.test(url.pathname)) throw new Error('Invalid LinkedIn profile');
  return { skipped: false, url: `https://www.linkedin.com${url.pathname.replace(/\/$/, '')}` };
}
