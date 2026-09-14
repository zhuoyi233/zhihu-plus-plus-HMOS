import { common } from '@kit.AbilityKit';
import { P1Destination, P1DestinationName } from 'core';
import {
  COOKIE_HEADER_MAX_LENGTH,
  CookieSessionStore,
  getAppSessionOwner,
  HttpProbeClient,
  safeSessionSummary,
  SessionCookie,
  SessionRepository,
  SessionState,
  SessionStatus
} from 'data';
import { AppNavigationRow } from './AppPageChrome';

@Component
export struct TechnicalLabPage {
  @State private networkStatus: string = 'HTTP 探针尚未运行';
  @State private sessionStatus: string = '会话探针尚未运行';
  @State private loginStatus: string = '正在读取登录状态…';
  @State private cookieInput: string = '';
  @State private loginBusy: boolean = false;
  @State private authenticated: boolean = false;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  private readonly httpProbeClient: HttpProbeClient = new HttpProbeClient();

  aboutToAppear(): void {
    this.refreshLoginStatus();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          Blank().height(64)
          Text('账号与会话')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.loginStatus)
              .id('developer_login_status')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Button('验证登录')
              .id('developer_verify_login')
              .width('100%')
              .enabled(!this.loginBusy)
              .onClick((): void => {
                void this.verifyLogin();
              })
            Text('手动设置 Cookie')
              .fontSize($r('app.float.p1_heading_font_size'))
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Text('请输入完整 Cookie 字符串。仅在本机验证并加密保存，提交后输入框会立即清空。')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
            TextInput({ text: this.cookieInput, placeholder: 'name1=value1; name2=value2' })
              .id('developer_cookie_input')
              .type(InputType.Password)
              .maxLength(COOKIE_HEADER_MAX_LENGTH)
              .enabled(!this.loginBusy)
              .onChange((value: string): void => {
                this.cookieInput = value;
              })
            Button('确认设置并验证')
              .id('developer_cookie_submit')
              .width('100%')
              .enabled(!this.loginBusy && this.cookieInput.trim().length > 0)
              .onClick((): void => {
                void this.importCookie();
              })
            Button('退出并清理本地会话')
              .id('developer_logout')
              .width('100%')
              .enabled(!this.loginBusy)
              .onClick((): void => {
                void this.logout();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('网络诊断')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.networkStatus)
              .id('http_status')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Button('运行 HTTP 探针')
              .id('run_http_probe')
              .width('100%')
              .onClick((): void => {
                void this.runHttpProbe();
              })
            Button('取消 HTTP 探针')
              .id('cancel_http_probe')
              .width('100%')
              .onClick((): void => {
                this.httpProbeClient.cancel();
                this.networkStatus = 'HTTP 探针已取消';
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('调试页面')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column() {
            AppNavigationRow({ title: '原生长正文', description: '验证正文解析、排版与公式渲染',
              testId: 'open_reader_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.READER_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '图片与 GIF', description: '验证图片加载和动图展示',
              testId: 'open_image_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.IMAGE_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '数据库迁移', description: '验证本地数据库结构升级',
              testId: 'open_database_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.DATABASE_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '深链解析', description: '验证知乎链接到原生页面的路由',
              testId: 'open_deep_link_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.DEEP_LINK_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '二维码扫描', description: '验证 Scan Kit 与结果安全策略',
              testId: 'open_qr_scan_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.QR_SCAN_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '后台任务约束', description: '验证后台执行边界',
              testId: 'open_background_task_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.BACKGROUND_TASK_PROBE }) })
            Divider().color($r('app.color.divider_color'))
            AppNavigationRow({ title: '领域模型夹具门禁', description: '运行领域模型设备端回归',
              testId: 'p1_open_domain_fixture_probe', grouped: true,
              onRowClick: (): void => this.navigate({ name: P1DestinationName.DOMAIN_FIXTURE_PROBE }) })
          }
          .width('100%')
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))

          Text('本地存储诊断')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
          Column({ space: $r('app.float.p1_spacing_medium') }) {
            Text(this.sessionStatus)
              .id('session_status')
              .fontSize($r('app.float.p1_body_font_size'))
              .fontColor($r('app.color.primary_text'))
              .width('100%')
            Text('测试会话会暂时覆盖本地 Cookie 存储；仅用于无真实登录态时的开发验证。')
              .fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text'))
              .width('100%')
            Button('写入测试会话')
              .id('save_session_probe')
              .width('100%')
              .enabled(!this.authenticated)
              .onClick((): void => {
                void this.saveSessionProbe();
              })
            Button('恢复并清理测试会话')
              .id('restore_session_probe')
              .width('100%')
              .enabled(!this.authenticated)
              .onClick((): void => {
                void this.restoreSessionProbe();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding($r('app.float.p1_card_padding'))
          .borderRadius($r('app.float.p1_card_radius'))
          .backgroundColor($r('app.color.surface_background'))
        }
        .width('100%')
        .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
          bottom: $r('app.float.p1_page_padding') })
      }
      .scrollBar(BarState.Off)
      .id('p1_technical_lab_scroll')
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .backgroundColor($r('app.color.page_background'))
    }
    .id('p1_technical_lab_top_start_container')
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
    .backgroundColor($r('app.color.page_background'))
  }

  private async runHttpProbe(): Promise<void> {
    this.networkStatus = 'HTTP 请求中…';
    try {
      const result = await this.httpProbeClient.requestPublicQuestion();
      this.networkStatus = `HTTP ${result.statusCode}，响应 ${result.body.length} 字符`;
    } catch (error) {
      const message = error instanceof Error ? error.message : '未知错误';
      this.networkStatus = `HTTP 探针失败：${message}`;
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
    }
  }

  private async restoreSessionProbe(): Promise<void> {
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
    }
  }

  private async importCookie(): Promise<void> {
    const rawCookie = this.cookieInput;
    this.cookieInput = '';
    this.loginBusy = true;
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
      this.loginBusy = false;
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
    this.loginBusy = true;
    this.loginStatus = '正在验证登录…';
    try {
      const state = await this.sessionRepository().load();
      this.applySessionState(state);
      this.broadcastSessionChange(state.status === SessionStatus.AUTHENTICATED);
    } catch (_error) {
      this.loginStatus = '登录验证失败；本地会话未改动';
    } finally {
      this.loginBusy = false;
    }
  }

  private async logout(): Promise<void> {
    this.loginBusy = true;
    this.cookieInput = '';
    try {
      const state = await this.sessionRepository().logout();
      this.applySessionState(state);
      this.broadcastSessionChange(false);
    } catch (_error) {
      this.loginStatus = '退出清理失败，请重试';
    } finally {
      this.loginBusy = false;
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
