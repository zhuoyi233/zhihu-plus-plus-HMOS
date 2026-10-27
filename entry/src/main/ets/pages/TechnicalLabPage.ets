import { AppDestination, AppDestinationName } from 'core';
import {
  COOKIE_HEADER_MAX_LENGTH,
  CookieSessionStore,
  getAppSessionOwner,
  HttpProbeClient,
  onThemeColor,
  DEFAULT_THEME_COLOR,
  FeedCardStyle,
  safeSessionSummary,
  SessionCookie,
  SessionRepository,
  SessionState,
  SessionStatus
} from 'data';
import { AppNavigationRow } from './AppPageChrome';
import { settingsGroupBackground, settingsGroupRadius } from './AccountSettingsLayout';

/**
 * 开发者选项：可嵌入设置右栏。
 *
 * - 开发者模式从全局 developerModeEnabled 读取并监听，目录、搜索、正文同一门禁；
 * - Cookie 只存在当前页面会话内存，模式关闭、离开页面或提交时立即清空；
 * - 会话类操作（验证、Cookie 提交、退出、测试会话）共用一把互斥锁，重复点击或重排不会重放；
 * - HTTP 探针用请求代次丢弃“取消后迟到”的结果，逻辑离页时取消，尺寸变化不取消。
 */
@Component
export struct TechnicalLabPage {
  @State private developerModeEnabled: boolean = AppStorage.get<boolean>('developerModeEnabled') ?? false;
  @State private networkStatus: string = 'HTTP 探针尚未运行';
  @State private sessionStatus: string = '会话探针尚未运行';
  @State private loginStatus: string = '正在读取登录状态…';
  @State private cookieInput: string = '';
  /** 会话类操作互斥：任一会话写入进行中时，其余会话操作一律禁用。 */
  @State private sessionBusy: boolean = false;
  @State private probeBusy: boolean = false;
  @State private authenticated: boolean = false;
  /** 嵌入设置容器：不画额外顶部占位，标题由宿主绘制。 */
  @Prop embedded: boolean = false;
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('feedCardStyle') private feedCardStyle: string = FeedCardStyle.DIVIDER;
  @StorageProp('developerModeEnabled') @Watch('onDeveloperModeChanged')
  private developerModeStorage: boolean = false;
  navigate: (destination: AppDestination) => void = (_destination: AppDestination): void => {
  };
  /** 只负责持久化与广播；涉及导航的部分由入口来源（目录/独立路由）决定。 */
  onDeveloperModeDisabled: () => void = (): void => {};
  private readonly httpProbeClient: HttpProbeClient = new HttpProbeClient();
  private probeGeneration: number = 0;

  aboutToAppear(): void {
    this.developerModeEnabled = this.developerModeStorage;
    this.refreshLoginStatus();
  }

  aboutToDisappear(): void {
    // 逻辑离页：取消探针并作废在途结果，避免回包更新已销毁视图。
    this.cancelHttpProbe();
    this.cookieInput = '';
  }

  private onDeveloperModeChanged(): void {
    this.developerModeEnabled = this.developerModeStorage;
    if (!this.developerModeStorage) {
      // 模式关闭后不得保留敏感输入或在途探针。
      this.cookieInput = '';
      this.cancelHttpProbe();
    }
  }

  private isCardStyle(): boolean {
    return this.feedCardStyle === FeedCardStyle.CARD;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.spacing_medium') }) {
          if (!this.developerModeEnabled) {
            Column({ space: $r('app.float.spacing_small') }) {
              Text('开发者模式已关闭')
                .fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text'))
                .width('100%')
              Text('开发者选项已从设置目录与搜索结果中隐藏。需要时在“关于应用”里连续点击版本号重新开启。')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .width('100%')
            }
            .width('100%')
            .padding($r('app.float.card_padding'))
            .backgroundColor(settingsGroupBackground(this.feedCardStyle))
            .borderRadius(settingsGroupRadius(this.feedCardStyle))
          } else {
            this.sectionTitle('开发者模式')
            Column({ space: 4 }) {
              Row() {
                Column({ space: 4 }) {
                  Text('开发者模式')
                    .fontSize($r('app.float.body_font_size'))
                    .fontColor($r('app.color.primary_text'))
                  Text('关闭后将立即隐藏开发者选项并回到设置目录')
                    .fontSize($r('app.float.secondary_font_size'))
                    .fontColor($r('app.color.secondary_text'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.developerModeEnabled })
                  .id('developer_mode_toggle')
                  .selectedColor(this.resolvedThemeColor)
                  .onChange((enabled: boolean): void => {
                    this.developerModeEnabled = enabled;
                    if (!enabled) {
                      this.cookieInput = '';
                      this.cancelHttpProbe();
                      this.onDeveloperModeDisabled();
                    }
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding($r('app.float.card_padding'))
            .borderRadius(settingsGroupRadius(this.feedCardStyle))
            .backgroundColor(settingsGroupBackground(this.feedCardStyle))

            this.sessionGroup()
            this.networkGroup()
            this.probePagesGroup()
            this.storageGroup()
          }
        }
        .width('100%')
        .padding({
          left: $r('app.float.page_padding'),
          right: $r('app.float.page_padding'),
          top: this.embedded ? 4 : 12,
          bottom: $r('app.float.page_padding')
        })
      }
      .scrollBar(BarState.Off)
      .id('technical_lab_scroll')
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .id('technical_lab_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title)
      .fontSize($r('app.float.secondary_font_size'))
      .fontColor($r('app.color.secondary_text'))
      .width('100%')
      .padding({ left: 4 })
  }

  @Builder
  private sessionGroup() {
    this.sectionTitle('账号与会话')
    Column({ space: $r('app.float.spacing_medium') }) {
      Text(this.loginStatus)
        .id('developer_login_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Button('验证登录')
        .id('developer_verify_login')
        .width('100%')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.sessionBusy)
        .onClick((): void => {
          void this.verifyLogin();
        })
      Text('手动设置 Cookie')
        .fontSize($r('app.float.heading_font_size'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('请输入完整 Cookie 字符串。仅在本机验证并加密保存，提交后输入框会立即清空。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      TextInput({ text: this.cookieInput, placeholder: 'name1=value1; name2=value2' })
        .id('developer_cookie_input')
        .type(InputType.Password)
        .maxLength(COOKIE_HEADER_MAX_LENGTH)
        .enabled(!this.sessionBusy)
        .onChange((value: string): void => {
          this.cookieInput = value;
        })
      Button('确认设置并验证')
        .id('developer_cookie_submit')
        .width('100%')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.sessionBusy && this.cookieInput.trim().length > 0)
        .onClick((): void => {
          void this.importCookie();
        })
      Button('退出并清理本地会话')
        .id('developer_logout')
        .width('100%')
        .fontColor($r('app.color.error_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(!this.sessionBusy)
        .accessibilityText('退出登录并清理本地会话，不删除收藏、屏蔽规则与历史记录')
        .onClick((): void => {
          void this.logout();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
  }

  @Builder
  private networkGroup() {
    this.sectionTitle('网络诊断')
    Column({ space: $r('app.float.spacing_medium') }) {
      Text(this.networkStatus)
        .id('http_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Button(this.probeBusy ? 'HTTP 请求中…' : '运行 HTTP 探针')
        .id('run_http_probe')
        .width('100%')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.probeBusy)
        .onClick((): void => {
          void this.runHttpProbe();
        })
      Button('取消 HTTP 探针')
        .id('cancel_http_probe')
        .width('100%')
        .fontColor($r('app.color.primary_text'))
        .backgroundColor($r('app.color.control_background'))
        .enabled(this.probeBusy)
        .onClick((): void => {
          this.cancelHttpProbe();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
  }

  @Builder
  private probePagesGroup() {
    this.sectionTitle('调试页面')
    Column() {
      AppNavigationRow({ title: '原生长正文', description: '验证正文解析、排版与公式渲染',
        testId: 'open_reader_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.READER_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '图片与 GIF', description: '验证图片加载和动图展示',
        testId: 'open_image_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.IMAGE_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '连续阅读原型', description: 'P0：单列表连续滚动 · 懒加载 · 锚点补偿 · 正文释放',
        testId: 'open_continuous_reading_proto', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.CONTINUOUS_READING_PROTOTYPE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '数据库迁移', description: '验证本地数据库结构升级',
        testId: 'open_database_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.DATABASE_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '深链解析', description: '验证知乎链接到原生页面的路由',
        testId: 'open_deep_link_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.DEEP_LINK_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '二维码扫描', description: '验证 Scan Kit 与结果安全策略',
        testId: 'open_qr_scan_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.QR_SCAN_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '后台任务约束', description: '验证后台执行边界',
        testId: 'open_background_task_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.BACKGROUND_TASK_PROBE }) })
      Divider().color($r('app.color.divider_color'))
      AppNavigationRow({ title: '领域模型夹具门禁', description: '运行领域模型设备端回归',
        testId: 'open_domain_fixture_probe', grouped: true,
        onRowClick: (): void => this.navigate({ name: AppDestinationName.DOMAIN_FIXTURE_PROBE }) })
    }
    .width('100%')
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
  }

  @Builder
  private storageGroup() {
    this.sectionTitle('本地存储诊断')
    Column({ space: $r('app.float.spacing_medium') }) {
      Text(this.sessionStatus)
        .id('session_status')
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Text('测试会话会暂时覆盖本地 Cookie 存储；仅用于无真实登录态时的开发验证，已有真实登录态时不可用。')
        .fontSize($r('app.float.secondary_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')
      Button('写入测试会话')
        .id('save_session_probe')
        .width('100%')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.authenticated && !this.sessionBusy)
        .onClick((): void => {
          void this.saveSessionProbe();
        })
      Button('恢复并清理测试会话')
        .id('restore_session_probe')
        .width('100%')
        .fontColor(onThemeColor(this.resolvedThemeColor))
        .backgroundColor(this.resolvedThemeColor)
        .enabled(!this.authenticated && !this.sessionBusy)
        .onClick((): void => {
          void this.restoreSessionProbe();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.card_padding'))
    .borderRadius(settingsGroupRadius(this.feedCardStyle))
    .backgroundColor(settingsGroupBackground(this.feedCardStyle))
  }

  private cancelHttpProbe(): void {
    this.probeGeneration += 1;
    this.probeBusy = false;
    if (this.networkStatus === 'HTTP 请求中…') {
      this.networkStatus = 'HTTP 探针已取消';
    }
    this.httpProbeClient.cancel();
  }

  private async runHttpProbe(): Promise<void> {
    if (this.probeBusy) {
      return;
    }
    const generation = ++this.probeGeneration;
    this.probeBusy = true;
    this.networkStatus = 'HTTP 请求中…';
    try {
      const result = await this.httpProbeClient.requestPublicQuestion();
      if (generation !== this.probeGeneration) {
        return;
      }
      this.networkStatus = `HTTP ${result.statusCode}，响应 ${result.body.length} 字符`;
    } catch (error) {
      if (generation !== this.probeGeneration) {
        return;
      }
      const message = error instanceof Error ? error.message : '未知错误';
      this.networkStatus = `HTTP 探针失败：${message}`;
    } finally {
      if (generation === this.probeGeneration) {
        this.probeBusy = false;
      }
    }
  }

  private sessionStore(): CookieSessionStore {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取应用上下文');
    }
    return new CookieSessionStore(context);
  }

  private sessionRepository(): SessionRepository {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('无法获取应用上下文');
    }
    return getAppSessionOwner(context).getRepository();
  }

  private async saveSessionProbe(): Promise<void> {
    if (this.sessionBusy || this.authenticated) {
      return;
    }
    this.sessionBusy = true;
    this.sessionStatus = '正在加密测试会话…';
    const now = Date.now();
    const cookies: Array<SessionCookie> = [
      { name: 'd_c0', value: 'probe-session-value' },
      { name: 'expired_probe', value: 'remove-me', expiresAt: now - 1 }
    ];
    try {
      await this.sessionStore().save(cookies, now);
      this.sessionStatus = '测试会话已加密保存；可重启应用后恢复';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.sessionStatus = `会话保存失败：${message}`;
    } finally {
      this.sessionBusy = false;
    }
  }

  private async restoreSessionProbe(): Promise<void> {
    if (this.sessionBusy || this.authenticated) {
      return;
    }
    this.sessionBusy = true;
    this.sessionStatus = '正在恢复测试会话…';
    const store = this.sessionStore();
    try {
      const cookies = await store.load();
      const restored = cookies.some((cookie: SessionCookie) => cookie.name === 'd_c0');
      const expiredRemoved = !cookies.some((cookie: SessionCookie) => cookie.name === 'expired_probe');
      await store.clear();
      this.sessionStatus = restored && expiredRemoved
        ? safeSessionSummary('恢复成功并已清理', cookies)
        : '未找到测试会话，或过期清理失败';
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.sessionStatus = `会话恢复失败：${message}`;
    } finally {
      this.sessionBusy = false;
    }
  }

  private async importCookie(): Promise<void> {
    if (this.sessionBusy) {
      return;
    }
    const rawCookie = this.cookieInput;
    this.cookieInput = '';
    this.sessionBusy = true;
    this.loginStatus = '正在验证 Cookie…';
    try {
      const state = await this.sessionRepository().beginLoginWithCookieHeader(rawCookie).result;
      this.applySessionState(state);
      if (state.status === SessionStatus.AUTHENTICATED) {
        this.broadcastSessionChange(true);
      }
    } catch (_error) {
      this.loginStatus = 'Cookie 验证失败，请稍后重试';
    } finally {
      this.sessionBusy = false;
    }
  }

  private refreshLoginStatus(): void {
    try {
      this.applySessionState(this.sessionRepository().getState());
    } catch (_error) {
      this.loginStatus = '无法读取登录状态';
    }
  }

  private async verifyLogin(): Promise<void> {
    if (this.sessionBusy) {
      return;
    }
    this.sessionBusy = true;
    this.loginStatus = '正在验证登录…';
    try {
      const state = await this.sessionRepository().load();
      this.applySessionState(state);
      this.broadcastSessionChange(state.status === SessionStatus.AUTHENTICATED);
    } catch (_error) {
      this.loginStatus = '登录验证失败；本地会话未改动';
    } finally {
      this.sessionBusy = false;
    }
  }

  private async logout(): Promise<void> {
    if (this.sessionBusy) {
      return;
    }
    this.sessionBusy = true;
    this.cookieInput = '';
    try {
      const state = await this.sessionRepository().logout();
      this.applySessionState(state);
      this.broadcastSessionChange(false);
    } catch (_error) {
      this.loginStatus = '退出清理失败，请重试';
    } finally {
      this.sessionBusy = false;
    }
  }

  private applySessionState(state: SessionState): void {
    this.loginStatus = state.message;
    this.authenticated = state.status === SessionStatus.AUTHENTICATED;
  }

  private broadcastSessionChange(authenticated: boolean): void {
    const nextSessionTick = (AppStorage.get<number>('sessionStateTick') ?? 0) + 1;
    AppStorage.setOrCreate('sessionStateTick', nextSessionTick);
    if (authenticated) {
      const nextFeedTick = (AppStorage.get<number>('loginFeedReloadTick') ?? 0) + 1;
      AppStorage.setOrCreate('loginFeedReloadTick', nextFeedTick);
    }
  }
}
