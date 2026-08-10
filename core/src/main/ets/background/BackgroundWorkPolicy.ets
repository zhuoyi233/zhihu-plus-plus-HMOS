export enum BackgroundRoute {
  FOREGROUND_ONLY = 'foreground_only',
  TRANSIENT_FINISH = 'transient_finish',
  DEFERRED_SYSTEM = 'deferred_system',
  CONTINUOUS_USER_VISIBLE = 'continuous_user_visible',
  NOT_SUPPORTED = 'not_supported'
}

export enum ZhihuWorkload {
  USER_REFRESH = 'user_refresh',
  FINISH_IN_FLIGHT_REQUEST = 'finish_in_flight_request',
  NON_URGENT_MAINTENANCE = 'non_urgent_maintenance',
  PERIODIC_FEED_CRAWL = 'periodic_feed_crawl',
  AUDIO_PLAYBACK = 'audio_playback'
}

export interface BackgroundWorkDecision {
  route: BackgroundRoute;
  requiresVisibleNotification: boolean;
  reason: string;
}

export function decideBackgroundRoute(workload: ZhihuWorkload): BackgroundWorkDecision {
  switch (workload) {
    case ZhihuWorkload.USER_REFRESH:
      return {
        route: BackgroundRoute.FOREGROUND_ONLY,
        requiresVisibleNotification: false,
        reason: '刷新和推荐计算由前台用户操作触发'
      };
    case ZhihuWorkload.FINISH_IN_FLIGHT_REQUEST:
      return {
        route: BackgroundRoute.TRANSIENT_FINISH,
        requiresVisibleNotification: false,
        reason: '仅收尾已经开始的有限操作，不启动新任务'
      };
    case ZhihuWorkload.NON_URGENT_MAINTENANCE:
      return {
        route: BackgroundRoute.DEFERRED_SYSTEM,
        requiresVisibleNotification: false,
        reason: '由系统根据时间、网络和电量条件择机执行'
      };
    case ZhihuWorkload.AUDIO_PLAYBACK:
      return {
        route: BackgroundRoute.CONTINUOUS_USER_VISIBLE,
        requiresVisibleNotification: true,
        reason: '未来音频播放必须使用合规模式并保持用户可感知'
      };
    case ZhihuWorkload.PERIODIC_FEED_CRAWL:
    default:
      return {
        route: BackgroundRoute.NOT_SUPPORTED,
        requiresVisibleNotification: false,
        reason: '首版禁止后台常驻或周期性抓取知乎 Feed'
      };
  }
}
