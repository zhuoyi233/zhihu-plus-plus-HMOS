import { common } from '@kit.AbilityKit';
import { HttpProbeClient } from '../network/HttpProbeClient';
import {
  LoginVerificationStatus,
  ZhihuLoginClient
} from '../network/ZhihuLoginClient';
import {
  parseCookieAssignments,
  safeSessionSummary,
  SessionCookie
} from '../session/CookieSession';
import { CookieSessionStore } from '../session/CookieSessionStore';
import { ReaderProbe } from './ReaderProbe';

@Entry
@Component
struct Index {
  @State private networkStatus: string = 'HTTP 探针尚未运行';
  @State private sessionStatus: string = '会话探针尚未运行';
  @State private loginStatus: string = '当前为游客模式';
  @State private cookieInput: string = '';
  @State private loginBusy: boolean = false;
  @State private showReaderProbe: boolean = false;
  private readonly httpProbeClient: HttpProbeClient = new HttpProbeClient();
  private readonly loginClient: ZhihuLoginClient = new ZhihuLoginClient();

  aboutToAppear(): void {
    this.restoreLogin();
  }

  build() {
    if (this.showReaderProbe) {
      ReaderProbe({
        onBack: () => {
          this.showReaderProbe = false;
        }
      })
    } else {
      Column({ space: 16 }) {
      Text('Zhihu++ HarmonyOS')
        .id('p0_title')
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      Text('P0 技术验证工程')
        .id('p0_subtitle')
        .fontSize(20)
        .fontColor($r('app.color.primary_text'))

      Text('目标 API 24 · 最低兼容 API 20')
        .id('p0_sdk_baseline')
        .fontSize(16)
        .fontColor($r('app.color.secondary_text'))

      Text('下一步：网络、会话、签名、正文与存储验证')
        .id('p0_next_step')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Text(this.networkStatus)
        .id('p0_http_status')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Text(this.sessionStatus)
        .id('p0_session_status')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Text(this.loginStatus)
        .id('p0_login_status')
        .fontSize(15)
        .fontColor($r('app.color.secondary_text'))

      Button('打开原生长正文原型')
        .id('p0_open_reader_probe')
        .onClick(() => {
          this.showReaderProbe = true;
        })

      TextInput({ text: this.cookieInput, placeholder: '粘贴 z_c0=…; d_c0=…' })
        .id('p0_cookie_input')
        .type(InputType.Password)
        .enabled(!this.loginBusy)
        .onChange((value: string) => {
          this.cookieInput = value;
        })

      Row({ space: 12 }) {
        Button('运行 HTTP 探针')
          .id('p0_run_http_probe')
          .onClick(() => {
            this.runHttpProbe();
          })

        Button('取消')
          .id('p0_cancel_http_probe')
          .onClick(() => {
            this.httpProbeClient.cancel();
            this.networkStatus = 'HTTP 探针已取消';
          })
      }

      Row({ space: 12 }) {
        Button('验证并保存 Cookie')
          .id('p0_import_cookie')
          .enabled(!this.loginBusy && this.cookieInput.trim().length > 0)
          .onClick(() => {
            this.importCookie();
          })

        Button('游客模式')
          .id('p0_guest_mode')
          .enabled(!this.loginBusy)
          .onClick(() => {
            this.loginStatus = '当前为游客模式；已保存的登录不会被删除';
          })
      }

      Button('退出并清理本地会话')
        .id('p0_logout')
        .enabled(!this.loginBusy)
        .onClick(() => {
          this.logout();
        })

      Row({ space: 12 }) {
        Button('写入测试会话')
          .id('p0_save_session_probe')
          .onClick(() => {
            this.saveSessionProbe();
          })

        Button('恢复并清理')
          .id('p0_restore_session_probe')
          .onClick(() => {
            this.restoreSessionProbe();
          })
      }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(24)
      .backgroundColor($r('app.color.page_background'))
    }
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
