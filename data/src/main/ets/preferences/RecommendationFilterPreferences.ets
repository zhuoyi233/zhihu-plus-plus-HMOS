/** 与上游 RecommendationMode 的 key、显示名和说明保持一致。 */
export enum RecommendationMode {
  WEB = 'server',
  ANDROID = 'android',
  LOCAL = 'local',
  MIXED = 'mixed'
}

export enum QualityFilterMode {
  OFF = 'OFF',
  RULES = 'RULES',
  HIDE = 'HIDE'
}

export interface RecommendationFilterPreferences {
  recommendationMode: RecommendationMode;
  loginForRecommendation: boolean;
  autoRefreshHomeOnStartup: boolean;
  qualityFilterMode: QualityFilterMode;
  answerVoteupThreshold: number;
  articleVoteupThreshold: number;
  articleFollowersThreshold: number;
  videoVoteThreshold: number;
  videoFollowersThreshold: number;
  questionAnswerThreshold: number;
  questionFollowersThreshold: number;
  enableContentFilter: boolean;
  filterFollowedUserContent: boolean;
  blockZhihuAdPlatform: boolean;
  blockZhihuSchool: boolean;
  blockWeChatOfficialAccount: boolean;
  blockPaidContent: boolean;
  reverseBlock: boolean;
}

export interface RecommendationFilterPreferencesGateway {
  loadRecommendationFilterPreferences(): Promise<RecommendationFilterPreferences>;
  saveRecommendationFilterPreferences(value: RecommendationFilterPreferences): Promise<void>;
}

/** 首页启动快照按推荐来源隔离，避免切换算法后复用不匹配的分页数据。 */
export interface HomeFeedStartupCacheGateway {
  loadHomeFeedStartupResponse(mode: RecommendationMode): Promise<string | undefined>;
  saveHomeFeedStartupResponse(mode: RecommendationMode, response: string): Promise<void>;
}

export function defaultRecommendationFilterPreferences(): RecommendationFilterPreferences {
  return {
    recommendationMode: RecommendationMode.MIXED,
    loginForRecommendation: true,
    autoRefreshHomeOnStartup: true,
    qualityFilterMode: QualityFilterMode.RULES,
    answerVoteupThreshold: 10,
    articleVoteupThreshold: 20,
    articleFollowersThreshold: 50,
    videoVoteThreshold: 20,
    videoFollowersThreshold: 50,
    questionAnswerThreshold: 0,
    questionFollowersThreshold: 50,
    enableContentFilter: true,
    filterFollowedUserContent: false,
    blockZhihuAdPlatform: true,
    blockZhihuSchool: true,
    blockWeChatOfficialAccount: true,
    blockPaidContent: true,
    reverseBlock: false
  };
}

export function normalizeRecommendationFilterPreferences(
  value: RecommendationFilterPreferences): RecommendationFilterPreferences {
  return {
    recommendationMode: decodeRecommendationMode(value.recommendationMode),
    loginForRecommendation: value.loginForRecommendation,
    autoRefreshHomeOnStartup: value.autoRefreshHomeOnStartup,
    qualityFilterMode: decodeQualityFilterMode(value.qualityFilterMode),
    answerVoteupThreshold: normalizeThreshold(value.answerVoteupThreshold, 10),
    articleVoteupThreshold: normalizeThreshold(value.articleVoteupThreshold, 20),
    articleFollowersThreshold: normalizeThreshold(value.articleFollowersThreshold, 50),
    videoVoteThreshold: normalizeThreshold(value.videoVoteThreshold, 20),
    videoFollowersThreshold: normalizeThreshold(value.videoFollowersThreshold, 50),
    questionAnswerThreshold: normalizeThreshold(value.questionAnswerThreshold, 0),
    questionFollowersThreshold: normalizeThreshold(value.questionFollowersThreshold, 50),
    enableContentFilter: value.enableContentFilter,
    filterFollowedUserContent: value.filterFollowedUserContent,
    blockZhihuAdPlatform: value.blockZhihuAdPlatform,
    blockZhihuSchool: value.blockZhihuSchool,
    blockWeChatOfficialAccount: value.blockWeChatOfficialAccount,
    blockPaidContent: value.blockPaidContent,
    reverseBlock: value.reverseBlock
  };
}

export function decodeRecommendationMode(value: string): RecommendationMode {
  if (value === RecommendationMode.WEB) return RecommendationMode.WEB;
  if (value === RecommendationMode.ANDROID) return RecommendationMode.ANDROID;
  if (value === RecommendationMode.LOCAL) return RecommendationMode.LOCAL;
  return RecommendationMode.MIXED;
}

export function decodeQualityFilterMode(value: string): QualityFilterMode {
  if (value === QualityFilterMode.OFF) return QualityFilterMode.OFF;
  if (value === QualityFilterMode.HIDE) return QualityFilterMode.HIDE;
  return QualityFilterMode.RULES;
}

export function recommendationModeLabel(value: RecommendationMode): string {
  if (value === RecommendationMode.WEB) return 'Web 端推荐';
  if (value === RecommendationMode.ANDROID) return '安卓端推荐';
  if (value === RecommendationMode.LOCAL) return '本地排序（实验性）';
  return '混合推荐';
}

export function recommendationModeDescription(value: RecommendationMode): string {
  if (value === RecommendationMode.WEB) return '使用知乎网页端的推荐算法';
  if (value === RecommendationMode.ANDROID) return '使用知乎安卓端的推荐算法';
  if (value === RecommendationMode.LOCAL) return '对已有缓存或 Web 候选做本地热度排序，暂不学习用户行为';
  return '融合安卓和网页端推荐算法，并过滤盐选内容';
}

export function qualityFilterModeLabel(value: QualityFilterMode): string {
  if (value === QualityFilterMode.OFF) return '不屏蔽';
  if (value === QualityFilterMode.HIDE) return '隐藏';
  return '屏蔽规则';
}

function normalizeThreshold(value: number, fallback: number): number {
  return Number.isSafeInteger(value) && value >= 0 && value <= 100000000 ? value : fallback;
}
