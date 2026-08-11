import { common } from '@kit.AbilityKit';
import { P1Destination, P1DestinationName } from 'core';
import {
  CookieSessionStore,
  HttpProbeClient,
  LoginVerificationStatus,
  parseCookieAssignments,
  safeSessionSummary,
  SessionCookie,
  ZhihuLoginClient
} from 'data';

@Component
export struct TechnicalLabPage {
  @State private networkStatus: string = 'HTTP 探针尚未运行';
  @State private sessionStatus: string = '会话探针尚未运行';
  @State private loginStatus: string = '当前为游客模式';
  @State private cookieInput: string = '';
  @State private loginBusy: boolean = false;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  private readonly httpProbeClient: HttpProbeClient = new HttpProbeClient();
  private readonly loginClient: ZhihuLoginClient = new ZhihuLoginClient();

  aboutToAppear(): void {
    this.restoreLogin();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          Text('Zhihu++ HarmonyOS')
            .id('p0_title')
            .fontSize($r('app.float.p1_display_font_size'))
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))

          Text('P0 技术验证工程')
            .id('p0_subtitle')
            .fontSize($r('app.float.p1_heading_font_size'))
            .fontColor($r('app.color.primary_text'))

          Text('目标与最低兼容 API 24')
            .id('p0_sdk_baseline')
            .fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Text('P0 门禁已收口；此页面仅用于技术回归验证')
            .id('p0_next_step')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Text(this.networkStatus)
            .id('p0_http_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Text(this.sessionStatus)
            .id('p0_session_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Text(this.loginStatus)
            .id('p0_login_status')
            .fontSize($r('app.float.p1_secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))

          Button('打开原生长正文原型')
            .id('p0_open_reader_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.READER_PROBE });
            })

          Button('打开图片与 GIF 原型')
            .id('p0_open_image_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.IMAGE_PROBE });
            })

          Button('打开数据库迁移原型')
            .id('p0_open_database_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.DATABASE_PROBE });
            })

          Button('打开深链解析原型')
            .id('p0_open_deep_link_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.DEEP_LINK_PROBE });
            })

          Button('打开二维码扫描原型')
            .id('p0_open_qr_scan_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.QR_SCAN_PROBE });
            })

          Button('打开后台任务约束原型')
            .id('p0_open_background_task_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.BACKGROUND_TASK_PROBE });
            })

          Button('打开领域模型夹具门禁')
            .id('p1_open_domain_fixture_probe')
            .onClick(() => {
              this.navigate({ name: P1DestinationName.DOMAIN_FIXTURE_PROBE });
            })

          TextInput({ text: this.cookieInput, placeholder: '粘贴 z_c0=…; d_c0=…' })
            .id('p0_cookie_input')
            .type(InputType.Password)
            .enabled(!this.loginBusy)
            .onChange((value: string) => {
              this.cookieInput = value;
            })

          Column({ space: $r('app.float.p1_spacing_small') }) {
            Button('运行 HTTP 探针')
              .id('p0_run_http_probe')
              .width('100%')
              .onClick(() => {
                this.runHttpProbe();
              })

            Button('取消')
              .id('p0_cancel_http_probe')
              .width('100%')
              .onClick(() => {
                this.httpProbeClient.cancel();
                this.networkStatus = 'HTTP 探针已取消';
              })
          }
          .width('100%')

          Column({ space: $r('app.float.p1_spacing_small') }) {
            Button('验证并保存 Cookie')
              .id('p0_import_cookie')
              .width('100%')
              .enabled(!this.loginBusy && this.cookieInput.trim().length > 0)
              .onClick(() => {
                this.importCookie();
              })

            Button('游客模式')
              .id('p0_guest_mode')
              .width('100%')
              .enabled(!this.loginBusy)
              .onClick(() => {
                this.loginStatus = '当前为游客模式；已保存的登录不会被删除';
              })
          }
          .width('100%')

          Button('退出并清理本地会话')
            .id('p0_logout')
            .enabled(!this.loginBusy)
            .onClick(() => {
              this.logout();
            })

          Column({ space: $r('app.float.p1_spacing_small') }) {
            Button('写入测试会话')
              .id('p0_save_session_probe')
              .width('100%')
              .onClick(() => {
                this.saveSessionProbe();
              })

            Button('恢复并清理')
              .id('p0_restore_session_probe')
              .width('100%')
              .onClick(() => {
                this.restoreSessionProbe();
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding($r('app.float.p1_page_padding'))
      }
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
    return new CookieSessionStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private async saveSessionProbe(): Promise<void> {
    this.sessionStatus = '正在加密测试会话…';
    const now = Date.now();
    const cookies: Array<SessionCookie> = [
      { name: 'd_c0', value: 'p0-session-probe' },
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
    const cookies = parseCookieAssignments(rawCookie);
    this.loginBusy = true;
    this.loginStatus = '正在验证 Cookie…';
    try {
      const result = await this.loginClient.verify(cookies);
      if (result.status === LoginVerificationStatus.AUTHENTICATED && result.profile !== undefined) {
        await this.sessionStore().save(cookies);
        this.loginStatus = `已登录：${result.profile.name}`;
      } else {
        this.loginStatus = result.message;
      }
    } catch (_error) {
      this.loginStatus = 'Cookie 已验证，但加密保存失败';
    } finally {
      this.loginBusy = false;
    }
  }

  private async restoreLogin(): Promise<void> {
    this.loginBusy = true;
    try {
      const store = this.sessionStore();
      const cookies = await store.load();
      if (cookies.length === 0) {
        this.loginStatus = '当前为游客模式';
        return;
      }
      this.loginStatus = '正在验证已保存的登录…';
      const result = await this.loginClient.verify(cookies);
      if (result.status === LoginVerificationStatus.AUTHENTICATED && result.profile !== undefined) {
        this.loginStatus = `已登录：${result.profile.name}`;
      } else if (result.status === LoginVerificationStatus.REJECTED ||
        result.status === LoginVerificationStatus.INVALID_INPUT) {
        await store.clear();
        this.loginStatus = `${result.message}，已清理本地会话`;
      } else {
        this.loginStatus = `${result.message}；本地会话已保留`;
      }
    } catch (_error) {
      this.loginStatus = '登录恢复失败；本地会话未改动';
    } finally {
      this.loginBusy = false;
    }
  }

  private async logout(): Promise<void> {
    this.loginBusy = true;
    this.cookieInput = '';
    try {
      await this.sessionStore().clear();
      this.loginStatus = '已退出登录并清理本地会话';
    } catch (_error) {
      this.loginStatus = '退出清理失败，请重试';
    } finally {
      this.loginBusy = false;
    }
  }
}
