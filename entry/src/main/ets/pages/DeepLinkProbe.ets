import {
  DeepLinkDestination,
  DeepLinkType,
  describeDeepLink,
  resolveZhihuLink
} from 'core';

interface DeepLinkProbeCase {
  name: string;
  input: string;
  expectedType: DeepLinkType;
  expectedValue: string;
}

const PROBE_CASES: Array<DeepLinkProbeCase> = [
  {
    name: '回答网页',
    input: 'https://www.zhihu.com/question/631983014/answer/3309625617',
    expectedType: DeepLinkType.ANSWER,
    expectedValue: '3309625617'
  },
  {
    name: '回答直达网页',
    input: 'https://www.zhihu.com/answer/2040633177593619876',
    expectedType: DeepLinkType.ANSWER,
    expectedValue: '2040633177593619876'
  },
  {
    name: '问题网页',
    input: 'https://www.zhihu.com/question/631983014',
    expectedType: DeepLinkType.QUESTION,
    expectedValue: '631983014'
  },
  {
    name: '专栏文章',
    input: 'https://zhuanlan.zhihu.com/p/1981671287999981270',
    expectedType: DeepLinkType.ARTICLE,
    expectedValue: '1981671287999981270'
  },
  {
    name: 'OIA 文章',
    input: 'https://www.zhihu.com/oia/articles/1981671287999981270',
    expectedType: DeepLinkType.ARTICLE,
    expectedValue: '1981671287999981270'
  },
  {
    name: '用户主页',
    input: 'https://www.zhihu.com/people/scanmenge',
    expectedType: DeepLinkType.PERSON,
    expectedValue: 'scanmenge'
  },
  {
    name: '视频网页',
    input: 'https://www.zhihu.com/video/123456789',
    expectedType: DeepLinkType.VIDEO,
    expectedValue: '123456789'
  },
  {
    name: '想法网页',
    input: 'https://www.zhihu.com/pin/2059710318939301395',
    expectedType: DeepLinkType.PIN,
    expectedValue: '2059710318939301395'
  },
  {
    name: '想法 AppView',
    input: 'https://www.zhihu.com/appview/pin/2059710318939301395',
    expectedType: DeepLinkType.PIN,
    expectedValue: '2059710318939301395'
  },
  {
    name: '回答 AppView',
    input: 'https://www.zhihu.com/appview/answer/2040633177593619876',
    expectedType: DeepLinkType.ANSWER,
    expectedValue: '2040633177593619876'
  },
  {
    name: '文章 AppView',
    input: 'https://www.zhihu.com/appview/p/1981671287999981270',
    expectedType: DeepLinkType.ARTICLE,
    expectedValue: '1981671287999981270'
  },
  {
    name: '搜索',
    input: 'https://www.zhihu.com/search?q=HarmonyOS%20ArkTS',
    expectedType: DeepLinkType.SEARCH,
    expectedValue: 'HarmonyOS ArkTS'
  },
  {
    name: '知乎跳转链接',
    input: 'https://link.zhihu.com/?target=https%3A%2F%2Fwww.zhihu.com%2Fquestion%2F48509984',
    expectedType: DeepLinkType.QUESTION,
    expectedValue: '48509984'
  },
  {
    name: 'zhihu 回答',
    input: 'zhihu://answers/2040633177593619876',
    expectedType: DeepLinkType.ANSWER,
    expectedValue: '2040633177593619876'
  },
  {
    name: 'zhihu 问题',
    input: 'zhihu://questions/631983014',
    expectedType: DeepLinkType.QUESTION,
    expectedValue: '631983014'
  },
  {
    name: 'zhihu 文章',
    input: 'zhihu://articles/1981671287999981270',
    expectedType: DeepLinkType.ARTICLE,
    expectedValue: '1981671287999981270'
  },
  {
    name: 'zhihu 想法',
    input: 'zhihu://pin/2059710318939301395',
    expectedType: DeepLinkType.PIN,
    expectedValue: '2059710318939301395'
  },
  {
    name: 'zhihu 搜索',
    input: 'zhihu://search?q=ArkTS',
    expectedType: DeepLinkType.SEARCH,
    expectedValue: 'ArkTS'
  },
  {
    name: 'zhihu 首页',
    input: 'zhihu://feed',
    expectedType: DeepLinkType.MAIN_TABS,
    expectedValue: ''
  }
];

@Component
export struct DeepLinkProbePage {
  onBack: () => void = () => {};
  @State private input: string = 'zhihu://answers/2040633177593619876';
  @State private status: string = '等待解析';
  @State private matrixStatus: string = '尚未运行映射矩阵';
  @State private results: Array<string> = [];

  aboutToAppear(): void {
    this.runMatrix();
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Button('返回')
          .id('p0_deep_link_back')
          .onClick(() => this.onBack())

        Text('知乎 URL 与深链解析')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))

        Text('纯 ArkTS 解析，不发起网络请求；内容 ID 保持字符串，避免 19 位 ID 精度丢失。')
          .fontSize(16)
          .lineHeight(26)
          .fontColor($r('app.color.secondary_text'))

        TextInput({ text: this.input, placeholder: '输入知乎 URL 或 zhihu:// 链接' })
          .id('p0_deep_link_input')
          .onChange((value: string) => {
            this.input = value;
          })

        Button('解析链接')
          .id('p0_run_deep_link_probe')
          .onClick(() => {
            const destination = resolveZhihuLink(this.input);
            this.status = destination === undefined ? '不支持或链接无效' : describeDeepLink(destination);
          })

        Text(this.status)
          .id('p0_deep_link_status')
          .fontSize(17)
          .fontColor($r('app.color.primary_text'))

        Text(this.matrixStatus)
          .id('p0_deep_link_matrix_status')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))

        ForEach(this.results, (result: string) => {
          Text(result)
            .fontSize(15)
            .lineHeight(24)
            .fontColor($r('app.color.secondary_text'))
            .width('100%')
        })
      }
      .width('100%')
      .padding(24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private runMatrix(): void {
    let passed = 0;
    const results: Array<string> = [];
    PROBE_CASES.forEach((probeCase: DeepLinkProbeCase) => {
      const destination: DeepLinkDestination | undefined = resolveZhihuLink(probeCase.input);
      const actualValue = destination?.type === DeepLinkType.SEARCH ? destination.query : destination?.id;
      const success = destination?.type === probeCase.expectedType && actualValue === probeCase.expectedValue;
      if (success) {
        passed += 1;
      }
      results.push(`${success ? '✓' : '✗'} ${probeCase.name}：` +
        `${destination === undefined ? '未解析' : describeDeepLink(destination)}`);
    });
    this.results = results;
    this.matrixStatus = passed === PROBE_CASES.length
      ? `通过：${passed}/${PROBE_CASES.length} 条映射正确`
      : `失败：${passed}/${PROBE_CASES.length} 条映射正确`;
  }
}
