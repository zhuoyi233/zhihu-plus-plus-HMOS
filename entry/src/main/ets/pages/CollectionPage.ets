import { P1Destination, P1DestinationName } from 'core';
import {
  CollectionRepository,
  CollectionSummary,
  LoginSessionGateway
} from 'data';
import {
  CollectionController,
  CollectionPhase,
  CollectionViewState
} from './CollectionState';

@Component
export struct CollectionPage {
  identifier: string = '';
  repository: CollectionRepository | undefined = undefined;
  session: LoginSessionGateway | undefined = undefined;
  navigate: (destination: P1Destination) => void = (_destination: P1Destination): void => {
  };
  onBack: () => void = (): void => {};
  @State private phase: CollectionPhase = CollectionPhase.IDLE;
  @State private items: Array<CollectionSummary> = [];
  @State private loadingMore: boolean = false;
  @State private canLoadMore: boolean = false;
  @State private requiresLogin: boolean = false;
  @State private busy: boolean = false;
  @State private errorMessage: string = '';
  @State private showCreateDialog: boolean = false;
  @State private createTitle: string = '';
  @State private createDescription: string = '';
  @State private createIsPublic: boolean = false;
  @State private actionTarget?: CollectionSummary = undefined;
  @State private showActionSheet: boolean = false;
  @State private pendingDelete?: CollectionSummary = undefined;
  @State private showDeleteSheet: boolean = false;
  private controller?: CollectionController;

  aboutToAppear(): void {
    // P3-7：返回栈重显（页面实例与状态保留）时 aboutToAppear 可能再次触发；
    // 控制器仍存活时直接复用，避免 loadInitial 清空列表并重载导致滚动位置丢失。
    if (this.controller !== undefined) {
      this.controller.activate();
      return;
    }
    const repository = this.repository;
    const session = this.session;
    if (repository === undefined || session === undefined) {
      this.phase = CollectionPhase.ERROR;
      this.errorMessage = '收藏夹数据源未配置';
      return;
    }
    this.controller = new CollectionController(
      this.identifier,
      repository,
      session,
      (state: CollectionViewState): void => this.applyState(state)
    );
    this.controller.activate();
    this.controller.loadInitial();
  }

  aboutToDisappear(): void {
    this.controller?.deactivate();
    this.controller = undefined;
    this.actionTarget = undefined;
    this.showActionSheet = false;
    this.pendingDelete = undefined;
    this.showDeleteSheet = false;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: $r('app.float.p1_spacing_medium') }) {
        if (this.phase === CollectionPhase.IDLE || this.phase === CollectionPhase.LOADING) {
          this.statusPanel('正在加载收藏夹…', false, 'p3_collections_loading')
        } else if (this.phase === CollectionPhase.ERROR) {
          this.statusPanel(this.errorMessage, true, 'p3_collections_error')
        } else if (this.phase === CollectionPhase.EMPTY) {
          this.statusPanel('还没有收藏夹，点击右下角新建', true, 'p3_collections_empty')
        } else {
          if (this.errorMessage.length > 0) {
            Row({ space: $r('app.float.p1_spacing_small') }) {
              Text(this.errorMessage)
                .fontSize($r('app.float.p1_secondary_font_size'))
                .fontColor($r('app.color.secondary_text'))
                .layoutWeight(1)
              if (this.requiresLogin) {
                Button('去登录')
                  .id('p3_collections_login')
                  .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
              } else {
                Button('重试')
                  .id('p3_collections_retry_more')
                  .onClick(() => this.controller?.retry())
              }
            }
            .width('100%')
            .padding($r('app.float.p1_spacing_small'))
            .borderRadius($r('app.float.p1_card_radius'))
            .backgroundColor($r('app.color.surface_background'))
          }

          List({ space: 10 }) {
            ForEach(this.items, (collection: CollectionSummary) => {
              ListItem() {
                this.collectionCard(collection)
              }
            }, (collection: CollectionSummary): string => collection.id)

            if (this.loadingMore || this.canLoadMore) {
              ListItem() {
                Button(this.loadingMore ? '正在加载更多…' : '加载更多')
                  .id('p3_collections_load_more')
                  .width('100%')
                  .fontSize($r('app.float.p1_secondary_font_size'))
                  .enabled(!this.loadingMore && !this.busy)
                  .onClick(() => this.controller?.loadMore())
              }
            }
          }
          .id('p3_collections_list')
          .width('100%')
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => this.controller?.loadMore())
        }

      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .padding({
        left: $r('app.float.p1_page_padding'),
        right: $r('app.float.p1_page_padding'),
        top: 94,
        bottom: $r('app.float.p1_page_padding')
      })
      .backgroundColor($r('app.color.page_background'))

      if (this.phase === CollectionPhase.READY || this.phase === CollectionPhase.EMPTY) {
        Button(this.busy ? '处理中…' : '新建', { type: ButtonType.Capsule })
          .id('p3_collections_create_button')
          .width(96)
          .height(48)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor(Color.White)
          .backgroundColor($r('app.color.brand_primary'))
          .margin({
            right: $r('app.float.p1_page_padding'),
            bottom: $r('app.float.p1_page_padding')
          })
          .accessibilityText('新建收藏夹')
          .enabled(!this.busy)
          .onClick((): void => {
            this.openCreateDialog();
          })
      }

      Column()
        .bindSheet(this.showCreateDialog, this.createDialog(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.showCreateDialog) {
              this.showCreateDialog = false;
            }
          }
        })
      Column()
        .bindSheet(this.showActionSheet, this.collectionActionSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.showActionSheet) {
              this.showActionSheet = false;
            }
            this.actionTarget = undefined;
          }
        })
      Column()
        .bindSheet(this.showDeleteSheet, this.deleteConfirmation(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false,
          maskColor: '#66000000',
          backgroundColor: $r('app.color.surface_background'),
          onDisappear: (): void => {
            if (this.showDeleteSheet) {
              this.showDeleteSheet = false;
            }
            this.pendingDelete = undefined;
          }
        })
    }
    .id('p3_collections_page')
    .width('100%')
    .height('100%')
  }

  @Builder
  private collectionCard(collection: CollectionSummary) {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text(collection.title)
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Text(collection.isPublic ? '公开' : '私密')
          .fontSize($r('app.float.p1_caption_font_size'))
          .fontColor($r('app.color.secondary_text'))
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id(`p3_collections_actions_${collection.id}`)
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('收藏夹操作')
          .enabled(!this.busy)
          .onClick((): void => this.openActionSheet(collection))
      }
      .width('100%')

      if (collection.description.trim().length > 0) {
        Text(collection.description)
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.secondary_text'))
          .width('100%')
          .maxLines(3)
      }

      Text(`${collection.itemCount} 篇内容 · ${collection.followerCount} 人关注`)
        .fontSize($r('app.float.p1_caption_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .width('100%')

    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding($r('app.float.p1_card_padding'))
    .borderRadius($r('app.float.p1_card_radius'))
    .backgroundColor($r('app.color.card_background'))
    .enabled(!this.busy)
    .onClick((): void => this.openCollection(collection))
  }

  @Builder
  private collectionActionSheet() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text(this.actionTarget?.title ?? '收藏夹操作')
          .fontSize($r('app.float.p1_heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
          .maxLines(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('p3_collections_actions_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭收藏夹操作')
          .onClick((): void => this.closeActionSheet())
      }
      .width('100%')
      Button('打开')
        .id(`p3_collections_open_${this.actionTarget?.id ?? ''}`)
        .width('100%')
        .enabled(this.actionTarget !== undefined && !this.busy)
        .onClick((): void => {
          const target = this.actionTarget;
          this.closeActionSheet();
          if (target !== undefined) {
            this.openCollection(target);
          }
        })
      Button('删除收藏夹')
        .id(`p3_collections_delete_${this.actionTarget?.id ?? ''}`)
        .width('100%')
        .fontColor($r('app.color.error_text'))
        .backgroundColor(Color.Transparent)
        .enabled(this.actionTarget !== undefined && !this.busy)
        .onClick((): void => {
          const target = this.actionTarget;
          this.closeActionSheet();
          if (target !== undefined) {
            this.pendingDelete = target;
            this.showDeleteSheet = true;
          }
        })
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.surface_background'))
  }

  @Builder
  private statusPanel(message: string, retry: boolean, testId: string) {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      if (testId === 'p3_collections_loading') {
        LoadingProgress()
          .id('p3_collections_loading_progress')
          .width(40)
          .height(40)
          .color($r('app.color.brand_primary'))
      }
      Text(message)
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.secondary_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (retry) {
        if (this.requiresLogin) {
          Button('去登录')
            .id('p3_collections_status_login')
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick((): void => this.navigate({ name: P1DestinationName.LOGIN }))
        } else {
          Button('重新加载')
            .id(`${testId}_retry`)
            .fontSize($r('app.float.p1_body_font_size'))
            .onClick(() => this.controller?.retry())
        }
      }
    }
    .id(testId)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private createDialog() {
    Column({ space: $r('app.float.p1_spacing_medium') }) {
      Text('新建收藏夹')
        .fontSize($r('app.float.p1_heading_font_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      TextInput({ text: this.createTitle, placeholder: '收藏夹名称' })
        .id('p3_collections_create_title_input')
        .width('100%')
        .maxLength(50)
        .onChange((value: string): void => {
          this.createTitle = value;
        })
      TextInput({ text: this.createDescription, placeholder: '描述（可选）' })
        .id('p3_collections_create_description_input')
        .width('100%')
        .maxLength(200)
        .onChange((value: string): void => {
          this.createDescription = value;
        })
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Text('公开收藏夹')
          .fontSize($r('app.float.p1_body_font_size'))
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.createIsPublic })
          .id('p3_collections_create_public_toggle')
          .onChange((value: boolean): void => {
            this.createIsPublic = value;
          })
      }
      .width('100%')
      if (this.errorMessage.length > 0 && this.phase !== CollectionPhase.ERROR) {
        Text(this.errorMessage)
          .fontSize($r('app.float.p1_secondary_font_size'))
          .fontColor($r('app.color.error_text'))
          .width('100%')
      }
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick((): void => {
            this.closeCreateDialog();
          })
        Button(this.busy ? '创建中…' : '创建')
          .id('p3_collections_create_submit')
          .layoutWeight(1)
          .enabled(!this.busy && this.createTitle.trim().length > 0)
          .onClick((): void => {
            this.submitCreate();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  @Builder
  private deleteConfirmation() {
    Column({ space: $r('app.float.p1_spacing_small') }) {
      Text('删除收藏夹「' + (this.pendingDelete?.title ?? '') + '」？此操作无法撤销。')
        .fontSize($r('app.float.p1_body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .width('100%')
      Row({ space: $r('app.float.p1_spacing_small') }) {
        Button('取消')
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick((): void => {
            this.showDeleteSheet = false;
            this.pendingDelete = undefined;
          })
        Button('确认删除')
          .id('p3_collections_delete_confirm')
          .layoutWeight(1)
          .enabled(!this.busy)
          .onClick((): void => {
            const target = this.pendingDelete;
            this.showDeleteSheet = false;
            this.pendingDelete = undefined;
            if (target !== undefined) {
              this.controller?.deleteCollection(target.id);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding($r('app.float.p1_spacing_medium'))
    .backgroundColor($r('app.color.surface_background'))
    .borderRadius($r('app.float.p1_card_radius'))
  }

  private openCreateDialog(): void {
    this.createTitle = '';
    this.createDescription = '';
    this.createIsPublic = false;
    this.showCreateDialog = true;
  }

  private closeCreateDialog(): void {
    this.showCreateDialog = false;
  }

  private openCollection(collection: CollectionSummary): void {
    this.navigate({ name: P1DestinationName.COLLECTION, id: collection.id });
  }

  private openActionSheet(collection: CollectionSummary): void {
    this.actionTarget = collection;
    this.showActionSheet = true;
  }

  private closeActionSheet(): void {
    this.showActionSheet = false;
    this.actionTarget = undefined;
  }

  private submitCreate(): void {
    if (this.busy) {
      return;
    }
    this.controller?.createCollection(this.createTitle, this.createDescription, this.createIsPublic).then(
      (created: boolean): void => {
        if (created) {
          this.closeCreateDialog();
        }
      }
    );
  }

  private applyState(state: CollectionViewState): void {
    this.phase = state.phase;
    this.items = state.items;
    this.loadingMore = state.loadingMore;
    this.canLoadMore = state.canLoadMore;
    this.requiresLogin = state.requiresLogin;
    this.busy = state.busy;
    this.errorMessage = state.errorMessage ?? '';
  }
}
