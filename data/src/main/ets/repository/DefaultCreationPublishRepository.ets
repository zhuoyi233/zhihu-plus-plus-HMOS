import {
  isSafeDecimalContentId,
  JsonArrayValue,
  JsonBooleanValue,
  JsonNullValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson
} from 'core';
import {
  AnswerPublishInput,
  AnswerPublishRepository,
  buildAnswerEditingRequest,
  buildAnswerPublishRequest,
  buildAnswerRelationshipRequest,
  buildAnswerRemoteDraftRequest,
  buildPinPublishRequest,
  buildPinRemoteDraftRequest,
  buildPinTopicRecommendationRequest,
  ExistingAnswerForEditing,
  MAX_CREATION_HTML_LENGTH,
  MAX_PIN_TITLE_LENGTH,
  PinPublishInput,
  PinPublishRepository,
  PinTopicSuggestion,
  PublishFailure,
  PublishFailureKind,
  PublishHttpContract,
  parsePublishedContentId
} from './CreationPublishRepository';
import { ZhihuHttpClient, ZhihuHttpResponse } from '../network/ZhihuHttpClient';

const MAX_TOPIC_SUGGESTION_COUNT: number = 20;
const MAX_DISCUSS_COUNT_LENGTH: number = 200;

/**
 * P4 创作发布的生产仓储。会话 Cookie 只由注入的 ZhihuHttpClient 读取；本类不持久化、记录或暴露
 * Cookie、正文和上游响应。调用方需要将同一会话的 client 注入本仓储。
 */
export class DefaultCreationPublishRepository implements AnswerPublishRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async findMyAnswerId(questionId: string): Promise<string | undefined> {
    const response = await this.execute(buildAnswerRelationshipRequest(questionId));
    return parseMyAnswerId(response.body);
  }

  async fetchAnswerForEditing(answerId: string): Promise<ExistingAnswerForEditing | undefined> {
    const response = await this.execute(buildAnswerEditingRequest(answerId));
    return parseExistingAnswerForEditing(response.body, answerId);
  }

  async saveRemoteDraft(input: AnswerPublishInput): Promise<void> {
    await this.execute(buildAnswerRemoteDraftRequest(input));
  }

  async publish(input: AnswerPublishInput): Promise<string> {
    const response = await this.execute(buildAnswerPublishRequest(input));
    // 回答状态机需要保留 103003 响应以进入“转为编辑”分支；绝不在这里记录响应正文。
    return response.body;
  }

  async recommendTopics(query: string, title: string, contentHtml: string): Promise<Array<PinTopicSuggestion>> {
    const response = await this.execute(buildPinTopicRecommendationRequest(query, title, contentHtml));
    return parsePinTopicSuggestions(response.body);
  }

  async saveRemoteDraftForPin(input: PinPublishInput): Promise<void> {
    await this.execute(buildPinRemoteDraftRequest(input));
  }

  async publishPin(input: PinPublishInput): Promise<string> {
    const response = await this.execute(buildPinPublishRequest(input));
    const publishedId = parsePublishedContentId(response.body);
    if (publishedId === undefined) {
      throw new PublishFailure(PublishFailureKind.SERVER);
    }
    return publishedId;
  }

  /** Pin 仓储通过窄包装复用此实现，避免以不安全的联合参数实现两个同名接口。 */
  async savePinRemoteDraft(input: PinPublishInput): Promise<void> {
    await this.saveRemoteDraftForPin(input);
  }

  async publishPinContent(input: PinPublishInput): Promise<string> {
    return this.publishPin(input);
  }

  private async execute(contract: PublishHttpContract): Promise<ZhihuHttpResponse> {
    const requestGeneration = this.generation;
    const response = await this.httpClient.execute({
      url: contract.url,
      method: contract.method,
      body: contract.body,
      accept: 'application/json',
      useSession: contract.useSession,
      signWithZse: contract.signWithZse,
      includeXsrfToken: contract.includeXsrfToken,
      refererPath: contract.refererPath,
      contentType: contract.body === undefined ? undefined : 'application/json'
    });
    if (requestGeneration !== this.generation) {
      throw new PublishFailure(PublishFailureKind.CANCELLED);
    }
    return response;
  }
}

/** Pin 的调用签名与回答同名，使用窄包装避免不安全的类型断言或页面层 URL 拼接。 */
export class DefaultPinPublishRepository implements PinPublishRepository {
  private readonly creation: DefaultCreationPublishRepository;

  constructor(httpClient: ZhihuHttpClient) {
    this.creation = new DefaultCreationPublishRepository(httpClient);
  }

  recommendTopics(query: string, title: string, contentHtml: string): Promise<Array<PinTopicSuggestion>> {
    return this.creation.recommendTopics(query, title, contentHtml);
  }

  saveRemoteDraft(input: PinPublishInput): Promise<void> {
    return this.creation.savePinRemoteDraft(input);
  }

  publish(input: PinPublishInput): Promise<string> {
    return this.creation.publishPinContent(input);
  }

  cancel(): void {
    this.creation.cancel();
  }
}

function parseMyAnswerId(body: string): string | undefined {
  const root = requireObject(body);
  const relationshipValue = root.get('relationship');
  if (relationshipValue === undefined || relationshipValue instanceof JsonNullValue) {
    return undefined;
  }
  if (!(relationshipValue instanceof JsonObjectValue)) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  const myAnswerValue = relationshipValue.get('my_answer');
  if (myAnswerValue === undefined || myAnswerValue instanceof JsonNullValue) {
    return undefined;
  }
  if (!(myAnswerValue instanceof JsonObjectValue)) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  const isDeleted = myAnswerValue.get('is_deleted');
  if (isDeleted instanceof JsonBooleanValue && isDeleted.value) {
    return undefined;
  }
  const answerId = readContentId(myAnswerValue.get('answer_id'));
  if (answerId === undefined && myAnswerValue.get('answer_id') !== undefined) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  return answerId;
}

function parseExistingAnswerForEditing(body: string, expectedAnswerId: string): ExistingAnswerForEditing | undefined {
  if (!isSafeDecimalContentId(expectedAnswerId)) {
    throw new PublishFailure(PublishFailureKind.INVALID_INPUT);
  }
  const root = requireObject(body);
  if (readContentId(root.get('id')) !== expectedAnswerId) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  const editableContent = readSafeHtml(root.get('editable_content'));
  const content = readSafeHtml(root.get('content'));
  const html = editableContent ?? content;
  if (html === undefined) {
    return undefined;
  }
  return {
    answerId: expectedAnswerId,
    html: html,
    tocEnabled: readTocEnabled(root.get('settings'))
  };
}

function parsePinTopicSuggestions(body: string): Array<PinTopicSuggestion> {
  const root = requireObject(body);
  const data = root.get('data');
  if (!(data instanceof JsonObjectValue)) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  const list = data.get('list');
  if (!(list instanceof JsonArrayValue)) {
    throw new PublishFailure(PublishFailureKind.SERVER);
  }
  const suggestions: Array<PinTopicSuggestion> = [];
  list.items.forEach((item: JsonValue): void => {
    const suggestion = decodePinTopicSuggestion(item);
    if (suggestion !== undefined && suggestions.length < MAX_TOPIC_SUGGESTION_COUNT &&
      !suggestions.some((candidate: PinTopicSuggestion): boolean => candidate.topicId === suggestion.topicId)) {
      suggestions.push(suggestion);
    }
  });
  return suggestions;
}

function decodePinTopicSuggestion(value: JsonValue): PinTopicSuggestion | undefined {
  if (!(value instanceof JsonObjectValue)) {
    return undefined;
  }
  const topicId = readContentId(value.get('topic_id'));
  const name = readSafeText(value.get('name'), MAX_PIN_TITLE_LENGTH);
  if (topicId === undefined || name === undefined || name.trim().length === 0 || name.includes('#')) {
    return undefined;
  }
  const discussValue = value.get('discuss_count');
  let discussCount: string = '';
  if (discussValue !== undefined) {
    const decodedDiscussCount = readSafeText(discussValue, MAX_DISCUSS_COUNT_LENGTH);
    if (decodedDiscussCount === undefined) {
      return undefined;
    }
    discussCount = decodedDiscussCount;
  }
  return {
    topicId: topicId,
    displayName: name,
    discussCount: discussCount
  };
}

function requireObject(body: string): JsonObjectValue {
  try {
    const parsed = parseStrictJson(body);
    if (parsed instanceof JsonObjectValue) {
      return parsed;
    }
  } catch (_error) {
  }
  throw new PublishFailure(PublishFailureKind.SERVER);
}

function readContentId(value: JsonValue | undefined): string | undefined {
  const id = value instanceof JsonStringValue
    ? value.value
    : value instanceof JsonNumberValue ? value.literal : undefined;
  return isSafeDecimalContentId(id) ? id : undefined;
}

function readSafeHtml(value: JsonValue | undefined): string | undefined {
  if (!(value instanceof JsonStringValue)) {
    return undefined;
  }
  return value.value.length <= MAX_CREATION_HTML_LENGTH && !value.value.includes('\u0000') ? value.value : undefined;
}

function readSafeText(value: JsonValue | undefined, maxLength: number): string | undefined {
  if (!(value instanceof JsonStringValue) || value.value.length > maxLength ||
    /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F]/.test(value.value)) {
    return undefined;
  }
  return value.value;
}

function readTocEnabled(value: JsonValue | undefined): boolean {
  if (!(value instanceof JsonObjectValue)) {
    return false;
  }
  const tableOfContents = value.get('table_of_contents');
  if (!(tableOfContents instanceof JsonObjectValue)) {
    return false;
  }
  const enabled = tableOfContents.get('enabled');
  return enabled instanceof JsonBooleanValue && enabled.value;
}
