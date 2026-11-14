import { DEFAULT_THEME_COLOR, PeopleContentSection, themeColorContainerColor } from 'data';
import { TopBarGlassPill } from './components/TopBarContent';
import { peopleTitleText, PeopleTitleState } from './PeopleTitleBar';
import { PeopleTabsLayout, PeopleTabsState, peopleTabsInTitleBar, requestPeopleSection,
  resolvePeopleTabsLayout } from './PeopleContentTabsState';

/** 三处复用同一控件与选中状态：资料下方、窄窗悬浮、宽窗顶栏中央。 */
@Component
export struct PeopleContentTabs {
  personId: string = '';
  @Prop presentation: string = 'inline';
  @Prop viewportWidthVp: number = 0;
  @StorageProp('peopleContentTabsStates') private states: PeopleTabsState[] = [];
  @StorageProp('resolvedThemeColor') private resolvedThemeColor: string = DEFAULT_THEME_COLOR;
  @StorageProp('systemFontSizeScale') private fontScale: number = 1;

  private layout(): PeopleTabsLayout {
    return resolvePeopleTabsLayout(this.viewportWidthVp, this.fontScale);
  }

  private selected(section: PeopleContentSection): boolean {
    return (this.states.find((state: PeopleTabsState): boolean => state.id === this.personId)?.selected
      ?? PeopleContentSection.ANSWERS) === section;
  }

  @Builder
  private tab(label: string, section: PeopleContentSection) {
    Button(label, { type: ButtonType.Capsule, stateEffect: true })
      .width(this.layout().buttonWidth)
      .height(this.layout().buttonHeight)
      .padding({ left: 12, right: 12 })
      .id(`people_content_tab_${section}`)
      .fontSize($r('app.float.body_font_size'))
      .fontWeight(this.selected(section) ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.selected(section) ? this.resolvedThemeColor : $r('app.color.primary_text'))
      .backgroundColor(this.selected(section) ? themeColorContainerColor(this.resolvedThemeColor) : Color.Transparent)
      .responseRegion({ x: 0, y: -4, width: '100%', height: this.layout().height })
      .accessibilitySelected(this.selected(section))
      .onClick((): void => requestPeopleSection(this.personId, section))
  }

  @Builder
  private tabs() {
    Scroll() {
      Row() {
        this.tab('回答', PeopleContentSection.ANSWERS)
        this.tab('文章', PeopleContentSection.ARTICLES)
        this.tab('动态', PeopleContentSection.ACTIVITIES)
      }
      .height(this.layout().buttonHeight)
    }
    .id('people_content_tabs')
    .width('100%')
    .height(this.layout().buttonHeight)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  build() {
    if (this.presentation === 'floating') {
      Row() {
        TopBarGlassPill({
          content: (): void => this.tabs(),
          widthVp: this.layout().width,
          heightVp: this.layout().height,
          interactive: false,
          contentPadding: { left: 4, right: 4, top: 4, bottom: 4 },
          elementId: 'people_content_floating_capsule',
          label: '个人主页内容栏目'
        })
      }
      .width(this.layout().width)
      .height(this.layout().height)
      .borderRadius(this.layout().height / 2)
      // 材质降级或模拟器无法采样时，也不能让下方正文与栏目文字叠在一起。
      .backgroundColor($r('app.color.immersive_title_background'))
    } else {
      Row() { this.tabs() }
        .width(this.layout().width)
        .height(this.layout().height)
        .padding(4)
        .borderRadius(this.layout().height / 2)
        // 顶栏已经提供渐变模糊，此处只画分段轮廓，不再叠一层采样材质。
        .backgroundColor(this.presentation === 'title' ? $r('app.color.surface_background') : Color.Transparent)
        .id(this.presentation === 'title' ? 'people_content_title_capsule' : 'people_content_inline_capsule')
    }
  }
}

/** 叠在 HDS 原生标题栏内；原生返回与更多菜单仍由 HDS 承载。 */
@Component
export struct PeopleTitleTabs {
  personId: string = '';
  @State private widthVp: number = 0;
  @StorageProp('peopleContentTabsStates') private states: PeopleTabsState[] = [];
  @StorageProp('peopleTitleStates') private titles: PeopleTitleState[] = [];
  @StorageProp('systemFontSizeScale') private fontScale: number = 1;

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (peopleTabsInTitleBar(this.states, this.personId)) {
        Text(peopleTitleText(this.titles, this.personId))
          .id('people_detail_page_title')
          .fontSize($r('app.float.heading_font_size'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
          .width(Math.max(0, (this.widthVp - resolvePeopleTabsLayout(this.widthVp, this.fontScale).width) / 2 - 96))
          .height(48)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 80 })
        Row() {
          PeopleContentTabs({ personId: this.personId, presentation: 'title', viewportWidthVp: this.widthVp })
        }
        .width('100%').height(48)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%').height(48)
    .hitTestBehavior(HitTestMode.Transparent)
    .onAreaChange((_oldArea: Area, area: Area): void => {
      const width = Number(area.width);
      if (width > 0 && Math.abs(width - this.widthVp) > 0.5) { this.widthVp = width; }
    })
  }
}
