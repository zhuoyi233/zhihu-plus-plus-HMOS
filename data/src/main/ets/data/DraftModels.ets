import { isSafeDecimalContentId, isSafeLocalDraftId, JsonArrayValue, parseStrictJson } from 'core';
import { utf8Encode } from '../network/Utf8';

export const DRAFT_ACCOUNT_KEY_PREFIX: string = 'sha256:';
export const MAX_DRAFT_TITLE_LENGTH: number = 200;
export const MAX_DRAFT_HTML_LENGTH: number = 1024 * 1024;
export const MAX_DRAFT_REFERENCE_JSON_LENGTH: number = 64 * 1024;

export enum ContentDraftKind {
  ANSWER = 'answer',
  PIN = 'pin'
}

/**
 * 账号键只保存稳定账号标识的 SHA-256 摘要，绝不能传入或从 Cookie 推导。
 * 该值也是 RDB 的账号隔离边界，而不是对用户展示的身份信息。
 */
export interface DraftAccountScope {
  readonly accountKey: string;
}

export interface ContentDraftIdentity extends DraftAccountScope {
  readonly draftKey: string;
  readonly kind: ContentDraftKind;
  readonly targetId: string;
}

export interface ContentDraftMetadata extends ContentDraftIdentity {
  readonly remoteContentId?: string;
  readonly title: string;
  readonly plainTextLength: number;
  readonly tocEnabled: boolean;
  readonly imageRefsJson: string;
  readonly topicRefsJson: string;
  readonly dirty: boolean;
  readonly version: number;
  readonly createdAt: number;
  readonly updatedAt: number;
}

export interface ContentDraftSaveInput extends ContentDraftIdentity {
  readonly html: string;
  readonly remoteContentId?: string;
  readonly title: string;
  readonly plainTextLength: number;
  readonly tocEnabled: boolean;
  readonly imageRefsJson: string;
  readonly topicRefsJson: string;
  readonly dirty: boolean;
}

export function isSafeDraftAccountKey(value: string | undefined): boolean {
  return typeof value === 'string' &&
    /^sha256:[0-9a-f]{64}$/.test(value);
}

export async function hashDraftAccountId(stableAccountId: string): Promise<string> {
  if (!isSafeStableAccountId(stableAccountId)) {
    throw new Error('Draft account identifier is invalid');
  }
  return DRAFT_ACCOUNT_KEY_PREFIX + sha256Hex(`zhihu-plus:draft-account:v1:${stableAccountId}`);
}

export function createAnswerDraftIdentity(accountKey: string, questionId: string): ContentDraftIdentity {
  return createIdentity(accountKey, ContentDraftKind.ANSWER, questionId);
}

export function createPinDraftIdentity(accountKey: string, localDraftId: string): ContentDraftIdentity {
  return createIdentity(accountKey, ContentDraftKind.PIN, localDraftId);
}

export function validateContentDraftIdentity(identity: ContentDraftIdentity): void {
  if (!isSafeDraftAccountKey(identity.accountKey) || !isSafeDraftKind(identity.kind) ||
    !isSafeDraftTarget(identity.kind, identity.targetId) ||
    identity.draftKey !== buildDraftKey(identity.accountKey, identity.kind, identity.targetId)) {
    throw new Error('Draft identity is invalid');
  }
}

export function validateContentDraftSaveInput(input: ContentDraftSaveInput): void {
  validateContentDraftIdentity(input);
  if (!isSafeDraftHtml(input.html) || !isSafeDraftText(input.title, MAX_DRAFT_TITLE_LENGTH) ||
    typeof input.tocEnabled !== 'boolean' || typeof input.dirty !== 'boolean' ||
    !Number.isSafeInteger(input.plainTextLength) || input.plainTextLength < 0 ||
    input.plainTextLength > MAX_DRAFT_HTML_LENGTH ||
    (input.remoteContentId !== undefined && !isSafeDecimalContentId(input.remoteContentId)) ||
    !isSafeDraftReferenceJson(input.imageRefsJson) || !isSafeDraftReferenceJson(input.topicRefsJson)) {
    throw new Error('Draft content is invalid');
  }
}

export function validateContentDraftMetadata(metadata: ContentDraftMetadata): void {
  validateContentDraftSaveInput({
    draftKey: metadata.draftKey,
    accountKey: metadata.accountKey,
    kind: metadata.kind,
    targetId: metadata.targetId,
    html: '',
    remoteContentId: metadata.remoteContentId,
    title: metadata.title,
    plainTextLength: metadata.plainTextLength,
    tocEnabled: metadata.tocEnabled,
    imageRefsJson: metadata.imageRefsJson,
    topicRefsJson: metadata.topicRefsJson,
    dirty: metadata.dirty
  });
  if (!Number.isSafeInteger(metadata.version) || metadata.version <= 0 ||
    !isSafeTimestamp(metadata.createdAt) || !isSafeTimestamp(metadata.updatedAt) ||
    metadata.updatedAt < metadata.createdAt) {
    throw new Error('Draft metadata is invalid');
  }
}

function createIdentity(accountKey: string, kind: ContentDraftKind, targetId: string): ContentDraftIdentity {
  if (!isSafeDraftAccountKey(accountKey) || !isSafeDraftKind(kind) || !isSafeDraftTarget(kind, targetId)) {
    throw new Error('Draft identity is invalid');
  }
  return {
    accountKey: accountKey,
    kind: kind,
    targetId: targetId,
    draftKey: buildDraftKey(accountKey, kind, targetId)
  };
}

function buildDraftKey(accountKey: string, kind: ContentDraftKind, targetId: string): string {
  return `${kind}:${accountKey}:${targetId}`;
}

function isSafeDraftKind(value: ContentDraftKind): boolean {
  return value === ContentDraftKind.ANSWER || value === ContentDraftKind.PIN;
}

function isSafeDraftTarget(kind: ContentDraftKind, targetId: string): boolean {
  return kind === ContentDraftKind.ANSWER
    ? isSafeDecimalContentId(targetId)
    : isSafeLocalDraftId(targetId);
}

function isSafeStableAccountId(value: string): boolean {
  return typeof value === 'string' && value.length >= 1 && value.length <= 200 &&
    !/[\u0000-\u001F\u007F-\u009F]/.test(value);
}

function isSafeDraftHtml(value: string): boolean {
  return typeof value === 'string' && value.length <= MAX_DRAFT_HTML_LENGTH && !/\u0000/.test(value);
}

function isSafeDraftText(value: string, maxLength: number): boolean {
  return typeof value === 'string' && value.length <= maxLength &&
    !/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/.test(value);
}

function isSafeDraftReferenceJson(value: string): boolean {
  if (typeof value !== 'string' || value.length > MAX_DRAFT_REFERENCE_JSON_LENGTH) {
    return false;
  }
  try {
    return parseStrictJson(value) instanceof JsonArrayValue;
  } catch (_error) {
    return false;
  }
}

function isSafeTimestamp(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0 && value <= 8640000000000000;
}

/** 纯 ArkTS SHA-256，避免把账号隔离边界依赖到高版本 Crypto Kit runtime。 */
function sha256Hex(value: string): string {
  const input = new Uint8Array(utf8Encode(value));
  const originalLength = input.length;
  const paddedLength = Math.ceil((originalLength + 9) / 64) * 64;
  const padded = new Uint8Array(paddedLength);
  padded.set(input);
  padded[originalLength] = 0x80;
  const bitLength = originalLength * 8;
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  padded[paddedLength - 8] = (high >>> 24) & 0xff;
  padded[paddedLength - 7] = (high >>> 16) & 0xff;
  padded[paddedLength - 6] = (high >>> 8) & 0xff;
  padded[paddedLength - 5] = high & 0xff;
  padded[paddedLength - 4] = (low >>> 24) & 0xff;
  padded[paddedLength - 3] = (low >>> 16) & 0xff;
  padded[paddedLength - 2] = (low >>> 8) & 0xff;
  padded[paddedLength - 1] = low & 0xff;

  const state = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ]);
  const words = new Uint32Array(64);
  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let index = 0; index < 16; index += 1) {
      const base = offset + index * 4;
      words[index] = ((padded[base] << 24) | (padded[base + 1] << 16) |
        (padded[base + 2] << 8) | padded[base + 3]) >>> 0;
    }
    for (let index = 16; index < 64; index += 1) {
      const first = words[index - 15];
      const second = words[index - 2];
      words[index] = (smallSigma0(first) + words[index - 16] + smallSigma1(second) + words[index - 7]) >>> 0;
    }
    let a = state[0];
    let b = state[1];
    let c = state[2];
    let d = state[3];
    let e = state[4];
    let f = state[5];
    let g = state[6];
    let h = state[7];
    for (let index = 0; index < 64; index += 1) {
      const nextOne = (h + bigSigma1(e) + ((e & f) ^ (~e & g)) + SHA256_CONSTANTS[index] + words[index]) >>> 0;
      const nextZero = (bigSigma0(a) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + nextOne) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (nextOne + nextZero) >>> 0;
    }
    state[0] = (state[0] + a) >>> 0;
    state[1] = (state[1] + b) >>> 0;
    state[2] = (state[2] + c) >>> 0;
    state[3] = (state[3] + d) >>> 0;
    state[4] = (state[4] + e) >>> 0;
    state[5] = (state[5] + f) >>> 0;
    state[6] = (state[6] + g) >>> 0;
    state[7] = (state[7] + h) >>> 0;
  }
  let result = '';
  for (let index = 0; index < state.length; index += 1) {
    result += state[index].toString(16).padStart(8, '0');
  }
  return result;
}

function rotateRight(value: number, shift: number): number {
  return (value >>> shift) | (value << (32 - shift));
}

function smallSigma0(value: number): number {
  return rotateRight(value, 7) ^ rotateRight(value, 18) ^ (value >>> 3);
}

function smallSigma1(value: number): number {
  return rotateRight(value, 17) ^ rotateRight(value, 19) ^ (value >>> 10);
}

function bigSigma0(value: number): number {
  return rotateRight(value, 2) ^ rotateRight(value, 13) ^ rotateRight(value, 22);
}

function bigSigma1(value: number): number {
  return rotateRight(value, 6) ^ rotateRight(value, 11) ^ rotateRight(value, 25);
}

const SHA256_CONSTANTS: Uint32Array = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]);
