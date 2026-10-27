import {
  DEFAULT_THEME_COLOR,
  matchPhoneLoginRegions,
  PHONE_LOGIN_REGIONS,
  PhoneLoginRegion,
  regionDialText
} from 'data';

/**
 * 国家/地区选择弹层（bindSheet + Search + List）。
 *
 * 设计约束（见 docs/phone-login-country-code-plan.md）：
 * - 空查询按知乎官网原顺序展示，长列表限定可用高度，不使用 FIT_CONTENT 展开全部条目；
 * - 搜索匹配中文名称、别名、地区标识与去掉可选 “+” 的区号，无结果给出明确空态；
 * - 点选即生效并关闭，取消/返回不改变原选择；再次打开定位当前项，搜索内容每次打开清空；
 * - 辅助功能标签读出完整地区、区号与当前选中状态。
 */
@Component
export struct PhoneCountryCodeSheet {
  @Prop selectedRegionId: string = '';
  onSelect: (region: PhoneLoginRegion) => void = (): void => {
  };
  onClose: () => void = (): void => {
  };
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @State private query: string = '';
  @State private regions: Array<PhoneLoginRegion> = PHONE_LOGIN_REGIONS;
  private scroller: Scroller = new Scroller();
  private scrollTimerId: number = -1;

  aboutToAppear(): void {
    this.query = '';
    this.regions = PHONE_LOGIN_REGIONS;
    const index: number = this.selectedIndex();
    if (index > 0) {
      // 等弹层完成首帧布局后再定位，避免 Scroller 尚未绑定列表。
      this.scrollTimerId = setTimeout((): void => {
        this.scrollTimerId = -1;
        if (index < this.regions.length) {
          this.scroller.scrollToIndex(index, false, ScrollAlign.START);
        }
      }, 60);
    }
  }

  aboutToDisappear(): void {
    if (this.scrollTimerId !== -1) {
      clearTimeout(this.scrollTimerId);
      this.scrollTimerId = -1;
    }
  }

  build() {
    Column({ space: $r('app.float.spacing_small') }) {
      Row({ space: $r('app.float.spacing_small') }) {
        Text('选择国家/地区')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .layoutWeight(1)
        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(20)
            .fontColor([$r('app.color.primary_text')])
        }
          .id('phone_region_close')
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭选择国家/地区')
          .onClick((): void => {
            this.onClose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Search({ value: this.query, placeholder: '搜索国家/地区或区号' })
        .id('phone_region_search')
        .width('100%')
        .height(40)
        .backgroundColor($r('app.color.control_background'))
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.secondary_text'))
        .onChange((value: string): void => {
          this.query = value;
          this.regions = matchPhoneLoginRegions(value);
        })

      if (this.regions.length === 0) {
        Column({ space: $r('app.float.spacing_small') }) {
          Text('没有匹配的国家/地区')
            .id('phone_region_empty')
            .fontSize($r('app.float.body_font_size'))
            .fontColor($r('app.color.primary_text'))
          Text('可以输入地区名称、英文别名或区号，例如 “日本”“Japan”“81”。')
            .fontSize($r('app.float.secondary_font_size'))
            .fontColor($r('app.color.secondary_text'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 4, right: 4, top: 8, bottom: 8 })
      } else {
        List({ space: 0, scroller: this.scroller }) {
          ForEach(this.regions, (region: PhoneLoginRegion) => {
            ListItem() {
              this.regionRow(region)
            }
          }, (region: PhoneLoginRegion): string => region.id)
        }
        .id('phone_region_list')
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
    }
    .id('phone_region_sheet')
    .width('100%')
    .height('100%')
    .padding($r('app.float.page_padding'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private regionRow(region: PhoneLoginRegion) {
    Row({ space: $r('app.float.spacing_small') }) {
      Text(region.displayName)
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.primary_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text(regionDialText(region))
        .fontSize($r('app.float.body_font_size'))
        .fontColor($r('app.color.secondary_text'))
      if (region.id === this.selectedRegionId) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontColor([this.resolvedThemeColor])
      }
    }
    .id(`phone_region_option_${region.id}`)
    .width('100%')
    .constraintSize({ minHeight: 48 })
    .padding({ left: 8, right: 8 })
    .borderRadius($r('app.float.card_radius'))
    .backgroundColor(region.id === this.selectedRegionId
      ? $r('app.color.control_background') : Color.Transparent)
    .accessibilityText(`${region.displayName} ${regionDialText(region)}` +
      (region.id === this.selectedRegionId ? '，当前已选中' : ''))
    .onClick((): void => {
      this.onSelect(region);
      this.onClose();
    })
  }

  private selectedIndex(): number {
    const index: number = this.regions.findIndex((region: PhoneLoginRegion): boolean =>
      region.id === this.selectedRegionId);
    return index < 0 ? 0 : index;
  }
}
