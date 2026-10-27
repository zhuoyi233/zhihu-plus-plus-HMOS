/**
 * 设置搜索索引：只覆盖“设置”及其管理子项，不再返回发布想法、草稿、收藏夹等个人功能。
 * 可见性与页面一致，未开启开发者模式时搜索“Cookie”等关键词不会暴露隐藏入口。
 */
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
  readonly id: SettingsEntryId;
  readonly title: string;
  readonly path: string;
  readonly keywords: string;
  readonly visibility: SettingsEntryVisibility;
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
    visibility: SettingsEntryVisibility.ANONYMOUS_ONLY
  },
  {
    id: SettingsEntryId.IDENTITY,
    title: '身份管理',
    path: '账户',
    keywords: '马甲 切换身份 账号',
    visibility: SettingsEntryVisibility.AUTHENTICATED_ONLY
  },
  {
    id: SettingsEntryId.APPEARANCE,
    title: '外观与阅读体验',
    path: '使用偏好',
    keywords: '主题 沉浸 光感 材质 字号 行高 段间距 列表样式 卡片 分割线 信息流 列数',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.THEME_COLOR,
    title: '主题颜色',
    path: '外观与阅读体验',
    keywords: '主题色 配色 颜色 强调色',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.READING,
    title: '朗读与播放',
    path: '使用偏好',
    keywords: '语音 语速 音调 播放',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.FILTER,
    title: '推荐系统与内容过滤',
    path: '使用偏好',
    keywords: '推荐 算法 质量 智能过滤 广告 盐选',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.BLOCKING_RULES,
    title: '内容屏蔽',
    path: '推荐系统与内容过滤',
    keywords: '屏蔽 作者 关键词 黑名单 话题 正则 大小写 阈值 导入 导出 备份 清空',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.BLOCKED_HISTORY,
    title: '屏蔽记录',
    path: '推荐系统与内容过滤',
    keywords: '屏蔽 隐藏 记录 清空 删除记录',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.NOTIFICATION,
    title: '通知设置',
    path: '使用偏好',
    keywords: '提醒 推送 通知',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.SYSTEM_UPDATE,
    title: '系统与更新',
    path: '应用',
    keywords: '版本 检查更新 下载 反馈 日志',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.ABOUT,
    title: '关于应用',
    path: '应用',
    keywords: '版本 GitHub 协议 许可 免责声明 开源',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.ABOUT_VERSION,
    title: '应用与版本',
    path: '关于应用',
    keywords: '版本 版本号 应用 开发',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.ABOUT_GITHUB,
    title: 'GitHub',
    path: '关于应用',
    keywords: '项目 主页 源码 仓库',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.ABOUT_LICENSE,
    title: '项目协议',
    path: '关于应用',
    keywords: 'AGPL 协议 许可',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.ABOUT_OPEN_SOURCE,
    title: '开源许可',
    path: '关于应用',
    keywords: '开源 许可 HAR 模块',
    visibility: SettingsEntryVisibility.ALWAYS
  },
  {
    id: SettingsEntryId.DEVELOPER,
    title: '开发者选项',
    path: '开发者选项',
    keywords: 'Cookie 网络 调试 技术实验室 会话 探针 存储 诊断 二维码',
    visibility: SettingsEntryVisibility.DEVELOPER_ONLY
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

/** 空查询返回空数组；有查询时按标题、路径与关键词做不区分大小写的包含匹配。 */
export function matchSettingsSearchEntries(entries: Array<SettingsSearchEntry>, query: string): Array<SettingsSearchEntry> {
  const normalized: string = query.trim().toLowerCase();
  if (normalized.length === 0) {
    return [];
  }
  return entries.filter((entry: SettingsSearchEntry): boolean => {
    const haystack: string = `${entry.title} ${entry.path} ${entry.keywords}`.toLowerCase();
    return haystack.includes(normalized);
  });
}
