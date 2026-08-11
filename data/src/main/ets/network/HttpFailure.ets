export enum HttpFailureKind {
  AUTHENTICATION = 'authentication',
  RATE_LIMITED = 'rate_limited',
  CLIENT = 'client',
  SERVER = 'server',
  TIMEOUT = 'timeout',
  NETWORK = 'network',
  CANCELLED = 'cancelled',
  BUSY = 'busy'
}

export function classifyHttpStatus(statusCode: number): HttpFailureKind | undefined {
  if (statusCode >= 300 && statusCode < 400) {
    return HttpFailureKind.CLIENT;
  }
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
  if (errorCode === 2300028) {
    return HttpFailureKind.TIMEOUT;
  }
  if (errorCode === 2300047) {
    return HttpFailureKind.CLIENT;
  }
  return HttpFailureKind.NETWORK;
}

export function isRetryableHttpFailure(kind: HttpFailureKind): boolean {
  return kind === HttpFailureKind.RATE_LIMITED || kind === HttpFailureKind.SERVER ||
    kind === HttpFailureKind.TIMEOUT || kind === HttpFailureKind.NETWORK;
}

export function describeHttpFailure(kind: HttpFailureKind, statusCode?: number): string {
  switch (kind) {
    case HttpFailureKind.AUTHENTICATION:
      return statusCode === undefined ? '需要有效登录态' : `HTTP ${statusCode}（需要有效登录态）`;
    case HttpFailureKind.RATE_LIMITED:
      return 'HTTP 429（请求过于频繁）';
    case HttpFailureKind.CLIENT:
      return statusCode === undefined ? '请求地址不受信任' : `HTTP ${statusCode}（客户端请求被拒绝）`;
    case HttpFailureKind.SERVER:
      return `HTTP ${statusCode}（服务端暂时不可用）`;
    case HttpFailureKind.TIMEOUT:
      return statusCode === undefined ? '请求超时' : `HTTP ${statusCode}（请求超时）`;
    case HttpFailureKind.CANCELLED:
      return '请求已取消';
    case HttpFailureKind.BUSY:
      return '已有 HTTP 请求正在进行';
    default:
      return '网络连接失败';
  }
}

export class HttpFailure extends Error {
  readonly kind: HttpFailureKind;
  readonly status?: number;
  readonly transportCode?: number;
  readonly retryable: boolean;

  constructor(kind: HttpFailureKind, status?: number, transportCode?: number) {
    super(describeHttpFailure(kind, status));
    this.name = 'HttpFailure';
    this.kind = kind;
    this.status = status;
    this.transportCode = transportCode;
    this.retryable = isRetryableHttpFailure(kind);
  }
}

export function httpFailureFromStatus(statusCode: number): HttpFailure | undefined {
  const kind = classifyHttpStatus(statusCode);
  return kind === undefined ? undefined : new HttpFailure(kind, statusCode);
}

export function httpFailureFromTransport(errorCode?: number): HttpFailure {
  return new HttpFailure(classifyTransportErrorCode(errorCode), undefined, errorCode);
}
