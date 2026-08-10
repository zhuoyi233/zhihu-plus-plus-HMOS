export interface ParsedAbsoluteUrl {
  protocol: string;
  hostname: string;
  port: string;
  username: string;
  password: string;
  hasUserInfo: boolean;
  pathname: string;
  params: Map<string, string>;
}

function decodeQueryComponent(value: string): string | undefined {
  try {
    return decodeURIComponent(value.replace(/\+/g, ' '));
  } catch (_) {
    return undefined;
  }
}

function parseQuery(query: string): Map<string, string> | undefined {
  const params: Map<string, string> = new Map();
  if (query.length === 0) {
    return params;
  }
  const pairs = query.split('&');
  for (let index = 0; index < pairs.length; index += 1) {
    const pair = pairs[index];
    const separator = pair.indexOf('=');
    const rawName = separator < 0 ? pair : pair.slice(0, separator);
    const rawValue = separator < 0 ? '' : pair.slice(separator + 1);
    const name = decodeQueryComponent(rawName);
    const value = decodeQueryComponent(rawValue);
    if (name === undefined || value === undefined) {
      return undefined;
    }
    if (!params.has(name)) {
      params.set(name, value);
    }
  }
  return params;
}

export function parseAbsoluteUrl(value: string): ParsedAbsoluteUrl | undefined {
  const match = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(?:\?([^#]*))?(?:#.*)?$/.exec(value);
  if (match === null || match[2].length === 0) {
    return undefined;
  }

  let authority = match[2];
  let username = '';
  let password = '';
  const userInfoSeparator = authority.lastIndexOf('@');
  const hasUserInfo = userInfoSeparator >= 0;
  if (userInfoSeparator >= 0) {
    const userInfo = authority.slice(0, userInfoSeparator);
    authority = authority.slice(userInfoSeparator + 1);
    const passwordSeparator = userInfo.indexOf(':');
    username = passwordSeparator < 0 ? userInfo : userInfo.slice(0, passwordSeparator);
    password = passwordSeparator < 0 ? '' : userInfo.slice(passwordSeparator + 1);
  }

  if (authority.length === 0 || authority.startsWith('[')) {
    return undefined;
  }
  let hostname = authority;
  let port = '';
  const portSeparator = authority.lastIndexOf(':');
  if (portSeparator >= 0) {
    hostname = authority.slice(0, portSeparator);
    port = authority.slice(portSeparator + 1);
    if (port.length === 0 || !/^\d+$/.test(port)) {
      return undefined;
    }
  }
  if (hostname.length === 0) {
    return undefined;
  }

  const params = parseQuery(match[4] ?? '');
  if (params === undefined) {
    return undefined;
  }
  return {
    protocol: `${match[1].toLowerCase()}:`,
    hostname: hostname.toLowerCase(),
    port: port,
    username: username,
    password: password,
    hasUserInfo: hasUserInfo,
    pathname: match[3],
    params: params
  };
}
