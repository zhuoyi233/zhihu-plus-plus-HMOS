/**
 * 设置搜索索引：只覆盖“设置”及其管理子项，不再返回发布想法、草稿、收藏夹等个人功能。
 * 可见性与页面一致，未开启开发者模式时搜索“Cookie”等关键词不会暴露隐藏入口。
 *
 * 在分类入口之上扩展了可独立定位的设置细项：具体项携带 pane/锚点/提醒卡片元数据，
 * 查询命中具体标题时按固定优先级排在分类结果之前。
 */
import { SettingsPaneId, SettingsTargetKind } from './SettingsSearchTarget';

// 中立目标类型重新导出：既有使用方继续从本模块取类型。
export { SettingsPaneId, SettingsTargetKind };

export enum SettingsEntryVisibility {
  ALWAYS = 'always',
  AUTHENTICATED_ONLY = 'authenticated_only',
  ANONYMOUS_ONLY = 'anonymous_only',
  DEVELOPER_ONLY = 'developer_only'
}

export enum SettingsEntryId {
  LOGIN = 'login',
  IDENTITY = 'identity',
  APPEARANCE = 'appearance',
  THEME_COLOR = 'theme_color',
  READING = 'reading',
  FILTER = 'filter',
  BLOCKING_RULES = 'blocking_rules',
  BLOCKED_HISTORY = 'blocked_history',
  NOTIFICATION = 'notification',
  SYSTEM_UPDATE = 'system_update',
  ABOUT = 'about',
  ABOUT_VERSION = 'about_version',
  ABOUT_GITHUB = 'about_github',
  ABOUT_LICENSE = 'about_license',
  ABOUT_OPEN_SOURCE = 'about_open_source',
  DEVELOPER = 'developer'
}

export interface SettingsSearchEntry {
  readonly id: string;
  readonly title: string;
  readonly path: string;
  readonly keywords: string;
  readonly visibility: SettingsEntryVisibility;
  readonly targetKind: SettingsTargetKind;
  readonly paneId: SettingsPaneId;
  /** 精确滚动锚点（设置整行）；空串表示不滚动（分类落点）。 */
  readonly anchorId: string;
  /** 定位后闪烁的分组卡片；空串表示不闪烁。 */
  readonly highlightGroupId: string;
  /** 条件隐藏时的前置开关落点；空串表示无回退（此时应隐藏结果）。 */
  readonly fallbackAnchorId: string;
}

export interface SettingsSearchOptions {
  readonly authenticated: boolean;
  readonly developerModeEnabled: boolean;
}

const SETTINGS_SEARCH_ENTRIES: Array<SettingsSearchEntry> = [
  {
    id: SettingsEntryId.LOGIN,
    title: '登录知乎',
    path: '账户',
    keywords: '账号 登录 手机号 扫码 网页',
    visibility: SettingsEntryVisibility.ANONYMOUS_ONLY,
    targetKind: SettingsTargetKind.EXTERNAL,
    paneId: SettingsPaneId.NONE,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.IDENTITY,
    title: '身份管理',
    path: '账户',
    keywords: '马甲 切换身份 账号',
    visibility: SettingsEntryVisibility.AUTHENTICATED_ONLY,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.IDENTITY,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.APPEARANCE,
    title: '外观与阅读体验',
    path: '使用偏好',
    keywords: '主题 沉浸 光感 材质 字号 行高 段间距 列表样式 卡片 分割线 信息流 列数',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_font_size',
    title: '字号',
    path: '外观与阅读体验 · 阅读',
    keywords: '字体大小 文字大小 font size',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_anchor_font_size',
    highlightGroupId: 'appearance_group_reading',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_line_height',
    title: '行高',
    path: '外观与阅读体验 · 阅读',
    keywords: '行间距 行距 line height',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_anchor_line_height',
    highlightGroupId: 'appearance_group_reading',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_block_spacing',
    title: '段间距',
    path: '外观与阅读体验 · 阅读',
    keywords: '段落间距 段落 block spacing',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_anchor_block_spacing',
    highlightGroupId: 'appearance_group_reading',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.THEME_COLOR,
    title: '主题颜色',
    path: '外观与阅读体验',
    keywords: '主题色 配色 颜色 强调色 accent',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.THEME_COLOR,
    anchorId: 'theme_color_anchor_presets',
    highlightGroupId: 'theme_color_group_presets',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.READING,
    title: '朗读与播放',
    path: '使用偏好',
    keywords: '语音 语速 音调 播放',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.READING,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'reading_speed',
    title: '语速',
    path: '朗读与播放 · 语音',
    keywords: '朗读速度 速度 speech speed',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.READING,
    anchorId: 'reading_anchor_speed',
    highlightGroupId: 'reading_group_voice',
    fallbackAnchorId: ''
  },
  {
    id: 'reading_pitch',
    title: '音调',
    path: '朗读与播放 · 语音',
    keywords: '音高 pitch',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.READING,
    anchorId: 'reading_anchor_pitch',
    highlightGroupId: 'reading_group_voice',
    fallbackAnchorId: ''
  },
  {
    id: 'reading_voice',
    title: '音色',
    path: '朗读与播放 · 语音',
    keywords: '语音 声音 voice 朗读者',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.READING,
    anchorId: 'reading_anchor_voice',
    highlightGroupId: 'reading_group_voice',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.FILTER,
    title: '推荐系统与内容过滤',
    path: '使用偏好',
    keywords: '推荐 算法 质量 智能过滤 广告 盐选',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.FILTER,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_zhihu_ad',
    title: '屏蔽知乎广告',
    path: '推荐系统与内容过滤 · 推广与付费内容',
    keywords: '广告 推广 xg 过滤',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_anchor_zhihu_ad',
    highlightGroupId: 'filter_group_promotion',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_paid',
    title: '屏蔽盐选付费内容',
    path: '推荐系统与内容过滤 · 推广与付费内容',
    keywords: '盐选 付费 会员 广告',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_anchor_paid',
    highlightGroupId: 'filter_group_promotion',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_topic_threshold',
    title: '主题屏蔽阈值',
    path: '推荐系统与内容过滤 · 智能与规则过滤',
    keywords: '主题 屏蔽 阈值 话题',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_anchor_topic_threshold',
    highlightGroupId: 'filter_group_rules',
    // 主题屏蔽关闭时阈值行不渲染：定位前置开关并提示需先开启。
    fallbackAnchorId: 'filter_anchor_topic_enabled'
  },
  {
    id: SettingsEntryId.BLOCKING_RULES,
    title: '内容屏蔽',
    path: '推荐系统与内容过滤',
    keywords: '屏蔽 作者 关键词 黑名单 话题 正则 大小写 阈值 导入 导出 备份 清空',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.BLOCKING_RULES,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.BLOCKED_HISTORY,
    title: '屏蔽记录',
    path: '推荐系统与内容过滤',
    keywords: '屏蔽 隐藏 记录 清空 删除记录',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.BLOCKED_HISTORY,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.NOTIFICATION,
    title: '通知设置',
    path: '使用偏好',
    keywords: '提醒 推送 通知',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.SYSTEM_UPDATE,
    title: '系统与更新',
    path: '应用',
    keywords: '版本 检查更新 下载 反馈 日志',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.SYSTEM_UPDATE,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.ABOUT,
    title: '关于应用',
    path: '应用',
    keywords: '版本 GitHub 协议 许可 免责声明 开源',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.ABOUT,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.ABOUT_VERSION,
    title: '应用与版本',
    path: '关于应用',
    keywords: '版本 版本号 应用 开发',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.ABOUT,
    anchorId: 'open_about_version',
    highlightGroupId: 'about_group_project',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.ABOUT_GITHUB,
    title: 'GitHub',
    path: '关于应用',
    keywords: '项目 主页 源码 仓库 github',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.ABOUT,
    anchorId: 'open_project_home',
    highlightGroupId: 'about_group_project',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.ABOUT_LICENSE,
    title: '项目协议',
    path: '关于应用',
    keywords: 'AGPL 协议 许可',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.ABOUT,
    anchorId: 'open_project_license',
    highlightGroupId: 'about_group_project',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.ABOUT_OPEN_SOURCE,
    title: '开源许可',
    path: '关于应用',
    keywords: '开源 许可 HAR 模块',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.ABOUT,
    anchorId: 'open_open_source_licenses',
    highlightGroupId: 'about_group_project',
    fallbackAnchorId: ''
  },
  {
    id: SettingsEntryId.DEVELOPER,
    title: '开发者选项',
    path: '开发者选项',
    keywords: 'Cookie 网络 调试 技术实验室 会话 探针 存储 诊断 二维码',
    visibility: SettingsEntryVisibility.DEVELOPER_ONLY,
    targetKind: SettingsTargetKind.CATEGORY,
    paneId: SettingsPaneId.DEVELOPER,
    anchorId: '',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'developer_cookie',
    title: '手动 Cookie',
    path: '开发者选项 · 会话',
    keywords: 'cookie 会话 凭证 登录态',
    visibility: SettingsEntryVisibility.DEVELOPER_ONLY,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.DEVELOPER,
    anchorId: 'developer_cookie_input',
    highlightGroupId: 'developer_group_cookie',
    fallbackAnchorId: ''
  }
];

function isEntryVisible(entry: SettingsSearchEntry, options: SettingsSearchOptions): boolean {
  switch (entry.visibility) {
    case SettingsEntryVisibility.AUTHENTICATED_ONLY:
      return options.authenticated;
    case SettingsEntryVisibility.ANONYMOUS_ONLY:
      return !options.authenticated;
    case SettingsEntryVisibility.DEVELOPER_ONLY:
      return options.developerModeEnabled;
    default:
      return true;
  }
}

/** 当前登录态与开发者模式下可见的设置搜索项。 */
export function visibleSettingsSearchEntries(options: SettingsSearchOptions): Array<SettingsSearchEntry> {
  return SETTINGS_SEARCH_ENTRIES.filter((entry: SettingsSearchEntry): boolean => isEntryVisible(entry, options));
}

/** 规范化查询：去首尾空白、英文小写化、连续空白合并。 */
export function normalizeSearchQuery(query: string): string {
  return query.trim().toLowerCase().replace(/\s+/g, ' ');
}

function haystackOf(entry: SettingsSearchEntry): string {
  return `${entry.title} ${entry.path} ${entry.keywords}`.toLowerCase();
}

function entryMatchesAllTerms(entry: SettingsSearchEntry, terms: Array<string>): boolean {
  const haystack: string = haystackOf(entry);
  return terms.every((term: string): boolean => haystack.includes(term));
}

/** 匹配优先级：0 标题完全匹配 → 1 标题包含 → 2 别名/关键词 → 3 仅路径命中。 */
function entryPriority(entry: SettingsSearchEntry, normalizedQuery: string, terms: Array<string>): number {
  const title: string = entry.title.toLowerCase();
  if (title === normalizedQuery) {
    return 0;
  }
  if (title.includes(normalizedQuery)) {
    return 1;
  }
  const keywordsHaystack: string = `${entry.title} ${entry.keywords}`.toLowerCase();
  if (terms.every((term: string): boolean => keywordsHaystack.includes(term))) {
    return 2;
  }
  return 3;
}

/**
 * 多词包含匹配：查询拆词后要求每个词都能在标题/路径/关键词中命中；
 * 结果按固定优先级排序（同级保持索引顺序），并按 id 去重。
 */
export function matchSettingsSearchEntries(entries: Array<SettingsSearchEntry>,
  query: string): Array<SettingsSearchEntry> {
  const normalized: string = normalizeSearchQuery(query);
  if (normalized.length === 0) {
    return [];
  }
  const terms: Array<string> = normalized.split(' ').filter((term: string): boolean => term.length > 0);
  if (terms.length === 0) {
    return [];
  }
  const matched: Array<SettingsSearchEntry> = entries
    .filter((entry: SettingsSearchEntry): boolean => entryMatchesAllTerms(entry, terms));
  const withPriority: Array<SearchCandidate> = matched.map((entry: SettingsSearchEntry, index: number) => {
    return { entry: entry, index: index, priority: entryPriority(entry, normalized, terms) } as SearchCandidate;
  });
  withPriority.sort((left: SearchCandidate, right: SearchCandidate): number => {
    if (left.priority !== right.priority) {
      return left.priority - right.priority;
    }
    return left.index - right.index;
  });
  const seen: Set<string> = new Set<string>();
  const results: Array<SettingsSearchEntry> = [];
  withPriority.forEach((candidate: SearchCandidate): void => {
    if (seen.has(candidate.entry.id)) {
      return;
    }
    seen.add(candidate.entry.id);
    results.push(candidate.entry);
  });
  return results;
}

interface SearchCandidate {
  readonly entry: SettingsSearchEntry;
  readonly index: number;
  readonly priority: number;
}
