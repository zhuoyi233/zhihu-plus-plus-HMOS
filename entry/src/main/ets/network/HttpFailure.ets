export enum HttpFailureKind {
  AUTHENTICATION = 'authentication',
  RATE_LIMITED = 'rate_limited',
  CLIENT = 'client',
  SERVER = 'server',
  TIMEOUT = 'timeout',
  NETWORK = 'network',
  CANCELLED = 'cancelled'
}

export function classifyHttpStatus(statusCode: number): HttpFailureKind | undefined {
  if (statusCode === 401 || statusCode === 403) {
    return HttpFailureKind.AUTHENTICATION;
  }
  if (statusCode === 408 || statusCode === 504) {
    return HttpFailureKind.TIMEOUT;
  }
  if (statusCode === 429) {
    return HttpFailureKind.RATE_LIMITED;
  }
  if (statusCode >= 400 && statusCode < 500) {
    return HttpFailureKind.CLIENT;
  }
  if (statusCode >= 500) {
    return HttpFailureKind.SERVER;
  }
  return undefined;
}

export function classifyTransportErrorCode(errorCode?: number): HttpFailureKind {
  return errorCode === 2300028 ? HttpFailureKind.TIMEOUT : HttpFailureKind.NETWORK;
}

export function describeHttpFailure(kind: HttpFailureKind, statusCode?: number): string {
  switch (kind) {
    case HttpFailureKind.AUTHENTICATION:
      return `HTTP ${statusCode}（需要有效登录态）`;
    case HttpFailureKind.RATE_LIMITED:
      return 'HTTP 429（请求过于频繁）';
    case HttpFailureKind.CLIENT:
      return `HTTP ${statusCode}（客户端请求被拒绝）`;
    case HttpFailureKind.SERVER:
      return `HTTP ${statusCode}（服务端暂时不可用）`;
    case HttpFailureKind.TIMEOUT:
      return statusCode === undefined ? '请求超时' : `HTTP ${statusCode}（请求超时）`;
    case HttpFailureKind.CANCELLED:
      return '请求已取消';
    default:
      return '网络连接失败';
  }
}
