import {
  JsonArrayValue,
  JsonBooleanValue,
  jsonIntegerLiteral,
  JsonNullValue,
  jsonNumber,
  jsonObject,
  JsonObjectValue,
  jsonString,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import {
  CollectionContentItem,
  CollectionContentKind,
  CollectionContentPage,
  CollectionPage,
  CollectionSummary
} from './CollectionModels';
import { PageCursor } from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}

function root(json: string, label: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${label}响应不是有效 JSON`);
    }
  }
  throw invalid(`${label}响应结构无效`);
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

function booleanValue(value: JsonValue | undefined, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return false;
  }
  if (value instanceof JsonBooleanValue) {
    return value.value;
  }
  throw invalid(`${field} 类型无效`);
}

function cursor(object: JsonObjectValue | undefined, label: string): PageCursor {
  const isEnd = object === undefined ? true : object.get('is_end');
  const end = isEnd === undefined || isEnd instanceof JsonNullValue ? true :
    isEnd instanceof JsonBooleanValue ? isEnd.value : true;
  if (isEnd !== undefined && !(isEnd instanceof JsonNullValue) && !(isEnd instanceof JsonBooleanValue)) {
    throw invalid(`${label} paging.is_end 类型无效`);
  }
  const nextValue = object?.get('next');
  const next = nextValue === undefined || nextValue instanceof JsonNullValue
    ? undefined
    : text(nextValue, `${label} paging.next`);
  return {
    isEnd: end,
    isStart: true,
    next: next,
    page: 0,
    total: 0
  };
}

function collectionSummary(object: JsonObjectValue, allowFavorited: boolean): CollectionSummary {
  const creator = jsonObject(object.get('creator'));
  return {
    id: id(object.get('id'), 'collection.id'),
    title: requiredText(object.get('title'), 'collection.title'),
    description: text(object.get('description'), 'collection.description'),
    isPublic: booleanValue(object.get('is_public'), 'collection.is_public'),
    answerCount: number(object.get('answer_count'), 'collection.answer_count'),
    followerCount: number(object.get('follower_count'), 'collection.follower_count'),
    itemCount: number(object.get('item_count'), 'collection.item_count'),
    likeCount: number(object.get('like_count'), 'collection.like_count'),
    commentCount: number(object.get('comment_count'), 'collection.comment_count'),
    isFavorited: allowFavorited
      ? booleanValue(object.get('is_favorited'), 'collection.is_favorited')
      : false,
    updatedAt: number(object.get('updated_time'), 'collection.updated_time'),
    creatorName: creator === undefined ? undefined : text(creator.get('name'), 'collection.creator.name')
  };
}

interface CollectionObjectPage {
  items: Array<JsonObjectValue>;
  paging: JsonObjectValue | undefined;
}

function collectObjects(json: string, label: string): CollectionObjectPage {
  const object = root(json, label);
  const error = object.get('error');
  if (error !== undefined && !(error instanceof JsonNullValue)) {
    throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR, `${label}接口返回错误`);
  }
  const data = object.get('data');
  if (!(data instanceof JsonArrayValue)) {
    throw invalid(`${label} data 不能为空`);
  }
  const pagingValue = object.get('paging');
  if (pagingValue !== undefined && !(pagingValue instanceof JsonNullValue) &&
    !(pagingValue instanceof JsonObjectValue)) {
    throw invalid(`${label} paging 结构无效`);
  }
  const items: Array<JsonObjectValue> = [];
  data.items.forEach((value: JsonValue): void => {
    const item = jsonObject(value);
    if (item !== undefined) {
      items.push(item);
    }
  });
  return { items: items, paging: pagingValue instanceof JsonObjectValue ? pagingValue : undefined };
}

export function decodeCollectionsPage(json: string): CollectionPage {
  const collected = collectObjects(json, '收藏夹列表');
  return {
    items: collected.items.map((item: JsonObjectValue): CollectionSummary => collectionSummary(item, false)),
    cursor: cursor(collected.paging, '收藏夹列表')
  };
}

export function decodeContentCollections(json: string): Array<CollectionSummary> {
  const collected = collectObjects(json, '内容收藏夹');
  return collected.items.map((item: JsonObjectValue): CollectionSummary => collectionSummary(item, true));
}

export function decodeCollectionDetail(json: string): CollectionSummary {
  const object = root(json, '收藏夹详情');
  const collection = jsonObject(object.get('collection'));
  if (collection === undefined) {
    throw invalid('收藏夹详情 collection 结构无效');
  }
  return collectionSummary(collection, false);
}

function contentItem(value: JsonValue): CollectionContentItem | undefined {
  const object = jsonObject(value);
  if (object === undefined) {
    throw invalid('收藏夹内容 item 结构无效');
  }
  const content = jsonObject(object.get('content'));
  if (content === undefined) {
    throw invalid('收藏夹内容 content 结构无效');
  }
  const type = jsonString(content.get('type'));
  if (type === CollectionContentKind.ANSWER) {
    const question = jsonObject(content.get('question'));
    if (question === undefined) {
      throw invalid('收藏夹回答 question 结构无效');
    }
    return {
      kind: CollectionContentKind.ANSWER,
      id: id(content.get('id'), 'collection.content.id'),
      title: requiredText(question.get('title') ?? question.get('name'), 'collection.content.question.title'),
      excerpt: text(content.get('excerpt') ?? content.get('content'), 'collection.content.excerpt'),
      details: `回答 · ${number(content.get('voteup_count'), 'collection.content.voteup_count')} 赞同 · ` +
        `${number(content.get('comment_count'), 'collection.content.comment_count')} 评论`,
      voteupCount: number(content.get('voteup_count'), 'collection.content.voteup_count'),
      commentCount: number(content.get('comment_count'), 'collection.content.comment_count'),
      authorName: authorName(content.get('author')),
      createdAt: number(content.get('created_time'), 'collection.content.created_time')
    };
  }
  if (type === CollectionContentKind.ARTICLE) {
    return {
      kind: CollectionContentKind.ARTICLE,
      id: id(content.get('id'), 'collection.content.id'),
      title: requiredText(content.get('title'), 'collection.content.title'),
      excerpt: text(content.get('excerpt') ?? content.get('content'), 'collection.content.excerpt'),
      details: `文章 · ${number(content.get('voteup_count'), 'collection.content.voteup_count')} 赞同 · ` +
        `${number(content.get('comment_count'), 'collection.content.comment_count')} 评论`,
      voteupCount: number(content.get('voteup_count'), 'collection.content.voteup_count'),
      commentCount: number(content.get('comment_count'), 'collection.content.comment_count'),
      authorName: authorName(content.get('author')),
      createdAt: number(content.get('created') ?? content.get('created_time'), 'collection.content.created')
    };
  }
  if (type === CollectionContentKind.QUESTION) {
    return {
      kind: CollectionContentKind.QUESTION,
      id: id(content.get('id'), 'collection.content.id'),
      title: requiredText(content.get('title') ?? content.get('name'), 'collection.content.title'),
      excerpt: text(content.get('detail') ?? content.get('excerpt'), 'collection.content.excerpt'),
      details: `问题 · ${number(content.get('answer_count'), 'collection.content.answer_count')} 回答 · ` +
        `${number(content.get('comment_count'), 'collection.content.comment_count')} 评论`,
      voteupCount: number(content.get('answer_count'), 'collection.content.answer_count'),
      commentCount: number(content.get('comment_count'), 'collection.content.comment_count'),
      authorName: authorName(content.get('author')),
      createdAt: number(content.get('created') ?? content.get('created_time'), 'collection.content.created')
    };
  }
  if (type === CollectionContentKind.PIN) {
    return {
      kind: CollectionContentKind.PIN,
      id: id(content.get('id'), 'collection.content.id'),
      title: '想法',
      excerpt: text(content.get('content') ?? content.get('excerpt'), 'collection.content.excerpt'),
      details: `想法 · ${number(content.get('like_count'), 'collection.content.like_count')} 赞 · ` +
        `${number(content.get('comment_count'), 'collection.content.comment_count')} 评论`,
      voteupCount: number(content.get('like_count'), 'collection.content.like_count'),
      commentCount: number(content.get('comment_count'), 'collection.content.comment_count'),
      authorName: authorName(content.get('author')),
      createdAt: number(content.get('created') ?? content.get('created_time'), 'collection.content.created')
    };
  }
  return undefined;
}

function authorName(value: JsonValue | undefined): string | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  const object = jsonObject(value);
  if (object === undefined) {
    return undefined;
  }
  const name = text(object.get('name'), 'collection.content.author.name');
  return name.trim().length === 0 ? undefined : name;
}

export function decodeCollectionItemsPage(json: string): CollectionContentPage {
  const collected = collectObjects(json, '收藏夹内容');
  const decoded: Array<CollectionContentItem> = [];
  collected.items.forEach((item: JsonObjectValue): void => {
    const content = contentItem(item);
    if (content !== undefined) {
      decoded.push(content);
    }
  });
  return { items: decoded, cursor: cursor(collected.paging, '收藏夹内容') };
}
