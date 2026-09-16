import {
  getAppSessionOwner,
  IdentityManagementClient,
  SessionStatus,
  ZhihuIdentityAccount
} from 'data';
import { getAbilityContext } from '../entryability/AbilityContextHolder';

type IdentityConfirmationKind = 'switch' | 'create';

@Component
export struct IdentityManagementPage {
  @State private accounts: Array<ZhihuIdentityAccount> = [];
  @State private currentAccountId: string = '';
  @State private loading: boolean = true;
  @State private busy: boolean = false;
  @State private errorMessage: string = '';
  @State private confirmationShown: boolean = false;
  @State private confirmationKind: IdentityConfirmationKind = 'switch';
  @State private targetAccount: ZhihuIdentityAccount | undefined = undefined;
  @State private acceptedCreateRules: boolean = false;
  private client: IdentityManagementClient | undefined = undefined;

  aboutToAppear(): void {
    const context = getAbilityContext();
    if (context === undefined) {
      this.loading = false;
      this.errorMessage = '账号服务暂不可用';
      return;
    }
    this.client = new IdentityManagementClient(getAppSessionOwner(context).getRepository());
    void this.refresh();
  }

  aboutToDisappear(): void {
    this.client?.cancel();
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: $r('app.float.p1_spacing_large') }) {
          if (this.loading && this.accounts.length === 0) {
            Column({ space: $r('app.float.p1_spacing_medium') }) {
              LoadingProgress().width(40).height(40).color($r('app.color.brand_primary'))
              Text('正在加载身份列表…').fontColor($r('app.color.secondary_text'))
            }.width('100%').height(180).justifyContent(FlexAlign.Center)
          }

          if (this.errorMessage.length > 0) {
            Column({ space: $r('app.float.p1_spacing_medium') }) {
              Text('加载失败').fontSize($r('app.float.p1_heading_font_size'))
                .fontColor($r('app.color.primary_text')).width('100%')
              Text(this.errorMessage).fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text')).width('100%')
              Button('重试').id('p5_identity_retry').enabled(!this.busy)
                .onClick((): void => { void this.refresh(); })
            }.width('100%').padding($r('app.float.p1_card_padding'))
              .borderRadius($r('app.float.p1_card_radius')).backgroundColor($r('app.color.surface_background'))
          }

          if (this.accounts.length > 0) {
            Text('当前手机号下的账号').fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text')).width('100%')
            Column() {
              ForEach(this.accounts, (account: ZhihuIdentityAccount, index: number): void => {
                if (index > 0) {
                  Divider().color($r('app.color.divider_color'))
                }
                this.accountRow(account, index)
              }, (account: ZhihuIdentityAccount): string => account.id)
            }.width('100%').borderRadius($r('app.float.p1_card_radius'))
              .backgroundColor($r('app.color.surface_background'))

            Text('新账号').fontSize($r('app.float.p1_secondary_font_size'))
              .fontColor($r('app.color.secondary_text')).width('100%')
            Column({ space: $r('app.float.p1_spacing_small') }) {
              Button('创建新账号')
                .id('p5_identity_create')
                .width('100%')
                .enabled(this.canCreateSubAccount() && !this.busy)
                .onClick((): void => {
                  this.confirmationKind = 'create';
                  this.acceptedCreateRules = false;
                  this.confirmationShown = true;
                })
              Text(this.createHint()).fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text')).width('100%')
            }.width('100%').padding($r('app.float.p1_card_padding'))
              .borderRadius($r('app.float.p1_card_radius')).backgroundColor($r('app.color.surface_background'))
          }
        }
        .width('100%')
        .padding({ left: $r('app.float.p1_page_padding'), right: $r('app.float.p1_page_padding'),
          top: 16, bottom: 40 })
      }
      .id('p5_identity_scroll')
      .width('100%').height('100%').scrollBar(BarState.Off)
      .backgroundColor($r('app.color.page_background'))

      if (this.busy) {
        Column({ space: $r('app.float.p1_spacing_medium') }) {
          LoadingProgress().width(44).height(44).color($r('app.color.brand_primary'))
          Text(this.confirmationKind === 'create' ? '正在创建并切换账号…' : '正在切换账号…')
            .fontColor($r('app.color.primary_text'))
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .backgroundColor('#99000000').zIndex(2)
      }

      Column()
        .bindSheet(this.confirmationShown, this.confirmationSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.confirmationShown) {
              this.confirmationShown = false;
            }
          }
        })
    }.width('100%').height('100%')
  }

  @Builder
  private accountRow(account: ZhihuIdentityAccount, index: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: $r('app.float.p1_spacing_medium') }) {
        Stack({ alignContent: Alignment.Center }) {
          Text(account.name.length > 0 ? account.name.charAt(0) : '?')
            .width(42).height(42).borderRadius(21).textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.brand_primary_container')).fontColor($r('app.color.brand_primary'))
          if (account.avatarUrl.length > 0) {
            Image(account.avatarUrl).width(42).height(42).borderRadius(21).objectFit(ImageFit.Cover)
          }
        }
        Column({ space: 2 }) {
          Text(account.name).fontSize($r('app.float.p1_body_font_size'))
            .fontColor($r('app.color.primary_text')).maxLines(1)
          Text(account.accountType === 1 ? '主账号' : (account.accountType === 2 ? '马甲号' : '知乎账号'))
            .fontSize($r('app.float.p1_secondary_font_size')).fontColor($r('app.color.secondary_text'))
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(account.id === this.currentAccountId ? '当前登录' : '切换')
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor(account.id === this.currentAccountId ? $r('app.color.brand_primary') : $r('app.color.secondary_text'))
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .id(`p5_identity_account_${index}`)
    .width('100%').padding($r('app.float.p1_card_padding')).backgroundColor(Color.Transparent)
    .enabled(!this.busy && account.id !== this.currentAccountId)
    .onClick((): void => {
      this.targetAccount = account;
      this.confirmationKind = 'switch';
      this.confirmationShown = true;
    })
  }

  @Builder
  private confirmationSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text(this.confirmationKind === 'create' ? '新账号使用规则' : '切换账号')
        .fontSize($r('app.float.p1_heading_font_size')).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.primary_text')).width('100%')
      if (this.confirmationKind === 'create') {
        Text('新账号与当前账号共用同一手机号，但昵称、内容、数据和互动行为相互独立。创建机会有限，创建后将立即切换。')
          .fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
        Row({ space: $r('app.float.p1_spacing_small') }) {
          Checkbox({ name: 'identity-create-rules', group: 'identity-create' })
            .select(this.acceptedCreateRules).onChange((checked: boolean): void => {
              this.acceptedCreateRules = checked;
            })
          Text('我已知悉并同意上述规则').fontSize($r('app.float.p1_body_font_size'))
        }.width('100%').alignItems(VerticalAlign.Center)
      } else {
        Text(`将切换到“${this.targetAccount?.name ?? ''}”。之后的推荐、内容和互动行为都属于该账号。`)
          .fontSize($r('app.float.p1_body_font_size')).fontColor($r('app.color.primary_text')).width('100%')
      }
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消').layoutWeight(1).onClick((): void => { this.confirmationShown = false; })
        Button(this.confirmationKind === 'create' ? '同意并创建' : '切换')
          .id(this.confirmationKind === 'create' ? 'p5_identity_create_confirm' : 'p5_identity_switch_confirm')
          .layoutWeight(1).enabled(this.confirmationKind !== 'create' || this.acceptedCreateRules)
          .onClick((): void => {
            this.confirmationShown = false;
            if (this.confirmationKind === 'create') {
              void this.createSubAccount();
            } else {
              void this.switchAccount();
            }
          })
      }.width('100%')
    }.width('100%').padding($r('app.float.p1_page_padding'))
  }

  private async refresh(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      const state = await client.listAccounts();
      this.accounts = state.accounts;
      this.currentAccountId = state.currentAccountId;
      if (state.accounts.length === 0) {
        this.errorMessage = '未找到可管理的账号，请确认当前登录状态';
      }
    } catch (_error) {
      this.errorMessage = '获取身份列表失败，请稍后重试';
    } finally {
      this.loading = false;
    }
  }

  private async switchAccount(): Promise<void> {
    const target = this.targetAccount;
    const client = this.client;
    if (target === undefined || client === undefined || this.busy) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const state = await client.switchAccount(target.id);
      if (state.status !== SessionStatus.AUTHENTICATED) {
        throw new Error(state.message);
      }
      this.afterIdentityChanged();
      await this.refreshAfterBusy();
    } catch (_error) {
      this.errorMessage = '切换账号失败，当前登录未改变';
    } finally {
      this.busy = false;
      this.targetAccount = undefined;
    }
  }

  private async createSubAccount(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.busy || !this.canCreateSubAccount()) {
      return;
    }
    this.busy = true;
    this.errorMessage = '';
    try {
      const state = await client.createSubAccount();
      if (state.status !== SessionStatus.AUTHENTICATED) {
        throw new Error(state.message);
      }
      this.afterIdentityChanged();
      await this.refreshAfterBusy();
    } catch (_error) {
      this.errorMessage = '创建新账号失败，当前登录未改变';
    } finally {
      this.busy = false;
    }
  }

  private async refreshAfterBusy(): Promise<void> {
    this.busy = false;
    await this.refresh();
    this.busy = true;
  }

  private afterIdentityChanged(): void {
    AppStorage.setOrCreate('sessionStateTick', (AppStorage.get<number>('sessionStateTick') ?? 0) + 1);
    AppStorage.setOrCreate('loginFeedReloadTick', (AppStorage.get<number>('loginFeedReloadTick') ?? 0) + 1);
  }

  private canCreateSubAccount(): boolean {
    return this.accounts.length < 2 && this.accounts.some((account: ZhihuIdentityAccount): boolean =>
      account.canCreateSubAccount && account.subAccountControlStatus === 0);
  }

  private createHint(): string {
    if (this.accounts.length >= 2) {
      return '当前手机号下已经存在主账号和马甲号。';
    }
    return this.canCreateSubAccount() ? '新账号将使用系统昵称完成初始化；昵称修改受知乎次数限制。' :
      '当前登录账号暂不满足创建新账号的条件。';
  }
}
