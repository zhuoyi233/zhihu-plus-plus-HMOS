const COOKIE_ATTRIBUTES: Set<string> = new Set<string>([
  'domain', 'path', 'expires', 'max-age', 'httponly', 'secure', 'samesite'
]);
const COOKIE_NAME_CHARACTERS = "!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
export const COOKIE_HEADER_MAX_LENGTH = 8192;
export const COOKIE_FIELD_MAX_COUNT = 64;
export const COOKIE_NAME_MAX_LENGTH = 128;
export const COOKIE_VALUE_MAX_LENGTH = 4096;

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

export function copySessionCookies(cookies: Array<SessionCookie>): Array<SessionCookie> {
  return cookies.map((cookie: SessionCookie): SessionCookie => ({
    name: cookie.name,
    value: cookie.value,
    expiresAt: cookie.expiresAt
  }));
}

function isValidCookieName(name: string): boolean {
  if (name.length === 0 || name.length > COOKIE_NAME_MAX_LENGTH) {
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
  if (value.length > COOKIE_VALUE_MAX_LENGTH) {
    return false;
  }
  for (let index = 0; index < value.length; index += 1) {
    const character = value.charCodeAt(index);
    if (character === 0 || character === 10 || character === 13 || character === 59) {
      return false;
    }
  }
  return true;
}

export function parseCookieAssignments(rawCookie: string, includeEmptyValues: boolean = false): Array<SessionCookie> {
  if (rawCookie.length === 0 || rawCookie.length > COOKIE_HEADER_MAX_LENGTH) {
    return [];
  }
  const cookies: Array<SessionCookie> = [];
  const assignments = rawCookie.split(';');
  if (assignments.length > COOKIE_FIELD_MAX_COUNT) {
    return [];
  }
  for (let index = 0; index < assignments.length; index += 1) {
    const assignment = assignments[index].trim();
    const separator = assignment.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    const name = assignment.substring(0, separator).trim();
    const value = assignment.substring(separator + 1).trim();
    if (!isValidCookieName(name) || (!includeEmptyValues && value.length === 0) || !isSafeCookieValue(value) ||
      COOKIE_ATTRIBUTES.has(name.toLowerCase())) {
      continue;
    }
    const existingIndex = cookies.findIndex((cookie: SessionCookie) => cookie.name === name);
    if (existingIndex >= 0) {
      cookies[existingIndex] = { name: name, value: value };
    } else {
      cookies.push({ name: name, value: value });
    }
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
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload) || payload.version !== 1 ||
    typeof payload.savedAt !== 'number' || !Number.isFinite(payload.savedAt) || !Array.isArray(payload.cookies) ||
    payload.cookies.length > COOKIE_FIELD_MAX_COUNT) {
    throw new Error('Unsupported cookie session format');
  }
  payload.cookies.forEach((cookie: SessionCookie): void => {
    if (cookie === null || typeof cookie !== 'object' || Array.isArray(cookie) ||
      typeof cookie.name !== 'string' || typeof cookie.value !== 'string' ||
      !isValidCookieName(cookie.name) || !isSafeCookieValue(cookie.value) ||
      (cookie.expiresAt !== undefined &&
        (typeof cookie.expiresAt !== 'number' || !Number.isFinite(cookie.expiresAt)))) {
      throw new Error('Unsupported cookie session format');
    }
  });
  return {
    version: 1,
    savedAt: payload.savedAt,
    cookies: copySessionCookies(payload.cookies)
  };
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
