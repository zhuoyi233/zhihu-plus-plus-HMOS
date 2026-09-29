import {
  AppUpdateDownloadSource, DEFAULT_THEME_COLOR, onThemeColor, sha256HexOfFile, updateDownloadSources
} from 'data';
import { pasteboard, request } from '@kit.BasicServicesKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import notificationManager from '@ohos.notificationManager';
import notification from '@ohos.notification';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

interface PopupStateChange {
  isVisible: boolean;
}

interface DownloadFailureHint {
  reason: string;
  hint: string;
}

/** reason 字符串与 OpenHarmony request 服务的 Reason 文本逐字对应。 */
const DOWNLOAD_FAILURE_HINTS: DownloadFailureHint[] = [
  { reason: 'NetWork is offline', hint: '网络已断开' },
  { reason: 'Continuous processing task time out', hint: '连接下载源超时' },
  { reason: 'Http protocol error', hint: '下载源响应异常' },
  { reason: 'Redirect error', hint: '下载源重定向异常' },
  { reason: 'Request error', hint: '下载请求失败' },
  { reason: 'Io Error', hint: '文件读写失败' },
  { reason: 'DNS error', hint: '下载源域名解析失败' },
  { reason: 'TCP error', hint: '网络连接失败' },
  { reason: 'TSL/SSL error', hint: '安全连接建立失败' },
  { reason: 'Insufficient space', hint: '设备存储空间不足' }
];

const DOWNLOAD_FAILED_NOTIFICATION_ID = 51001;

function downloadFailureHint(reason: string): string {
  for (const item of DOWNLOAD_FAILURE_HINTS) {
    if (item.reason === reason) {
      return item.hint;
    }
  }
  return reason.length > 0 ? reason : '下载未能完成';
}

@Component
export struct SystemUpdateSettingsPage {
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private selectedSource: AppUpdateDownloadSource | undefined = undefined;
  @State private downloadBusy: boolean = false;
  @State private downloadStatus: string = '';
  @Prop installedVersionLabel: string = '';
  @Prop updateCheckBusy: boolean = false;
  @Prop updateCheckMessage: string = '';
  @Prop availableVersion: string = '';
  @Prop latestVersion: string = '';
  @Prop latestAssetUrl: string = '';
  @Prop latestAssetSha256: string = '';
  onCheckUpdate: () => void = (): void => {};
  onOpenDownload: (url: string) => void = (_url: string): void => {};
  onOpenProject: () => void = (): void => {};
  onOpenWhatsNew: () => void = (): void => {};
  onOpenUpdateWhatsNew: () => void = (): void => {};

  private sources(): AppUpdateDownloadSource[] {
    return updateDownloadSources(this.latestAssetUrl);
  }

  private copySource(url: string): void {
    void pasteboard.getSystemPasteboard().setData(
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url)).then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: '下载链接已复制' });
      }).catch((_error: Error): void => {
        this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
      });
  }

  /** 通知栏进度由系统下载服务以应用身份发布，需应用通知开关已开才会显示。 */
  private async ensureNotificationAuthorized(): Promise<void> {
    const abilityContext = getAbilityContext();
    if (abilityContext === undefined) {
      return;
    }
    try {
      if (await notificationManager.isNotificationEnabled()) {
        return;
      }
    } catch (_error) {
      // 查询失败不阻塞下载，继续尝试请求授权。
    }
    try {
      await notificationManager.requestEnableNotification(abilityContext);
    } catch (_error) {
      // 用户拒绝授权时仍继续下载，仅无通知栏进度。
    }
  }

  /** 选择器确认时会预创建空文件；下载取消/失败后需清掉，避免残留垃圾文件。 */
  private removeReservedFile(uri: string): void {
    if (uri.length === 0) {
      return;
    }
    void fileIo.unlink(uri).catch((_error: Error): void => {});
  }

  /** 系统自带的失败通知只有缓存文件名，原因经 onFail 只发给应用，故由应用补发带原因的通知。 */
  private publishDownloadFailedNotification(reason: string): void {
    const notifRequest: notificationManager.NotificationRequest = {
      id: DOWNLOAD_FAILED_NOTIFICATION_ID,
      content: {
        contentType: notification.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '安装包下载失败',
          text: `${downloadFailureHint(reason)}，请更换下载源后重试`
        }
      }
    };
    void notificationManager.publish(notifRequest).catch((_error: Error): void => {});
  }

  private async startSystemDownload(source: AppUpdateDownloadSource): Promise<void> {
    if (this.downloadBusy) {
      return;
    }
    const context = this.getUIContext().getHostContext();
    const assetName = this.latestAssetUrl.substring(this.latestAssetUrl.lastIndexOf('/') + 1);
    if (context === undefined || assetName.length === 0) {
      this.downloadStatus = '无法获取下载所需的应用信息';
      return;
    }
    this.downloadBusy = true;
    this.downloadStatus = '请先选择安装包的保存位置';
    let targetUri = '';
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [assetName];
      const destinations = await new picker.DocumentViewPicker(context).save(options);
      if (destinations.length === 0) {
        this.downloadStatus = '已取消保存位置选择，未开始下载';
        this.downloadBusy = false;
        return;
      }
      targetUri = destinations[0];
    } catch (error) {
      const detail = error instanceof Error ? error.message : '请重试';
      this.downloadStatus = `无法选择保存位置：${detail}`;
      this.downloadBusy = false;
      return;
    }
    await this.ensureNotificationAuthorized();
    this.downloadStatus = `正在通过${source.label}下载安装包…`;
    this.getUIContext().getPromptAction().showToast({ message: '系统下载已开始，可在通知栏查看进度' });
    const cachePath = `${context.cacheDir}/update-${Date.now()}-${assetName}`;
    let task: request.agent.Task | undefined = undefined;
    try {
      const config: request.agent.Config = {
        action: request.agent.Action.DOWNLOAD,
        url: source.url,
        title: assetName,
        description: `知乎++鸿蒙版 ${source.label}`,
        saveas: cachePath,
        mode: request.agent.Mode.BACKGROUND,
        overwrite: true,
        gauge: true,
        redirect: true,
        notification: {
          title: '正在下载安装包',
          text: `知乎++鸿蒙版 ${source.label}`,
          visibility: request.agent.VISIBILITY_PROGRESS
        }
      };
      task = await request.agent.create(context, config);
      const activeTask = task;
      task.on('progress', (progress: request.agent.Progress): void => {
        const total = progress.sizes.length > 0 ? progress.sizes[0] : -1;
        this.downloadStatus = total > 0
          ? `正在下载 ${Math.floor(progress.processed * 100 / total)}%`
          : '正在下载到所选保存位置…';
      });
      task.on('completed', (_progress: request.agent.Progress): void => {
        void this.verifyAndSaveDownload(cachePath, targetUri, assetName);
      });
      task.on('failed', (_progress: request.agent.Progress): void => {
        this.downloadBusy = false;
        void fileIo.unlink(cachePath).catch((_error: Error): void => {});
        this.removeReservedFile(targetUri);
        void request.agent.show(activeTask.tid).then((info: request.agent.TaskInfo): void => {
          this.downloadStatus = `系统下载失败：${downloadFailureHint(info.reason)}`;
          this.publishDownloadFailedNotification(info.reason);
        }).catch((_error: Error): void => {
          this.downloadStatus = '系统下载失败，请更换下载源后重试';
          this.publishDownloadFailedNotification('');
        });
      });
      task.on('remove', (_progress: request.agent.Progress): void => {
        this.downloadBusy = false;
        void fileIo.unlink(cachePath).catch((_error: Error): void => {});
        this.removeReservedFile(targetUri);
        this.downloadStatus = '系统下载已取消';
      });
      this.downloadStatus = '系统下载任务已创建，正在启动…';
      await task.start();
    } catch (error) {
      this.downloadBusy = false;
      void fileIo.unlink(cachePath).catch((_error: Error): void => {});
      this.removeReservedFile(targetUri);
      const detail = error instanceof Error ? error.message : '请重试';
      this.downloadStatus = `系统下载未开始：${detail}`;
    }
  }

  /** 下载完成后先校验 SHA-256（清单带摘要时），不一致拒绝保存并清理；通过后才写入所选位置。 */
  private async verifyAndSaveDownload(cachePath: string, targetUri: string, assetName: string): Promise<void> {
    const expected = this.latestAssetSha256;
    let hashVerified = false;
    if (expected.length > 0) {
      this.downloadStatus = '正在校验安装包 SHA-256…';
      const actual = await sha256HexOfFile(cachePath).catch((_error: Error): string => {
        hilog.error(0x0000, 'AppUpdate', 'sha256 compute failed: %{public}s', _error.message);
        return '';
      });
      hilog.info(0x0000, 'AppUpdate', 'verify expectedLen=%{public}d actualPrefix=%{public}s',
        expected.length, actual.length > 0 ? actual.substring(0, 12) : '(empty)');
      if (actual.length > 0 && actual !== expected) {
        this.downloadBusy = false;
        void fileIo.unlink(cachePath).catch((_error: Error): void => {});
        this.removeReservedFile(targetUri);
        this.downloadStatus = '安装包 SHA-256 校验不一致，已拒绝保存，请更换下载源重试';
        return;
      }
      hashVerified = actual.length > 0;
    }
    await this.saveToPickedLocation(cachePath, targetUri, assetName, hashVerified);
  }

  private async saveToPickedLocation(cachePath: string, targetUri: string, assetName: string,
    hashVerified: boolean): Promise<void> {
    let destination: fileIo.File | undefined = undefined;
    try {
      const sourceInfo = await fileIo.stat(cachePath);
      if (sourceInfo.size <= 0) {
        throw new Error('下载文件为空');
      }
      destination = await fileIo.open(targetUri, fileIo.OpenMode.READ_WRITE);
      await fileIo.copyFile(cachePath, destination.fd);
      const savedInfo = await fileIo.stat(destination.fd);
      if (savedInfo.size !== sourceInfo.size) {
        throw new Error('保存文件大小不一致');
      }
      const suffix = hashVerified ? '，SHA-256 校验一致' : '';
      this.downloadStatus = `已保存 ${assetName} 到所选公共目录（${savedInfo.size} 字节${suffix}）`;
      this.getUIContext().getPromptAction().showToast({ message: '已保存到所选位置' });
    } catch (error) {
      this.removeReservedFile(targetUri);
      const detail = error instanceof Error ? error.message : '请重试';
      this.downloadStatus = `保存到所选位置失败：${detail}`;
    } finally {
      if (destination !== undefined) {
        await fileIo.close(destination).catch((_error: Error): void => {});
      }
      await fileIo.unlink(cachePath).catch((_error: Error): void => {});
      this.downloadBusy = false;
    }
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text('知乎++鸿蒙版').fontSize(20).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text(`已安装 ${this.installedVersionLabel}`).id('system_installed_version')
                .fontSize($r('app.float.secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.updateCheckBusy) {
              LoadingProgress().width(24).height(24).color(this.resolvedThemeColor)
            }
          }.width('100%').alignItems(VerticalAlign.Center)
          if (this.latestVersion.length > 0) {
            Text(`最新发布 v${this.latestVersion}`).fontSize($r('app.float.body_font_size'))
              .fontColor(this.resolvedThemeColor).width('100%')
          }
          Button(this.updateCheckBusy ? '正在检查…' : '检查更新')
            .id('system_check_update').width('100%').enabled(!this.updateCheckBusy)
            .fontColor(onThemeColor(this.resolvedThemeColor))
            .backgroundColor(this.resolvedThemeColor)
            .onClick((): void => this.onCheckUpdate())
          if (this.updateCheckMessage.length > 0) {
            Text(this.updateCheckMessage).id('system_update_status')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text')).width('100%')
          }
        }.width('100%').padding(18).borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.surface_background'))

        if (this.availableVersion.length > 0) {
          Text('更新日志').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text')).width('100%')
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row() {
              Text(`查看 v${this.availableVersion} 更新内容`).fontSize($r('app.float.body_font_size'))
                .fontColor($r('app.color.primary_text')).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.doc_text')).fontSize(18)
                .fontColor([$r('app.color.secondary_text')])
            }.width('100%')
          }.id('system_update_whats_new').width('100%').padding(16)
            .backgroundColor($r('app.color.surface_background'))
            .onClick((): void => this.onOpenUpdateWhatsNew())
        }

        if (this.sources().length > 0) {
          Text(`未签名安装包 · v${this.latestVersion}`).fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.secondary_text')).width('100%')
          Column({ space: 12 }) {
            Text('选择下载源').fontSize($r('app.float.body_font_size'))
              .fontWeight(FontWeight.Medium).fontColor($r('app.color.primary_text')).width('100%')
            Text('17 个代理源与 GitHub 官方源。下载后需自行签名安装。')
              .fontSize($r('app.float.secondary_font_size'))
              .fontColor($r('app.color.secondary_text')).width('100%')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.sources(), (source: AppUpdateDownloadSource, index: number) => {
                Button({ type: ButtonType.Normal, stateEffect: true }) {
                  Column({ space: 3 }) {
                    Text(source.label).fontSize(14).fontColor($r('app.color.primary_text'))
                    Text(source.official ? '官方' : (source.resumable ? '支持续传' : '普通代理'))
                      .fontSize(11).fontColor($r('app.color.secondary_text'))
                  }.width('100%')
                }.id(`system_source_${index + 1}`).width('48%').height(56).margin({ bottom: 8 })
                  .backgroundColor($r('app.color.page_background'))
                  .onClick((): void => { this.selectedSource = source; })
              }, (source: AppUpdateDownloadSource): string => source.url)
            }.width('100%')
          }.width('100%').padding(16).borderRadius($r('app.float.card_radius'))
            .backgroundColor($r('app.color.surface_background'))
        } else if (this.latestVersion.length > 0) {
          Text('此版本暂无可用的未签名 HAP 附件，请在 GitHub 发布页查看。')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text')).width('100%')
        }

        if (this.downloadStatus.length > 0) {
          Text(this.downloadStatus).id('system_download_status')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text')).width('100%')
        }

        Text('已安装版本').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.secondary_text')).width('100%')
        Button({ type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true }) {
          Row() {
            Text('本版本更新内容').fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text')).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.doc_text')).fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }.width('100%')
        }.id('system_open_whats_new').width('100%').padding(16)
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.surface_background'))
          .onClick((): void => this.onOpenWhatsNew())

        Text('支持与诊断').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.secondary_text')).width('100%')
        Button({ type: ButtonType.ROUNDED_RECTANGLE, stateEffect: true }) {
          Row() {
            Text('GitHub 项目与问题反馈').fontSize($r('app.float.body_font_size'))
              .fontColor($r('app.color.primary_text')).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18)
              .fontColor([$r('app.color.secondary_text')])
          }.width('100%')
        }.id('system_open_project').width('100%').padding(16)
          .borderRadius($r('app.float.card_radius'))
          .backgroundColor($r('app.color.surface_background'))
          .onClick((): void => this.onOpenProject())
      }
      .width('100%')
      .padding({ left: $r('app.float.page_padding'), right: $r('app.float.page_padding'),
        top: 81, bottom: 40 })
    }
    .id('system_update_scroll').width('100%').height('100%').scrollBar(BarState.Off)
    .backgroundColor($r('app.color.page_background'))
    .bindPopup(this.selectedSource !== undefined, {
      builder: () => { this.sourcePopup() },
      placement: Placement.Bottom,
      onStateChange: (event: PopupStateChange) => {
        if (!event.isVisible) { this.selectedSource = undefined; }
      }
    })
  }

  @Builder
  private sourcePopup() {
    Column({ space: 10 }) {
      Text(this.selectedSource?.label ?? '').fontSize(18).fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text')).width('100%')
      Text(this.selectedSource?.url ?? '').fontSize(12).maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        .fontColor($r('app.color.secondary_text')).width('100%')
      Text('安装包为未签名 HAP，下载后需自行签名。')
        .fontSize(12).fontColor($r('app.color.secondary_text')).width('100%')
      Button('系统下载').id('system_source_system_download').width('100%')
        .enabled(!this.downloadBusy)
        .fontColor(onThemeColor(this.resolvedThemeColor)).backgroundColor(this.resolvedThemeColor)
        .onClick((): void => {
          const source = this.selectedSource;
          if (source !== undefined) { void this.startSystemDownload(source); }
          this.selectedSource = undefined;
        })
      Button('在浏览器下载').id('system_source_open').width('100%')
        .fontColor($r('app.color.primary_text')).backgroundColor($r('app.color.page_background'))
        .onClick((): void => {
          const source = this.selectedSource;
          if (source !== undefined) { this.onOpenDownload(source.url); }
          this.selectedSource = undefined;
        })
      Button('复制链接').id('system_source_copy').width('100%')
        .backgroundColor($r('app.color.page_background')).fontColor($r('app.color.primary_text'))
        .onClick((): void => {
          const source = this.selectedSource;
          if (source !== undefined) { this.copySource(source.url); }
          this.selectedSource = undefined;
        })
    }.width('100%').padding(20).borderRadius($r('app.float.card_radius'))
      .backgroundColor($r('app.color.surface_background'))
  }
}
