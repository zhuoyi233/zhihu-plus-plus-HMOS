import { preferences } from '@kit.ArkData';

/**
 * 知乎日报原生渲染开关（P4 集中式本地开关）。
 *
 * 默认开启：日报列表与 `DAILY_STORY` 深链走原生日报页（一次请求 + 本地解析），
 * 关闭时恢复旧行为（列表内解析原文目标后直跳回答/问题/文章，失败回落浏览器）。
 * 这里只承载产品状态，不引入 reader/UI 依赖。
 */

export enum DailyStoryReaderMode {
  /** 旧路径：保持「解析原文目标后直跳」的行为。 */
  LEGACY = 'legacy',
  /** 新路径：原生日报阅读页。 */
  NATIVE = 'native'
}

export const DEFAULT_DAILY_STORY_READER_MODE: DailyStoryReaderMode = DailyStoryReaderMode.NATIVE;

/** AppStorage 广播字符串 → 模式；未知值回退默认（原生阅读），接受空串/未存储。 */
export function decodeDailyStoryReaderMode(value: string | undefined): DailyStoryReaderMode {
  return value === DailyStoryReaderMode.LEGACY ? DailyStoryReaderMode.LEGACY : DEFAULT_DAILY_STORY_READER_MODE;
}

export function dailyStoryReaderModeLabel(mode: DailyStoryReaderMode): string {
  return mode === DailyStoryReaderMode.NATIVE ? '原生阅读' : '跟随原文链接';
}

export function dailyStoryReaderModeDescription(mode: DailyStoryReaderMode): string {
  return mode === DailyStoryReaderMode.NATIVE
    ? '在应用内直接排版日报正文：保留引用块、作者、正文图与栏目，可分享日报地址'
    : '保留旧行为：先解析日报里的原文链接，直接打开对应的回答、问题或文章';
}

export function isNativeDailyStoryEnabled(mode: string | undefined): boolean {
  return decodeDailyStoryReaderMode(mode) === DailyStoryReaderMode.NATIVE;
}

/** 偏好存储原始值 → 模式；非字符串（含缺失）按未存储处理。 */
export function decodeDailyStoryReaderModeValue(value: preferences.ValueType): DailyStoryReaderMode {
  return typeof value === 'string' ? decodeDailyStoryReaderMode(value) : DEFAULT_DAILY_STORY_READER_MODE;
}
