import {
  isSafeDecimalContentId,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson
} from 'core';
import { HttpFailure, HttpFailureKind } from '../network/HttpFailure';
import { ZhihuHttpMethod } from '../network/ZhihuHttpClient';

export const MAX_CREATION_HTML_LENGTH: number = 1024 * 1024;
export const MAX_PIN_TITLE_LENGTH: number = 200;
export const MAX_PIN_TOPIC_COUNT: number = 5;
export const MAX_PIN_IMAGE_COUNT: number = 9;
export const MAX_PIN_TEXT_LENGTH: number = 1000000;

export interface ExistingAnswerForEditing {
  readonly answerId: string;
  readonly html: string;
  readonly tocEnabled: boolean;
}

export interface AnswerPublishInput {
  readonly questionId: string;
  readonly answerId?: string;
  readonly html: string;
  readonly tocEnabled: boolean;
  /** `${epochMilliseconds},${uuid}`；由平台随机源生成，合同层只校验格式。 */
  readonly traceId: string;
}

export interface AnswerPublishRepository {
  findMyAnswerId(questionId: string): Promise<string | undefined>;
  fetchAnswerForEditing(answerId: string): Promise<ExistingAnswerForEditing | undefined>;
  saveRemoteDraft(input: AnswerPublishInput): Promise<void>;
  publish(input: AnswerPublishInput): Promise<string>;
  cancel(): void;
}

export interface UploadedZhihuImage {
  readonly imageId: string;
  readonly url: string;
  readonly originalUrl: string;
  readonly width: number;
  readonly height: number;
  readonly watermark?: 'watermark' | 'original';
  readonly watermarkUrl?: string;
}

export interface PublishPinTopic {
  readonly topicId: string;
  /** 不含井号的展示名称；发布 body 由合同层添加井号。 */
  readonly displayName: string;
}

export interface PinTopicSuggestion extends PublishPinTopic {
  readonly discussCount: string;
}

export interface PinPublishInput {
  readonly title: string;
  readonly html: string;
  readonly textLength: number;
  readonly images: Array<UploadedZhihuImage>;
  readonly topics: Array<PublishPinTopic>;
  readonly traceId: string;
}

export interface PinPublishRepository {
  recommendTopics(query: string, title: string, contentHtml: string): Promise<Array<PinTopicSuggestion>>;
  saveRemoteDraft(input: PinPublishInput): Promise<void>;
  publish(input: PinPublishInput): Promise<string>;
  cancel(): void;
}

export interface ImageUploadInput {
  /** 仅允许由 ImagePicker 返回的应用可读 URI，具体文件策略在 P4-2 实现。 */
  readonly sourceUri: string;
  readonly mimeType: string;
  readonly byteLength: number;
}

export interface ImageUploadRepository {
  upload(input: ImageUploadInput): Promise<UploadedZhihuImage>;
  cancel(): void;
}

export enum PublishFailureKind {
  AUTHENTICATION = 'authentication',
  FORBIDDEN = 'forbidden',
  RATE_LIMITED = 'rate_limited',
  INVALID_INPUT = 'invalid_input',
  CONFLICT = 'conflict',
  NETWORK = 'network',
  TIMEOUT = 'timeout',
  CANCELLED = 'cancelled',
  SERVER = 'server'
}

export class PublishFailure extends Error {
  readonly kind: PublishFailureKind;
  readonly retryable: boolean;
  /** 所有非成功分支都必须保留本地草稿。 */
  readonly preservesLocalDraft: boolean = true;

  constructor(kind: PublishFailureKind) {
    super(describePublishFailure(kind));
    this.name = 'PublishFailure';
    this.kind = kind;
    this.retryable = kind === PublishFailureKind.RATE_LIMITED || kind === PublishFailureKind.NETWORK ||
      kind === PublishFailureKind.TIMEOUT || kind === PublishFailureKind.SERVER;
  }
}

export interface PublishHttpContract {
  readonly url: string;
  readonly method: ZhihuHttpMethod;
  readonly body?: string;
  readonly useSession: true;
  readonly signWithZse: true;
  readonly includeXsrfToken: boolean;
  readonly refererPath: string;
}

export function buildAnswerRelationshipUrl(questionId: string): string {
  return `https://api.zhihu.com/questions/${requireContentId(questionId)}` +
    '?include=relationship%2Crelationship.my_answer';
}

export function buildAnswerDraftUrl(questionId: string): string {
  return `https://www.zhihu.com/api/v4/questions/${requireContentId(questionId)}/draft`;
}

export function buildContentPublishUrl(): string {
  return 'https://www.zhihu.com/api/v4/content/publish';
}

export function buildPinTopicRecommendationUrl(query: string): string {
  if (!isSafeText(query, MAX_PIN_TITLE_LENGTH) || query.trim().length === 0) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
  return 'https://api.zhihu.com/content/publish/topics/recommend?recommend_type=pin&key_word=' +
    encodeURIComponent(query).replace(/%20/g, '+');
}

export function buildPinRemoteDraftUrl(): string {
  return 'https://api.zhihu.com/content/drafts';
}

export function buildAnswerRelationshipRequest(questionId: string): PublishHttpContract {
  requireContentId(questionId);
  return {
    url: buildAnswerRelationshipUrl(questionId),
    method: ZhihuHttpMethod.GET,
    useSession: true,
    signWithZse: true,
    includeXsrfToken: false,
    refererPath: '/'
  };
}

export function buildAnswerRemoteDraftRequest(input: AnswerPublishInput): PublishHttpContract {
  validateAnswerInput(input);
  return {
    url: buildAnswerDraftUrl(input.questionId),
    method: ZhihuHttpMethod.POST,
    body: buildAnswerDraftBody(input),
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    refererPath: answerRefererPath(input.questionId, input.answerId)
  };
}

/** 获取已有回答的可编辑正文；仅使用固定 include，避免调用方自行拼接详情地址。 */
export function buildAnswerEditingRequest(answerId: string): PublishHttpContract {
  const normalizedAnswerId = requireContentId(answerId);
  return {
    url: 'https://www.zhihu.com/api/v4/answers/' + normalizedAnswerId + '?include=' +
      encodeURIComponent(ANSWER_PUBLISH_INCLUDE),
    method: ZhihuHttpMethod.GET,
    useSession: true,
    signWithZse: true,
    includeXsrfToken: false,
    refererPath: '/'
  };
}

export function buildAnswerPublishRequest(input: AnswerPublishInput): PublishHttpContract {
  validateAnswerInput(input);
  return {
    url: buildContentPublishUrl(),
    method: ZhihuHttpMethod.POST,
    body: buildAnswerPublishBody(input),
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    refererPath: '/'
  };
}

export function buildPinTopicRecommendationRequest(
  query: string,
  title: string,
  contentHtml: string
): PublishHttpContract {
  if (!isSafeText(title, MAX_PIN_TITLE_LENGTH) || !isSafeCreationHtml(contentHtml)) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
  return {
    url: buildPinTopicRecommendationUrl(query),
    method: ZhihuHttpMethod.POST,
    body: '{"title":' + JSON.stringify(title) + ',"content":' + JSON.stringify(contentHtml) + '}',
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    refererPath: '/'
  };
}

export function buildPinRemoteDraftRequest(input: PinPublishInput): PublishHttpContract {
  validatePinInput(input);
  return {
    url: buildPinRemoteDraftUrl(),
    method: ZhihuHttpMethod.POST,
    body: buildPinPublishBody(input),
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    refererPath: '/'
  };
}

export function buildPinPublishRequest(input: PinPublishInput): PublishHttpContract {
  validatePinInput(input);
  return {
    url: buildContentPublishUrl(),
    method: ZhihuHttpMethod.POST,
    body: buildPinPublishBody(input),
    useSession: true,
    signWithZse: true,
    includeXsrfToken: true,
    refererPath: '/'
  };
}

export function buildAnswerDraftBody(input: AnswerPublishInput): string {
  validateAnswerInput(input);
  const tocEnabled = input.tocEnabled ? 'true' : 'false';
  return '{"content":' + JSON.stringify(input.html) +
    ',"draft_type":"normal","delta_time":30,"settings":{' +
    '"reshipment_settings":"allowed","comment_permission":"all","can_reward":false,"tagline":"",' +
    '"disclaimer_status":"close","disclaimer_type":"none","commercial_report_info":{"is_report":true},' +
    '"push_activity":false,"table_of_contents_enabled":' + tocEnabled +
    ',"thank_inviter_status":"close","thank_inviter":""}}';
}

export function buildAnswerPublishBody(input: AnswerPublishInput): string {
  validateAnswerInput(input);
  const tocEnabled = input.tocEnabled ? 'true' : 'false';
  const pcBusinessParams = '{"reshipment_settings":"allowed","comment_permission":"all",' +
    '"reward_setting":{"can_reward":false},"disclaimer_status":"close","disclaimer_type":"none",' +
    '"commercial_report_info":{"is_report":false},"commercial_zhitask_bind_info":null,"is_report":false,' +
    '"table_of_contents_enabled":' + tocEnabled + ',"thank_inviter_status":"close","thank_inviter":""}';
  const draft = input.answerId === undefined
    ? '{"disabled":1,"isPublished":false}'
    : '{"disabled":1,"isPublished":true,"contentId":' + JSON.stringify(input.answerId) + '}';
  return '{"action":"answer","data":{"publish":{"traceId":' + JSON.stringify(input.traceId) +
    '},"hybridInfo":{},"draft":' + draft + ',"extra_info":{"question_id":' +
    JSON.stringify(input.questionId) + ',"publisher":"pc","include":' + JSON.stringify(ANSWER_PUBLISH_INCLUDE) +
    ',"pc_business_params":' + JSON.stringify(pcBusinessParams) + '},"hybrid":{"html":' +
    JSON.stringify(input.html) + '},"reprint":{"reshipment_settings":"allowed"},' +
    '"commentsPermission":{"comment_permission":"all"},"appreciate":{"can_reward":false},' +
    '"publishSwitch":{"draft_type":"normal"},"creationStatement":{"disclaimer_status":"close",' +
    '"disclaimer_type":"none"},"commercialReportInfo":{"isReport":0},"toFollower":{},' +
    '"contentsTables":{"table_of_contents_enabled":' + tocEnabled + '},' +
    '"thanksInvitation":{"thank_inviter_status":"close","thank_inviter":""}}}';
}

export function buildPinPublishBody(input: PinPublishInput): string {
  validatePinInput(input);
  const title = input.title.trim().length > 0 ? ',"title":{"title":' + JSON.stringify(input.title) + '}' : '';
  const hybrid = input.html.trim().length > 0
    ? ',"hybrid":{"html":' + JSON.stringify(input.html) + ',"textLength":' + input.textLength + '}'
    : '';
  const media = input.images.length > 0
    ? ',"media":{"medias":[' + input.images.map((image: UploadedZhihuImage): string => serializePinImage(image)).join(',') + ']}'
    : '';
  const topic = input.topics.length > 0
    ? ',"topic":{"topics":[' + input.topics.map((item: PublishPinTopic): string =>
      '{"topic_id":' + JSON.stringify(item.topicId) + ',"topic_name":' + JSON.stringify(`#${item.displayName}#`) + '}').join(',') + ']}'
    : '';
  return '{"action":"pin","data":{"publish":{"traceId":' + JSON.stringify(input.traceId) +
    '},"commentsPermission":{"comment_permission":"all"},"extra_info":{"view_permission":"all",' +
    '"publisher":"pc"},"draft":{"disabled":1}' + title + hybrid + media + topic + '}}';
}

function serializePinImage(image: UploadedZhihuImage): string {
  const watermark = image.watermark === undefined ? '' : ',"watermark":' + JSON.stringify(image.watermark);
  const watermarkUrl = image.watermarkUrl === undefined ? '' : ',"watermarkUrl":' + JSON.stringify(image.watermarkUrl);
  return '{"image":{"height":' + image.height + ',"width":' + image.width + ',"url":' +
    JSON.stringify(image.url) + ',"originalUrl":' + JSON.stringify(image.originalUrl) + watermark + watermarkUrl + '}}';
}

/** `data.result` 是第二层 JSON；只接受规范数字内容 ID，不暴露原始响应。 */
export function parsePublishedContentId(body: string): string | undefined {
  let outer: JsonObjectValue;
  try {
    const parsed = parseStrictJson(body);
    if (!(parsed instanceof JsonObjectValue)) {
      return undefined;
    }
    outer = parsed;
  } catch (_error) {
    return undefined;
  }
  const data = outer.get('data');
  if (!(data instanceof JsonObjectValue)) {
    return undefined;
  }
  const result = data.get('result');
  if (!(result instanceof JsonStringValue)) {
    return undefined;
  }
  try {
    const nested = parseStrictJson(result.value);
    if (!(nested instanceof JsonObjectValue)) {
      return undefined;
    }
    return readContentId(nested.get('publish')) ?? readContentId(nested.get('id'));
  } catch (_error) {
    return undefined;
  }
}

export function isExistingAnswerConflict(body: string): boolean {
  let parsed: JsonValue;
  try {
    parsed = parseStrictJson(body);
  } catch (_error) {
    return false;
  }
  if (!(parsed instanceof JsonObjectValue)) {
    return false;
  }
  const error = parsed.get('error');
  return isConflictCode(parsed.get('code')) ||
    (error instanceof JsonObjectValue && isConflictCode(error.get('code')));
}

export function toPublishFailure(error: Object): PublishFailure {
  if (error instanceof PublishFailure) {
    return error;
  }
  if (!(error instanceof HttpFailure)) {
    return new PublishFailure(PublishFailureKind.NETWORK);
  }
  switch (error.kind) {
    case HttpFailureKind.AUTHENTICATION:
      return new PublishFailure(error.status === 403 ? PublishFailureKind.FORBIDDEN : PublishFailureKind.AUTHENTICATION);
    case HttpFailureKind.RATE_LIMITED:
      return new PublishFailure(PublishFailureKind.RATE_LIMITED);
    case HttpFailureKind.TIMEOUT:
      return new PublishFailure(PublishFailureKind.TIMEOUT);
    case HttpFailureKind.CANCELLED:
      return new PublishFailure(PublishFailureKind.CANCELLED);
    case HttpFailureKind.SERVER:
      return new PublishFailure(PublishFailureKind.SERVER);
    case HttpFailureKind.CLIENT:
      return new PublishFailure(PublishFailureKind.INVALID_INPUT);
    default:
      return new PublishFailure(PublishFailureKind.NETWORK);
  }
}

function validateAnswerInput(input: AnswerPublishInput): void {
  if (!isSafeDecimalContentId(input.questionId) ||
    (input.answerId !== undefined && !isSafeDecimalContentId(input.answerId)) ||
    !isSafeCreationHtml(input.html) || input.html.trim().length === 0 || !isSafePublishTraceId(input.traceId)) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
}

function validatePinInput(input: PinPublishInput): void {
  if (!isSafeText(input.title, MAX_PIN_TITLE_LENGTH) || !isSafeCreationHtml(input.html) ||
    !Number.isSafeInteger(input.textLength) || input.textLength < 0 || input.textLength > MAX_PIN_TEXT_LENGTH ||
    input.images.length > MAX_PIN_IMAGE_COUNT || input.topics.length > MAX_PIN_TOPIC_COUNT ||
    !isSafePublishTraceId(input.traceId) ||
    (input.title.trim().length === 0 && input.html.trim().length === 0 && input.images.length === 0) ||
    !input.images.every((image: UploadedZhihuImage): boolean => isSafeUploadedImage(image)) ||
    !input.topics.every((topic: PublishPinTopic): boolean => isSafePinTopic(topic))) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
}

function isSafeCreationHtml(value: string): boolean {
  return typeof value === 'string' && value.length <= MAX_CREATION_HTML_LENGTH && !/[\u0000]/.test(value);
}

function isSafeText(value: string, maxLength: number): boolean {
  return typeof value === 'string' && value.length <= maxLength && !/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/.test(value);
}

function isSafePublishTraceId(value: string): boolean {
  return typeof value === 'string' &&
    /^[1-9][0-9]{0,15},[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
}

function isSafeUploadedImage(image: UploadedZhihuImage): boolean {
  return isSafeDecimalContentId(image.imageId) && isSafeImageUrl(image.url) && isSafeImageUrl(image.originalUrl) &&
    Number.isSafeInteger(image.width) && image.width > 0 && Number.isSafeInteger(image.height) && image.height > 0 &&
    (image.watermarkUrl === undefined || isSafeImageUrl(image.watermarkUrl));
}

function isSafeImageUrl(value: string): boolean {
  return typeof value === 'string' && value.length <= 4096 &&
    /^https:\/\/(?:[a-z0-9-]+\.)*zhimg\.com\/[A-Za-z0-9._~%/?=&-]+$/.test(value);
}

function isSafePinTopic(topic: PublishPinTopic): boolean {
  return isSafeDecimalContentId(topic.topicId) && isSafeText(topic.displayName, MAX_PIN_TITLE_LENGTH) &&
    topic.displayName.trim().length > 0 && !topic.displayName.includes('#');
}

function requireContentId(value: string): string {
  if (!isSafeDecimalContentId(value)) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
  return value;
}

function answerRefererPath(questionId: string, answerId?: string): string {
  return `/question/${requireContentId(questionId)}/answer/${answerId === undefined ? '' : requireContentId(answerId)}`;
}

function readContentId(value: JsonValue | undefined): string | undefined {
  if (value instanceof JsonObjectValue) {
    return readContentId(value.get('id'));
  }
  const id = value instanceof JsonStringValue
    ? value.value
    : value instanceof JsonNumberValue ? value.literal : undefined;
  return isSafeDecimalContentId(id) ? id : undefined;
}

function isConflictCode(value: JsonValue | undefined): boolean {
  return (value instanceof JsonNumberValue && value.literal === '103003') ||
    (value instanceof JsonStringValue && value.value === '103003');
}

function describePublishFailure(kind: PublishFailureKind): string {
  switch (kind) {
    case PublishFailureKind.AUTHENTICATION:
      return '登录已失效，请重新登录后继续发布';
    case PublishFailureKind.FORBIDDEN:
      return '发布被拒绝或需要完成安全验证';
    case PublishFailureKind.RATE_LIMITED:
      return '请求过于频繁，请稍后重试';
    case PublishFailureKind.INVALID_INPUT:
      return '发布内容或目标无效';
    case PublishFailureKind.CONFLICT:
      return '该问题已有回答，请转入编辑';
    case PublishFailureKind.TIMEOUT:
      return '发布请求超时，请稍后重试';
    case PublishFailureKind.CANCELLED:
      return '发布请求已取消';
    case PublishFailureKind.SERVER:
      return '服务暂时不可用，请稍后重试';
    default:
      return '网络不可用，请检查连接后重试';
  }
}

const ANSWER_PUBLISH_INCLUDE: string =
  'is_visible,paid_info,paid_info_content,has_column,admin_closed_comment,reward_info,annotation_action,' +
  'annotation_detail,collapse_reason,is_normal,is_sticky,collapsed_by,suggest_edit,comment_count,thanks_count,' +
  'favlists_count,can_comment,content,editable_content,voteup_count,reshipment_settings,comment_permission,' +
  'created_time,updated_time,review_info,relevant_info,question,excerpt,attachment,content_source,is_labeled,' +
  'endorsements,reaction_instruction,ip_info,relationship.is_authorized,voting,is_thanked,is_author,is_nothelp,' +
  'is_favorited;author.vip_info,kvip_info,badge[*].topics;settings.table_of_contents.enabled';
