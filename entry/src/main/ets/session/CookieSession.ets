const COOKIE_ATTRIBUTES: Set<string> = new Set<string>([
  'domain', 'path', 'expires', 'max-age', 'httponly', 'secure', 'samesite'
]);
const COOKIE_NAME_CHARACTERS = "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

export interface SessionCookie {
  name: string;
  value: string;
  expiresAt?: number;
}

export interface CookieSessionData {
  version: number;
  savedAt: number;
  cookies: Array<SessionCookie>;
}

function isValidCookieName(name: string): boolean {
  if (name.length === 0) {
    return false;
  }
  for (let index = 0; index < name.length; index += 1) {
    if (COOKIE_NAME_CHARACTERS.indexOf(name.charAt(index)) < 0) {
      return false;
    }
  }
  return true;
}

function isSafeCookieValue(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const character = value.charCodeAt(index);
    if (character === 0 || character === 10 || character === 13 || character === 59) {
      return false;
    }
  }
  return true;
}

export function parseCookieAssignments(rawCookie: string): Array<SessionCookie> {
  const cookies: Array<SessionCookie> = [];
  const assignments = rawCookie.split(';');
  for (let index = 0; index < assignments.length; index += 1) {
    const assignment = assignments[index].trim();
    const separator = assignment.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    const name = assignment.substring(0, separator).trim();
    const value = assignment.substring(separator + 1).trim();
    if (!isValidCookieName(name) || value.length === 0 || !isSafeCookieValue(value) ||
      COOKIE_ATTRIBUTES.has(name.toLowerCase())) {
      continue;
    }
    cookies.push({ name: name, value: value });
  }
  return cookies;
}

export function removeExpiredCookies(cookies: Array<SessionCookie>, now: number): Array<SessionCookie> {
  return cookies.filter((cookie: SessionCookie) => cookie.expiresAt === undefined || cookie.expiresAt > now);
}

export function upsertCookie(cookies: Array<SessionCookie>, incoming: SessionCookie): Array<SessionCookie> {
  if (!isValidCookieName(incoming.name) || !isSafeCookieValue(incoming.value)) {
    return cookies.slice();
  }
  if (incoming.name === 'z_c0' && incoming.value.length === 0) {
    return cookies.slice();
  }
  const updated = cookies.filter((cookie: SessionCookie) => cookie.name !== incoming.name);
  if (incoming.value.length > 0) {
    updated.push(incoming);
  }
  return updated;
}

export function toCookieHeader(cookies: Array<SessionCookie>, now: number): string {
  return removeExpiredCookies(cookies, now)
    .filter((cookie: SessionCookie) => isValidCookieName(cookie.name) && isSafeCookieValue(cookie.value) &&
      cookie.value.length > 0)
    .map((cookie: SessionCookie) => `${cookie.name}=${cookie.value}`)
    .join('; ');
}

export function encodeCookieSession(cookies: Array<SessionCookie>, savedAt: number): string {
  const payload: CookieSessionData = {
    version: 1,
    savedAt: savedAt,
    cookies: cookies
  };
  return JSON.stringify(payload);
}

export function decodeCookieSession(serialized: string): CookieSessionData {
  const payload = JSON.parse(serialized) as CookieSessionData;
  if (payload.version !== 1 || !Array.isArray(payload.cookies)) {
    throw new Error('Unsupported cookie session format');
  }
  return payload;
}

export function safeSessionSummary(label: string, cookies: Array<SessionCookie>): string {
  const names = cookies
    .map((cookie: SessionCookie) => cookie.name.replace(/[^A-Za-z0-9_.-]/g, '?'))
    .sort()
    .join(',');
  return `${label}: count=${cookies.length}, names=[${names}]`;
}

export function redactSensitiveText(input: string): string {
  return input
    .replace(/((?:cookie|set-cookie|authorization|x-zse-96)\s*[:=]\s*)[^\r\n]*/gi, '$1[REDACTED]')
    .replace(/((?:z_c0|d_c0|_xsrf)\s*=\s*)[^;\s]*/gi, '$1[REDACTED]');
}
