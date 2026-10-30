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
    id: 'filter_recommendation_mode',
    title: '推荐算法',
    path: '推荐系统与内容过滤 · 推荐来源',
    keywords: '推荐算法 推荐 来源 Web 安卓 本地排序 混合',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_recommendation_mode',
    highlightGroupId: 'filter_group_source',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_login_recommendation',
    title: '推荐内容时登录',
    path: '推荐系统与内容过滤 · 推荐来源',
    keywords: '登录 推荐凭证 携带',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_login_recommendation',
    highlightGroupId: 'filter_group_source',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_auto_refresh_startup',
    title: '启动时自动刷新首页',
    path: '推荐系统与内容过滤 · 推荐来源',
    keywords: '自动刷新 启动 首页 缓存',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_auto_refresh_startup',
    highlightGroupId: 'filter_group_source',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_quality_mode',
    title: '质量屏蔽',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '质量屏蔽 低质量 赞数 关注数',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_quality_mode',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_answer_vote_threshold',
    title: '回答最低赞数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '回答 赞数 阈值 过滤',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_answer_vote_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_article_vote_threshold',
    title: '文章最低赞数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '文章 赞数 阈值 粉丝',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_article_vote_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_advanced_thresholds',
    title: '其他质量过滤阈值',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '其他 阈值 展开 粉丝 视频 问题',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_advanced_thresholds',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_article_follower_threshold',
    title: '文章最低粉丝数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '文章 粉丝数 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_article_follower_threshold',
    highlightGroupId: 'filter_group_quality',
    // 依赖“其他质量过滤阈值”展开。
    fallbackAnchorId: 'filter_advanced_thresholds'
  },
  {
    id: 'filter_video_vote_threshold',
    title: '视频最低赞数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '视频 赞数 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_video_vote_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: 'filter_advanced_thresholds'
  },
  {
    id: 'filter_video_follower_threshold',
    title: '视频最低粉丝数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '视频 粉丝数 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_video_follower_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: 'filter_advanced_thresholds'
  },
  {
    id: 'filter_question_answer_threshold',
    title: '问题最低回答数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '问题 回答数 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_question_answer_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: 'filter_advanced_thresholds'
  },
  {
    id: 'filter_question_follower_threshold',
    title: '问题最低关注数',
    path: '推荐系统与内容过滤 · 内容质量',
    keywords: '问题 关注数 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_question_follower_threshold',
    highlightGroupId: 'filter_group_quality',
    fallbackAnchorId: 'filter_advanced_thresholds'
  },
  {
    id: 'filter_smart_enabled',
    title: '启用智能内容过滤',
    path: '推荐系统与内容过滤 · 智能与规则过滤',
    keywords: '智能 过滤 已读 总开关',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_smart_enabled',
    highlightGroupId: 'filter_group_rules',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_keyword_enabled',
    title: '启用关键词屏蔽',
    path: '推荐系统与内容过滤 · 智能与规则过滤',
    keywords: '关键词 屏蔽 开关 黑名单',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_keyword_enabled',
    highlightGroupId: 'filter_group_rules',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_user_enabled',
    title: '启用用户屏蔽',
    path: '推荐系统与内容过滤 · 智能与规则过滤',
    keywords: '用户 屏蔽 开关 作者',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_user_enabled',
    highlightGroupId: 'filter_group_rules',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_topic_enabled',
    title: '启用主题屏蔽',
    path: '推荐系统与内容过滤 · 智能与规则过滤',
    keywords: '主题 屏蔽 开关 话题',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_topic_enabled',
    highlightGroupId: 'filter_group_rules',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_zhihu_school',
    title: '屏蔽知乎学堂内容',
    path: '推荐系统与内容过滤 · 推广与付费内容',
    keywords: '学堂 推广 教育课程 屏蔽',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_zhihu_school',
    highlightGroupId: 'filter_group_promotion',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_wechat',
    title: '屏蔽微信公众号文章',
    path: '推荐系统与内容过滤 · 推广与付费内容',
    keywords: '微信 公众号 外链 文章 屏蔽',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_wechat',
    highlightGroupId: 'filter_group_promotion',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_reverse',
    title: '反向屏蔽',
    path: '推荐系统与内容过滤 · 推广与付费内容',
    keywords: '反向屏蔽 只看广告 吃屎模式 反转',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_reverse',
    highlightGroupId: 'filter_group_promotion',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_open_blocklist',
    title: '内容屏蔽规则管理',
    path: '推荐系统与内容过滤 · 管理与统计',
    keywords: '内容屏蔽 规则 管理 添加',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_open_blocklist',
    highlightGroupId: 'filter_group_manage',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_open_history',
    title: '屏蔽记录入口',
    path: '推荐系统与内容过滤 · 管理与统计',
    keywords: '屏蔽记录 历史 查看入口',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_open_history',
    highlightGroupId: 'filter_group_manage',
    fallbackAnchorId: ''
  },
  {
    id: 'filter_statistics',
    title: '过滤统计',
    path: '推荐系统与内容过滤 · 管理与统计',
    keywords: '统计 过滤率 清理 重置',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.FILTER,
    anchorId: 'filter_statistics',
    highlightGroupId: 'filter_group_manage',
    // 依赖“启用智能内容过滤”开启。
    fallbackAnchorId: 'filter_smart_enabled'
  },
  {
    id: 'notifications_auto_read',
    title: '打开通知自动已读',
    path: '通知设置 · 阅读行为',
    keywords: '通知 已读 自动 标记',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_auto_read',
    highlightGroupId: 'notifications_group_behavior',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_unread_badge',
    title: '显示未读红点',
    path: '通知设置 · 阅读行为',
    keywords: '未读 红点 角标 数量',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_unread_badge',
    highlightGroupId: 'notifications_group_behavior',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_system_open',
    title: '管理系统通知',
    path: '通知设置 · 系统通知',
    keywords: '系统通知 授权 提醒 开关',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_system_open',
    highlightGroupId: 'notifications_group_system',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_display_like_answer',
    title: '应用内显示赞同我的回答',
    path: '通知设置 · 应用内显示',
    keywords: '赞同 回答 显示 通知',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_display_like_answer',
    highlightGroupId: 'notifications_group_display',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_display_like_comment',
    title: '应用内显示赞同我的评论',
    path: '通知设置 · 应用内显示',
    keywords: '赞同 评论 显示 通知',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_display_like_comment',
    highlightGroupId: 'notifications_group_display',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_display_reply_comment',
    title: '应用内显示回复我的评论',
    path: '通知设置 · 应用内显示',
    keywords: '回复 评论 显示 通知',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_display_reply_comment',
    highlightGroupId: 'notifications_group_display',
    fallbackAnchorId: ''
  },
  {
    id: 'notifications_display_invite_answer',
    title: '应用内显示邀请回答',
    path: '通知设置 · 应用内显示',
    keywords: '邀请 回答 显示 通知 提问',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.NOTIFICATION,
    anchorId: 'notifications_settings_display_invite_answer',
    highlightGroupId: 'notifications_group_display',
    fallbackAnchorId: ''
  },
  {
    id: 'system_check_update',
    title: '检查更新',
    path: '系统与更新',
    keywords: '检查更新 新版本 升级 下载',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.SYSTEM_UPDATE,
    anchorId: 'system_check_update',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'system_update_whats_new',
    title: '新版本内容',
    path: '系统与更新',
    keywords: '新版本 更新说明 版本内容 发布日志',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.SYSTEM_UPDATE,
    anchorId: 'system_update_whats_new',
    highlightGroupId: '',
    fallbackAnchorId: 'system_check_update'
  },
  {
    id: 'identity_create',
    title: '创建马甲号',
    path: '身份管理',
    keywords: '马甲 创建 新身份 切换身份',
    visibility: SettingsEntryVisibility.AUTHENTICATED_ONLY,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.IDENTITY,
    anchorId: 'identity_create',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'blocking_add_rule',
    title: '添加屏蔽规则',
    path: '内容屏蔽',
    keywords: '添加 规则 关键词 用户 话题 新建',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.BLOCKING_RULES,
    anchorId: 'blocking_add_rule',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
  {
    id: 'developer_mode_toggle',
    title: '开发者模式开关',
    path: '开发者选项',
    keywords: '开发者模式 开关 关闭 隐藏',
    visibility: SettingsEntryVisibility.DEVELOPER_ONLY,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.DEVELOPER,
    anchorId: 'developer_mode_toggle',
    highlightGroupId: '',
    fallbackAnchorId: ''
  },
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
    id: 'appearance_typography_preset',
    title: '正文排版',
    path: '外观与阅读体验 · 阅读',
    keywords: '排版 预设 舒适排版 原有排版 排版预设 行距',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_anchor_typography_preset',
    highlightGroupId: 'appearance_group_reading',
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
    id: 'appearance_theme_mode',
    title: '主题模式',
    path: '外观与阅读体验 · 主题',
    keywords: '主题模式 深色模式 浅色模式 跟随系统 深浅色',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_theme_light',
    highlightGroupId: 'appearance_group_theme',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_immersive_material',
    title: '沉浸光感',
    path: '外观与阅读体验 · 主题',
    keywords: '沉浸 光感 材质 模糊 挡位 玻璃',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_immersive_material_select',
    highlightGroupId: 'appearance_group_theme',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_fab_opacity',
    title: '悬浮按钮透明度',
    path: '外观与阅读体验 · 主题',
    keywords: '透明度 悬浮按钮',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_fab_opacity',
    highlightGroupId: 'appearance_group_theme',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_feed_thumbnail',
    title: '显示信息流缩略图',
    path: '外观与阅读体验 · 信息流',
    keywords: '缩略图 封面 图片 信息流 预览',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_feed_thumbnail',
    highlightGroupId: 'appearance_group_feed',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_refresh_fab',
    title: '显示刷新悬浮按钮',
    path: '外观与阅读体验 · 信息流',
    keywords: '刷新 悬浮按钮 快捷',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_refresh_fab',
    highlightGroupId: 'appearance_group_feed',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_feed_style',
    title: '列表样式',
    path: '外观与阅读体验 · 信息流',
    keywords: '列表样式 卡片 分割线 表面',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_feed_style',
    highlightGroupId: 'appearance_group_feed',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_feed_columns',
    title: '信息流列数',
    path: '外观与阅读体验 · 信息流',
    keywords: '列数 多列 瀑布流 单列 双列',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_feed_columns',
    highlightGroupId: 'appearance_group_feed',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_start_destination',
    title: '应用启动默认页面',
    path: '外观与阅读体验 · 底部导航栏',
    keywords: '启动页 默认页面 页签 启动 打开',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_start_destination',
    highlightGroupId: 'appearance_group_bottom_bar',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_answer_reading_mode',
    title: '回答阅读模式',
    path: '外观与阅读体验 · 回答页',
    keywords: '阅读模式 连续 单篇 回答',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_answer_reading_mode',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_title_auto_hide',
    title: '自动隐藏回答标题',
    path: '外观与阅读体验 · 回答页',
    keywords: '隐藏 标题 上划 回答',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_title_auto_hide',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_question_in_title_bar',
    title: '问题标题集成到顶栏',
    path: '外观与阅读体验 · 回答页',
    keywords: '问题 标题 顶栏 集成',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_question_in_title_bar',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_bottom_bar_auto_hide',
    title: '自动隐藏回答底部按钮',
    path: '外观与阅读体验 · 回答页',
    keywords: '底部 操作按钮 隐藏 上划 下划',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_bottom_bar_auto_hide',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_skip_answer',
    title: '显示跳转下一个回答按钮',
    path: '外观与阅读体验 · 回答页',
    keywords: '跳转 下一个回答 按钮 拖动',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_skip_answer',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_skip_answer_auto_hide',
    title: '滚动时自动隐藏跳转按钮',
    path: '外观与阅读体验 · 回答页',
    keywords: '隐藏 跳转按钮 淡出 上划',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_skip_answer_auto_hide',
    highlightGroupId: 'appearance_group_answer',
    // 依赖“显示跳转下一个回答按钮”开启。
    fallbackAnchorId: 'appearance_skip_answer'
  },
  {
    id: 'appearance_grip_follow_actions',
    title: '操作跟随智感握姿',
    path: '外观与阅读体验 · 回答页',
    keywords: '智感 握姿 传感器 手势 握持',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_grip_follow_actions',
    highlightGroupId: 'appearance_group_answer',
    // 不支持智感握姿的机型该行隐藏，回退到回答页组首行。
    fallbackAnchorId: 'appearance_answer_reading_mode'
  },
  {
    id: 'appearance_pin_answer_date',
    title: '置顶回答日期',
    path: '外观与阅读体验 · 回答页',
    keywords: '置顶 日期 显示 回答',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_pin_answer_date',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_hot_comments',
    title: '显示热评',
    path: '外观与阅读体验 · 回答页',
    keywords: '热评 评论 精选',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_hot_comments',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_answer_switch_mode',
    title: '回答切换手势',
    path: '外观与阅读体验 · 回答页',
    keywords: '切换手势 平滑 竖滑 左右滑 横滑',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_answer_switch_mode',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_answer_switch_sensitivity',
    title: '回答切换灵敏度',
    path: '外观与阅读体验 · 回答页',
    keywords: '灵敏度 切换 阈值',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_answer_switch_sensitivity',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_answer_double_tap',
    title: '双击正文动作',
    path: '外观与阅读体验 · 回答页',
    keywords: '双击 正文 询问 点赞',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_answer_double_tap',
    highlightGroupId: 'appearance_group_answer',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_tap_to_refresh',
    title: '点击底部导航栏回到顶部/刷新',
    path: '外观与阅读体验 · 底部导航栏',
    keywords: '回到顶部 刷新 页签 再点',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_tap_to_refresh',
    highlightGroupId: 'appearance_group_bottom_bar',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_nav_auto_hide',
    title: '滚动时自动隐藏底部导航栏',
    path: '外观与阅读体验 · 底部导航栏',
    keywords: '隐藏 导航栏 滚动 底部',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_nav_auto_hide',
    highlightGroupId: 'appearance_group_bottom_bar',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_volume_page_turn',
    title: '音量键翻页',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '音量键 翻页 电纸书 上下键',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_volume_page_turn',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_page_turn_answer',
    title: '翻页切换回答',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '翻页 切换 回答 电纸书',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_page_turn_answer',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_page_turn_fab',
    title: '显示翻页悬浮按钮',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '翻页 悬浮按钮 翻页键',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_page_turn_fab',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_page_turn_percent',
    title: '翻页距离',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '翻页 距离 幅度',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_page_turn_percent',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_page_turn_guide',
    title: '显示翻页位置线',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '位置线 翻页 指示线',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_page_turn_guide',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_content_end_marker',
    title: '显示内容结束标记',
    path: '外观与阅读体验 · 电纸书翻页',
    keywords: '结束标记 完 到底',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_content_end_marker',
    highlightGroupId: 'appearance_group_page_turn',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_share_action',
    title: '分享操作',
    path: '外观与阅读体验 · 交互',
    keywords: '分享 默认行为 菜单',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_share_action',
    highlightGroupId: 'appearance_group_interaction',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_search_hot',
    title: '搜索界面显示热搜',
    path: '外观与阅读体验 · 搜索',
    keywords: '热搜 搜索 热榜',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_search_hot',
    highlightGroupId: 'appearance_group_search',
    fallbackAnchorId: ''
  },
  {
    id: 'appearance_search_history',
    title: '记录并显示搜索历史',
    path: '外观与阅读体验 · 搜索',
    keywords: '搜索历史 记录 关键词',
    visibility: SettingsEntryVisibility.ALWAYS,
    targetKind: SettingsTargetKind.SETTING_ITEM,
    paneId: SettingsPaneId.APPEARANCE,
    anchorId: 'appearance_search_history',
    highlightGroupId: 'appearance_group_search',
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
