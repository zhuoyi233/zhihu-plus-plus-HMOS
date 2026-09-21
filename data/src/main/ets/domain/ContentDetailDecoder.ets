import {
  jsonIntegerLiteral,
  JsonArrayValue,
  JsonBooleanValue,
  JsonNullValue,
  JsonNumberValue,
  JsonObjectValue,
  jsonString,
  JsonStringValue,
  JsonValue,
  parseStrictJson,
  StrictJsonError
} from 'core';
import {
  Answer,
  AnswerEndorsementDisplay,
  Article,
  AuthorBadge,
  ContentVoteState,
  Question,
  QuestionTopicSummary,
  SegmentInfoMark,
  SegmentInfoMeta,
  SegmentInfoParagraph,
  UserProfile
} from './DomainModels';
import { DomainDecodeError, DomainDecodeFailureKind } from './ZhihuDomainDecoder';

function parseRoot(json: string, contentName: string): JsonObjectValue {
  try {
    const parsed = parseStrictJson(json);
    if (parsed instanceof JsonObjectValue) {
      return parsed;
    }
  } catch (error) {
    if (error instanceof StrictJsonError) {
      throw new DomainDecodeError(DomainDecodeFailureKind.INVALID_JSON, `${contentName}响应不是有效 JSON`);
    }
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, `${contentName}响应结构无效`);
}

function rejectUpstreamError(value: JsonValue | undefined, contentName: string): void {
  if (value === undefined || value instanceof JsonNullValue) {
    return;
  }
  if (!(value instanceof JsonObjectValue)) {
    throw invalid(`${contentName}.error 结构无效`);
  }
  const codeValue = value.get('code');
  let code = 'unknown';
  if (codeValue instanceof JsonNumberValue) {
    code = codeValue.value.toString();
  } else if (codeValue instanceof JsonStringValue) {
    code = codeValue.value;
  }
  throw new DomainDecodeError(DomainDecodeFailureKind.UPSTREAM_ERROR,
    `${contentName}接口返回错误（${code.slice(0, 24)}）`);
}

function checkedExpectedId(value: JsonValue | undefined, expectedId: string, field: string): string {
  if (value instanceof JsonStringValue) {
    if (value.value !== expectedId) {
      throw invalid(`${field} 与请求不一致`);
    }
    return expectedId;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    if (integerLiteral !== expectedId) {
      throw invalid(`${field} 与请求不一致`);
    }
    return expectedId;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredRelatedId(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && /^[1-9][0-9]{0,29}$/.test(value.value)) {
    return value.value;
  }
  const integerLiteral = jsonIntegerLiteral(value);
  if (integerLiteral !== undefined && /^[1-9][0-9]{0,29}$/.test(integerLiteral)) {
    return integerLiteral;
  }
  throw invalid(`${field} 缺少有效 ID`);
}

function requiredText(value: JsonValue | undefined, field: string): string {
  if (value instanceof JsonStringValue && value.value.trim().length > 0) {
    return value.value;
  }
  throw invalid(`${field} 不能为空`);
}

function textOrEmpty(value: JsonValue | undefined, field: string): string {
  if (value === undefined || value instanceof JsonNullValue) {
    return '';
  }
  if (!(value instanceof JsonStringValue)) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function nonNegativeInteger(value: JsonValue | undefined, field: string): number {
  if (value === undefined || value instanceof JsonNullValue) {
    return 0;
  }
  if (!(value instanceof JsonNumberValue) || !Number.isSafeInteger(value.value) || value.value < 0) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function optionalText(value: JsonValue | undefined): string | undefined {
  return value instanceof JsonStringValue && value.value.trim().length > 0 ? value.value : undefined;
}

function optionalBoolean(value: JsonValue | undefined, field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return false;
  }
  if (!(value instanceof JsonBooleanValue)) {
    throw invalid(`${field} 类型无效`);
  }
  return value.value;
}

function optionalObject(value: JsonValue | undefined, field: string): JsonObjectValue | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (!(value instanceof JsonObjectValue)) {
    throw invalid(`${field} 结构无效`);
  }
  return value;
}

/** 安全 alpha：0..1 内有限值，否则回退 1。 */
function safeAlpha(value: JsonValue | undefined): number {
  if (!(value instanceof JsonNumberValue) || !Number.isFinite(value.value)) {
    return 1;
  }
  return Math.min(1, Math.max(0, value.value));
}

/** 安全 token 组：仅接受已知前缀（GBK/GBL/GRD/GYL），未知返回 undefined 由 UI 回退主题色。 */
function safeTokenGroup(value: JsonValue | undefined): string | undefined {
  if (value instanceof JsonStringValue && /^(?:GBK|GBL|GRD|GYL)[0-9]{2}[A-Z]?$/.test(value.value)) {
    return value.value;
  }
  return undefined;
}

/**
 * 解码回答认可徽章流（对齐上游 Answer.endorsements 的 display 精简模型）。
 * 单个徽章无法展示时跳过，不因徽章数据异常拒绝详情加载。
 */
function endorsementsFromWire(value: JsonValue | undefined): Array<AnswerEndorsementDisplay> {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<AnswerEndorsementDisplay> = [];
  value.items.forEach((entry: JsonValue): void => {
    const endorsement = optionalObject(entry, 'endorsement');
    if (endorsement === undefined) {
      return;
    }
    const elements = endorsement.get('elements');
    if (!(elements instanceof JsonArrayValue)) {
      return;
    }
    const textParts: Array<string> = [];
    let textColorGroup: string | undefined = undefined;
    let textColorAlpha = 1;
    let leadingIconKey: string | undefined = undefined;
    let trailingIconKey: string | undefined = undefined;
    elements.items.forEach((elementValue: JsonValue): void => {
      const element = optionalObject(elementValue, 'endorsement.element');
      if (element === undefined) {
        return;
      }
      const type = element.get('type');
      const content = element.get('content');
      if (type instanceof JsonStringValue && type.value === 'TEXT' &&
        content instanceof JsonStringValue && content.value.trim().length > 0) {
        textParts.push(content.value.trim());
        textColorGroup = safeTokenGroup(element.get('fontColor') instanceof JsonObjectValue
          ? (element.get('fontColor') as JsonObjectValue).get('group')
          : undefined) ?? textColorGroup;
        textColorAlpha = element.get('fontColor') instanceof JsonObjectValue
          ? safeAlpha((element.get('fontColor') as JsonObjectValue).get('alpha'))
          : textColorAlpha;
      }
      // 图标元素（对齐上游：首个非箭头 IMAGE 为前导图标，末个含 arrow 的 IMAGE 为尾随图标）。
      if (type instanceof JsonStringValue && type.value === 'IMAGE') {
        const imageKey = optionalText(element.get('imageKey') ?? element.get('image_key'));
        if (imageKey !== undefined) {
          if (imageKey.indexOf('arrow') >= 0) {
            trailingIconKey = imageKey;
          } else if (leadingIconKey === undefined) {
            leadingIconKey = imageKey;
          }
        }
      }
    });
    const text = textParts.join(' ').trim();
    if (text.length === 0) {
      return;
    }
    const background = optionalObject(endorsement.get('backgroundColor'), 'endorsement.backgroundColor');
    result.push({
      text: text,
      backgroundColorGroup: background === undefined ? undefined : safeTokenGroup(background.get('group')),
      backgroundColorAlpha: background === undefined ? 1 : safeAlpha(background.get('alpha')),
      textColorGroup: textColorGroup,
      textColorAlpha: textColorAlpha,
      leadingIconKey: leadingIconKey,
      trailingIconKey: trailingIconKey
    });
  });
  return result;
}

/**
 * 从详情响应的 reaction.relation 或 relationship 中解析当前用户的投票关系。
 * 知乎接口两种形态都存在：字符串 vote（UP/DOWN/Neutral）与数字 voting（1/-1/0），
 * 无法解析时按中性处理，不因缺失该字段拒绝详情加载。
 */
function voteStateFromWire(wire: JsonObjectValue): ContentVoteState {
  const reaction = optionalObject(wire.get('reaction'), 'reaction');
  if (reaction !== undefined) {
    const relation = optionalObject(reaction.get('relation'), 'reaction.relation');
    if (relation !== undefined) {
      const vote = relation.get('vote');
      if (vote instanceof JsonStringValue) {
        return contentVoteStateFromString(vote.value);
      }
      const voting = relation.get('voting');
      if (voting instanceof JsonNumberValue) {
        return contentVoteStateFromNumber(voting.value);
      }
    }
  }
  const relationship = optionalObject(wire.get('relationship'), 'relationship');
  if (relationship !== undefined) {
    const vote = relationship.get('vote');
    if (vote instanceof JsonStringValue) {
      return contentVoteStateFromString(vote.value);
    }
  }
  return ContentVoteState.NEUTRAL;
}

function contentVoteStateFromString(value: string): ContentVoteState {
  if (value === 'UP') {
    return ContentVoteState.UP;
  }
  if (value === 'DOWN') {
    return ContentVoteState.DOWN;
  }
  return ContentVoteState.NEUTRAL;
}

function contentVoteStateFromNumber(value: number): ContentVoteState {
  if (value === 1) {
    return ContentVoteState.UP;
  }
  if (value === -1) {
    return ContentVoteState.DOWN;
  }
  return ContentVoteState.NEUTRAL;
}

/** badge_v2 子徽章解析中间结构：在展示模型上附加 wire 的 type 字段用于 primary 选取。 */
interface AuthorBadgeCandidate extends AuthorBadge {
  type: string;
}

/**
 * 解码作者认证徽章（对齐上游 BadgeV2.officialBadge 的 primary 选取逻辑）：
 * 优先 detail_badges，其次 merged_badges；跳过未通过审核的徽章；
 * 首选非 identity 且带图标的徽章，否则取首个带图标徽章；
 * 顶层 icon 非空时覆盖子徽章图标。无法解析时返回 undefined，不拒绝详情加载。
 */
function authorBadgeFromWire(value: JsonValue | undefined): AuthorBadge | undefined {
  if (value === undefined || !(value instanceof JsonObjectValue)) {
    return undefined;
  }
  const details = value.get('detail_badges') instanceof JsonArrayValue
    ? value.get('detail_badges') as JsonArrayValue
    : value.get('detailBadges') instanceof JsonArrayValue
      ? value.get('detailBadges') as JsonArrayValue
      : value.get('merged_badges') instanceof JsonArrayValue
        ? value.get('merged_badges') as JsonArrayValue
        : value.get('mergedBadges') instanceof JsonArrayValue
          ? value.get('mergedBadges') as JsonArrayValue
          : undefined;
  if (details === undefined) {
    return undefined;
  }
  const badges: AuthorBadgeCandidate[] = [];
  details.items.forEach((item: JsonValue): void => {
    if (!(item instanceof JsonObjectValue)) {
      return;
    }
    const status = item.get('badge_status') ?? item.get('badgeStatus');
    if (status instanceof JsonStringValue && status.value !== 'passed') {
      return;
    }
    const title = optionalText(item.get('title'));
    if (title === undefined) {
      return;
    }
    const description = optionalText(item.get('description')) ?? title;
    const iconUrl = optionalText(item.get('icon') ?? item.get('icon_url')) ?? '';
    const type = optionalText(item.get('type')) ?? '';
    badges.push({ title: title, description: description, iconUrl: iconUrl, type: type });
  });
  if (badges.length === 0) {
    return undefined;
  }
  // 对齐上游：首选非 identity 类型且带图标的徽章，否则取首个带图标徽章。
  const primary = badges.find((badge: AuthorBadgeCandidate): boolean =>
    badge.type !== 'identity' && badge.title !== '认证' && badge.iconUrl.length > 0) ??
    badges.find((badge: AuthorBadgeCandidate): boolean => badge.iconUrl.length > 0);
  if (primary === undefined) {
    return undefined;
  }
  const topLevelIcon = optionalText(value.get('icon'));
  return topLevelIcon !== undefined && topLevelIcon.length > 0
    ? { title: primary.title, description: primary.description, iconUrl: topLevelIcon }
    : primary;
}

function authorFromWire(wire: JsonObjectValue | undefined): UserProfile | undefined {
  if (wire === undefined) {
    return undefined;
  }
  const idValue = wire.get('id');
  let id: string;
  if (idValue instanceof JsonStringValue && idValue.value.trim().length > 0 && idValue.value.length <= 200) {
    id = idValue.value;
  } else {
    const integerLiteral = jsonIntegerLiteral(idValue);
    if (integerLiteral === undefined || integerLiteral.length > 30) {
      throw invalid('author.id 缺少有效 ID');
    }
    id = integerLiteral;
  }
  return {
    id: id,
    name: requiredText(wire.get('name'), 'author.name'),
    urlToken: optionalText(wire.get('url_token')),
    headline: textOrEmpty(wire.get('headline'), 'author.headline'),
    avatarUrl: optionalText(wire.get('avatar_url')),
    followerCount: nonNegativeInteger(wire.get('follower_count') ?? wire.get('followers_count'),
      'author.follower_count'),
    isFollowing: optionalBoolean(wire.get('is_following'), 'author.is_following'),
    isOrganization: optionalBoolean(wire.get('is_org'), 'author.is_org'),
    // 知乎 v4 响应字段为驼峰 badgeV2（上游 @SerialName("badgeV2")），兼容蛇形 badge_v2。
    badge: authorBadgeFromWire(wire.get('badgeV2') ?? wire.get('badge_v2'))
  };
}

/**
 * 解码正文他人划线（segment_infos）：按 pid 对齐各段，逐段解析 marks 高亮区间与元信息。
 * 字段名为蛇形（对齐真实接口与上游 segment_infos.md）：pid/text/marks、marks 的
 * start_index/end_index、seg_info/master_seg_info 的 seg_ids/is_like/like_count/
 * comment_count/my_comment_count/is_span。兼容 0/1 → 布尔（对应上游 BooleanCompatSerializer）。
 */
function segmentInfosFromWire(value: JsonValue | undefined): Array<SegmentInfoParagraph> {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<SegmentInfoParagraph> = [];
  value.items.forEach((paragraphValue: JsonValue): void => {
    // 真实接口的数组元素直接就是段落对象（{pid,text,marks}），没有包装层。
    if (!(paragraphValue instanceof JsonObjectValue)) {
      return;
    }
    const paragraph = paragraphValue;
    const pid = optionalText(paragraph.get('pid'));
    if (pid === undefined) {
      return;
    }
    const text = textOrEmpty(paragraph.get('text'), 'segment_info.text');
    result.push({ pid: pid, text: text, marks: segmentMarksFromWire(paragraph.get('marks')) });
  });
  return result;
}

function segmentMarksFromWire(value: JsonValue | undefined): Array<SegmentInfoMark> {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    return [];
  }
  const result: Array<SegmentInfoMark> = [];
  value.items.forEach((markValue: JsonValue): void => {
    // 真实接口的 marks 元素直接就是 {start_index,end_index,seg_info,...}，没有包装层。
    if (!(markValue instanceof JsonObjectValue)) {
      return;
    }
    const mark = markValue;
    const start = nonNegativeInteger(mark.get('start_index'), 'segment_mark.start_index');
    const end = nonNegativeInteger(mark.get('end_index'), 'segment_mark.end_index');
    if (end <= start) {
      return;
    }
    result.push({
      startIndex: start,
      endIndex: end,
      segInfo: segmentMetaFromWire(mark.get('seg_info')),
      masterSegInfo: segmentMetaFromWire(mark.get('master_seg_info'))
    });
  });
  return result;
}

function segmentMetaFromWire(value: JsonValue | undefined): SegmentInfoMeta | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  if (!(value instanceof JsonObjectValue)) {
    return undefined;
  }
  const segIdsValue = value.get('seg_ids');
  const segIds: Array<string> = [];
  if (segIdsValue instanceof JsonArrayValue) {
    segIdsValue.items.forEach((idValue: JsonValue): void => {
      if (idValue instanceof JsonStringValue) {
        segIds.push(idValue.value);
      }
    });
  }
  return {
    segIds: segIds,
    isLike: compatBoolean(value.get('is_like'), 'segment_meta.is_like'),
    likeCount: nonNegativeInteger(value.get('like_count'), 'segment_meta.like_count'),
    commentCount: nonNegativeInteger(value.get('comment_count'), 'segment_meta.comment_count'),
    myCommentCount: nonNegativeInteger(value.get('my_comment_count'), 'segment_meta.my_comment_count'),
    isSpan: compatBoolean(value.get('is_span'), 'segment_meta.is_span')
  };
}

/** 兼容 0/1/字符串/布尔 → 布尔（对应上游 BooleanCompatSerializer）。 */
function compatBoolean(value: JsonValue | undefined, _field: string): boolean {
  if (value === undefined || value instanceof JsonNullValue) {
    return false;
  }
  if (value instanceof JsonBooleanValue) {
    return value.value;
  }
  if (value instanceof JsonNumberValue) {
    return value.value !== 0;
  }
  if (value instanceof JsonStringValue) {
    return value.value === 'true' || value.value === '1';
  }
  return false;
}

export function decodeQuestionDetail(json: string, expectedId: string): Question {
  const wire = parseRoot(json, '问题');
  rejectUpstreamError(wire.get('error'), '问题');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'question.id');
  const relationship = optionalObject(wire.get('relationship'), 'question.relationship');
  return {
    id: id,
    title: requiredText(wire.get('title') ?? wire.get('name'), 'question.title'),
    detailHtml: textOrEmpty(wire.get('detail'), 'question.detail'),
    url: `https://www.zhihu.com/question/${id}`,
    answerCount: nonNegativeInteger(wire.get('answer_count'), 'question.answer_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'question.comment_count'),
    followerCount: nonNegativeInteger(wire.get('follower_count'), 'question.follower_count'),
    visitCount: questionVisitCount(wire.get('visit_count')),
    createdAt: nonNegativeInteger(wire.get('created'), 'question.created'),
    updatedAt: nonNegativeInteger(wire.get('updated_time'), 'question.updated_time'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author')),
    isFollowing: relationship === undefined
      ? undefined
      : optionalBoolean(relationship.get('is_following'), 'question.relationship.is_following'),
    topics: questionTopicsFromWire(wire.get('topics'))
  };
}

function questionVisitCount(value: JsonValue | undefined): number | undefined {
  if (value === undefined || value instanceof JsonNullValue) {
    return undefined;
  }
  return nonNegativeInteger(value, 'question.visit_count');
}

function questionTopicsFromWire(value: JsonValue | undefined): QuestionTopicSummary[] {
  if (value === undefined || value instanceof JsonNullValue) {
    return [];
  }
  if (!(value instanceof JsonArrayValue)) {
    throw invalid('question.topics 结构无效');
  }
  const topics: QuestionTopicSummary[] = [];
  value.items.forEach((item: JsonValue): void => {
    const object = item instanceof JsonObjectValue ? item : undefined;
    if (object === undefined) {
      return;
    }
    const id = jsonString(object.get('id')) ?? jsonIntegerLiteral(object.get('id'));
    const name = jsonString(object.get('name')) ?? jsonString(object.get('title'));
    if (id === undefined || id.trim().length === 0 || name === undefined || name.trim().length === 0) {
      return;
    }
    topics.push({ id: id, name: name });
  });
  return topics;
}

export function decodeAnswerDetail(json: string, expectedId: string): Answer {
  const wire = parseRoot(json, '回答');
  rejectUpstreamError(wire.get('error'), '回答');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'answer.id');
  const question = optionalObject(wire.get('question'), 'answer.question');
  const questionId = requiredRelatedId(question?.get('id'), 'answer.question.id');
  return {
    id: id,
    questionId: questionId,
    questionTitle: optionalText(question?.get('title') ?? question?.get('name')),
    contentHtml: textOrEmpty(wire.get('content'), 'answer.content'),
    excerpt: textOrEmpty(wire.get('excerpt'), 'answer.excerpt'),
    url: `https://www.zhihu.com/question/${questionId}/answer/${id}`,
    voteupCount: nonNegativeInteger(wire.get('voteup_count'), 'answer.voteup_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'answer.comment_count'),
    createdAt: nonNegativeInteger(wire.get('created_time'), 'answer.created_time'),
    updatedAt: nonNegativeInteger(wire.get('updated_time'), 'answer.updated_time'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author')),
    voteState: voteStateFromWire(wire),
    thanksCount: nonNegativeInteger(wire.get('thanks_count'), 'answer.thanks_count'),
    isThanked: optionalBoolean(wire.get('is_thanked'), 'answer.is_thanked'),
    endorsements: endorsementsFromWire(wire.get('endorsements')),
    ipInfo: optionalText(wire.get('ip_info')),
    segmentInfos: segmentInfosFromWire(wire.get('segment_infos')),
    allowSegmentInteraction: compatBoolean(wire.get('allow_segment_interaction'), 'answer.allow_segment_interaction')
  };
}

export function decodeArticleDetail(json: string, expectedId: string): Article {
  const wire = parseRoot(json, '文章');
  rejectUpstreamError(wire.get('error'), '文章');
  const id = checkedExpectedId(wire.get('id'), expectedId, 'article.id');
  return {
    id: id,
    title: requiredText(wire.get('title'), 'article.title'),
    contentHtml: textOrEmpty(wire.get('content'), 'article.content'),
    excerpt: textOrEmpty(wire.get('excerpt'), 'article.excerpt'),
    url: `https://zhuanlan.zhihu.com/p/${id}`,
    voteupCount: nonNegativeInteger(wire.get('voteup_count'), 'article.voteup_count'),
    commentCount: nonNegativeInteger(wire.get('comment_count'), 'article.comment_count'),
    createdAt: nonNegativeInteger(wire.get('created'), 'article.created'),
    updatedAt: nonNegativeInteger(wire.get('updated'), 'article.updated'),
    author: authorFromWire(optionalObject(wire.get('author'), 'author')),
    voteState: voteStateFromWire(wire),
    thanksCount: nonNegativeInteger(wire.get('thanks_count'), 'article.thanks_count'),
    isThanked: optionalBoolean(wire.get('is_thanked'), 'article.is_thanked'),
    endorsements: endorsementsFromWire(wire.get('endorsements')),
    topics: questionTopicsFromWire(wire.get('topics')),
    ipInfo: optionalText(wire.get('ip_info')),
    segmentInfos: segmentInfosFromWire(wire.get('segment_infos')),
    allowSegmentInteraction: compatBoolean(wire.get('allow_segment_interaction'), 'article.allow_segment_interaction')
  };
}

function invalid(message: string): DomainDecodeError {
  return new DomainDecodeError(DomainDecodeFailureKind.MISSING_FIELD, message);
}
