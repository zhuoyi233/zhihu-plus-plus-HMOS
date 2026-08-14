import {
  JsonArrayValue,
  JsonBooleanValue,
  jsonIntegerLiteral,
  jsonNumber,
  jsonObject,
  jsonString,
  JsonNullValue,
  JsonNumberValue,
  JsonObjectValue,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import {
  PageCursor,
  PeopleContentItem,
  PeopleContentKind,
  PeopleContentPage,
  PeopleContentSection
} from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}

function root(json: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, '响应不是有效 JSON');
    }
  }
  throw invalid('用户内容响应结构无效');
}

function id(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function text(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  const result = jsonString(value);
  if (result === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function requiredText(value: JsonValue | undefined, field: string): string {
  const result = text(value, field);
  if (result.trim().length === 0) {
    throw invalid(`${field} 不能为空`);
  }
  return result;
}

function number(value: JsonValue | undefined, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return 0;
  }
  const result = jsonNumber(value);
  if (result === undefined || !Number.isFinite(result) || result < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return result;
}

function cursor(object: JsonObjectValue | undefined): PageCursor {
  const isEnd = object === undefined ? true : object.get('is_end');
  const end = isEnd === undefined || isEnd instanceof JsonNullValue ? true :
    isEnd instanceof JsonBooleanValue ? isEnd.value : true;
  if (isEnd !== undefined && !(isEnd instanceof JsonNullValue) && !(isEnd instanceof JsonBooleanValue)) {
    throw invalid('用户内容 paging.is_end 类型无效');
  }
  const nextValue = object?.get('next');
  const next = nextValue === undefined || nextValue instanceof JsonNullValue ? undefined : text(nextValue, '用户内容 paging.next');
  return {
    isEnd: end,
    isStart: true,
    next: next,
    page: 0,
    total: 0
  };
}

function answer(object: JsonObjectValue): PeopleContentItem {
  const question = jsonObject(object.get('question'));
  if (question === undefined) {
    throw invalid('回答 question 结构无效');
  }
  return {
    kind: PeopleContentKind.ANSWER,
    id: id(object.get('id'), 'answer.id'),
    title: requiredText(question.get('title') ?? question.get('name'), 'answer.question.title'),
    excerpt: text(object.get('excerpt') ?? object.get('content'), 'answer.excerpt'),
    voteupCount: number(object.get('voteup_count'), 'answer.voteup_count'),
    commentCount: number(object.get('comment_count'), 'answer.comment_count'),
    createdAt: number(object.get('created_time'), 'answer.created_time')
  };
}

function article(object: JsonObjectValue): PeopleContentItem {
  return {
    kind: PeopleContentKind.ARTICLE,
    id: id(object.get('id'), 'article.id'),
    title: requiredText(object.get('title'), 'article.title'),
    excerpt: text(object.get('excerpt') ?? object.get('content'), 'article.excerpt'),
    voteupCount: number(object.get('voteup_count'), 'article.voteup_count'),
    commentCount: number(object.get('comment_count'), 'article.comment_count'),
    createdAt: number(object.get('created') ?? object.get('created_time'), 'article.created')
  };
}

function pin(object: JsonObjectValue): PeopleContentItem {
  return {
    kind: PeopleContentKind.PIN,
    id: id(object.get('id'), 'pin.id'),
    title: '想法',
    excerpt: text(object.get('content') ?? object.get('excerpt'), 'pin.content'),
    voteupCount: number(object.get('like_count'), 'pin.like_count'),
    commentCount: number(object.get('comment_count'), 'pin.comment_count'),
    createdAt: number(object.get('created') ?? object.get('created_time'), 'pin.created')
  };
}

function item(section: PeopleContentSection, value: JsonValue): PeopleContentItem | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    throw invalid('用户内容 item 结构无效');
  }
  if (section === PeopleContentSection.ANSWERS) {
    return answer(object);
  }
  if (section === PeopleContentSection.ARTICLES) {
    return article(object);
  }
  const type = jsonString(object.get('type'));
  const target = jsonObject(object.get('target'));
  if (target === undefined) {
    return undefined;
  }
  if (type !== undefined && type !== 'feed') {
    return undefined;
  }
  const targetType = jsonString(target.get('type'));
  if (targetType === PeopleContentKind.ANSWER) {
    return answer(target);
  }
  if (targetType === PeopleContentKind.ARTICLE) {
    return article(target);
  }
  if (targetType === 'pin') {
    return pin(target);
  }
  return undefined;
}

export function decodePeopleContentPage(json: string, section: PeopleContentSection): PeopleContentPage {
  const object = root(json);
  const error = object.get('error');
  if (error !== undefined && !(error instanceof JsonNullValue)) {
    throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR, '知乎接口返回错误');
  }
  const data = object.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw invalid('用户内容 data 不能为空');
  }
  const pagingValue = object.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) && !(pagingValue instanceof JsonObjectValue)) {
    throw invalid('用户内容 paging 结构无效');
  }
  const items: Array<PeopleContentItem> = [];
  data.items.forEach((value: JsonValue): void => {
    const decoded = item(section, value);
    if (decoded !== undefined) {
      items.push(decoded);
    }
  });
  return { items: items, cursor: cursor(pagingValue instanceof JsonObjectValue ? pagingValue : undefined) };
}
