import {
  ChannelContentItem,
  ChannelDailyStoryItem,
  ChannelFeedItem,
  ChannelFeedItemKind,
  ChannelFeedPage,
  DailyStorySummary,
  isDailyFeedDateCursor
} from './ChannelFeedModels';
import { FeedItem, FeedPage, PageCursor } from './DomainModels';
import {
  JsonArrayValue,
  jsonIntegerLiteral,
  jsonNumber,
  JsonNumberValue,
  jsonObject,
  JsonObjectValue,
  jsonString,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import { decodeFeedPage, DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

function root(json: string, label: string): JsonObjectValue {
  try {
    const value = parseStrictJson(json);
    if (value instanceof JsonObjectValue) {
      return value;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${label} 响应不是有效 JSON`);
    }
  }
  throw invalid(`${label} 响应结构无效`);
}

function requiredArray(object: JsonObjectValue, name: string, field: string): JsonArrayValue {
  const value = object.get(name);
  if (value instanceof JsonArrayValue) {
    return value;
  }
  throw invalid(`${field} 不能为空`);
}

function wireId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^\d{1,30}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredText(value: JsonValue | undefined, field: string): string {
  const text = jsonString(value);
  if (text !== undefined && text.trim().length > 0) {
    return text;
  }
  throw invalid(`${field} 不能为空`);
}

function optionalText(value: JsonValue | undefined, field: string): string {
  if (value === undefined) {
    return '';
  }
  const text = jsonString(value);
  if (text === undefined) {
    throw invalid(`${field} 类型无效`);
  }
  return text;
}

function topicIds(target: JsonObjectValue | undefined): Array<string> {
  if (target === undefined) {
    return [];
  }
  let value = target.get('bound_topic_ids');
  const question = jsonObject(target.get('question'));
  if (value === undefined && question !== undefined) {
    value = question.get('bound_topic_ids');
  }
  if (value === undefined) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid('feed.target.bound_topic_ids 类型无效');
  }
  const result: Array<string> = [];
  value.items.forEach((item: JsonValue): void => {
    const id = wireId(item, 'feed.target.bound_topic_ids');
    if (!result.includes(id)) {
      result.push(id);
    }
  });
  return result;
}

export function decodeChannelContentPage(json: string): ChannelFeedPage {
  const object = root(json, 'Feed');
  const data = requiredArray(object, 'data', 'feed.data');
  const targetsByItemId: Map<string, JsonObjectValue> = new Map<string, JsonObjectValue>();
  data.items.forEach((value: JsonValue): void => {
    const item = jsonObject(value);
    if (item === undefined) {
      return;
    }
    const type = jsonString(item.get('type'));
    const target = jsonObject(item.get('target'));
    const targetType = target === undefined ? undefined : jsonString(target.get('type'));
    const skipped = type === 'invited_answer' || type === 'tab_list' || type === 'feed_item_index_group';
    const unsupported = targetType !== undefined && targetType.trim().length > 0 && targetType !== 'answer' &&
      targetType !== 'article' && targetType !== 'question';
    if (skipped || unsupported) {
      return;
    }
    const keyValue = item.get('id');
    let key: string | undefined;
    if (keyValue instanceof JsonStringValue && keyValue.value.trim().length > 0) {
      key = keyValue.value;
    } else {
      const integerLiteral = jsonIntegerLiteral(keyValue);
      if (integerLiteral !== undefined && integerLiteral.length <= 30) {
        key = integerLiteral;
      }
    }
    if (key !== undefined && target !== undefined) {
      targetsByItemId.set(key, target);
    }
  });
  const decoded: FeedPage = decodeFeedPage(json);
  const items: Array<ChannelFeedItem> = decoded.items.map((item: FeedItem): ChannelContentItem => {
    if (!/^\d{1,30}$/.test(item.target.id)) {
      throw invalid('feed.target.id 缺少有效十进制 ID');
    }
    return {
      kind: ChannelFeedItemKind.CONTENT,
      feedItem: item,
      topicIds: topicIds(targetsByItemId.get(item.id))
    };
  });
  return { items: items, cursor: decoded.cursor };
}

export function decodeDailyFeedPage(json: string): ChannelFeedPage {
  const object = root(json, '日报');
  const date = requiredText(object.get('date'), 'daily.date');
  if (!isDailyFeedDateCursor(date)) {
    throw invalid('daily.date 格式无效');
  }
  const stories = requiredArray(object, 'stories', 'daily.stories');
  const items: Array<ChannelFeedItem> = stories.items.map((value: JsonValue): ChannelDailyStoryItem => {
    const story = jsonObject(value);
    if (story === undefined) {
      throw invalid('daily.story 结构无效');
    }
    const imagesValue = story.get('images');
    let imageUrl: string | undefined;
    if (imagesValue !== undefined) {
      if (!(imagesValue instanceof JsonArrayValue)) {
        throw invalid('daily.story.images 类型无效');
      }
      let firstImage: JsonValue | undefined;
      imagesValue.items.forEach((candidate: JsonValue): void => {
        if (firstImage === undefined) {
          firstImage = candidate;
        }
      });
      if (firstImage !== undefined) {
        const text = optionalText(firstImage, 'daily.story.images[0]');
        imageUrl = text.length === 0 ? undefined : text;
      }
    }
    const typeValue = story.get('type');
    const storyType = typeValue === undefined ? 0 : jsonNumber(typeValue);
    if (storyType === undefined || !Number.isSafeInteger(storyType) || storyType < 0) {
      throw invalid('daily.story.type 类型无效');
    }
    const summary: DailyStorySummary = {
      id: wireId(story.get('id'), 'daily.story.id'),
      title: requiredText(story.get('title'), 'daily.story.title'),
      hint: optionalText(story.get('hint'), 'daily.story.hint'),
      url: optionalText(story.get('url'), 'daily.story.url'),
      imageUrl: imageUrl,
      storyType: storyType,
      date: date
    };
    return { kind: ChannelFeedItemKind.DAILY_STORY, story: summary };
  });
  const cursor: PageCursor = {
    isEnd: false,
    isStart: false,
    next: date,
    page: -1,
    total: items.length
  };
  return { items: items, cursor: cursor };
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
