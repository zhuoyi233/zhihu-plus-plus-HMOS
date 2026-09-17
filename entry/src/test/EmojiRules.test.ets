import { describe, expect, it } from '@ohos/hypium';
import { util } from '@kit.ArkTS';
import {
  decodeStickerDataUrl,
  emojiFileName,
  EmojiSegment,
  EmojiSticker,
  isValidEmojiPlaceholder,
  parseEmojiSegments,
  parseStickerResponse
} from 'data';

function resolveKnown(placeholder: string): string {
  if (placeholder === '[惊喜]' || placeholder === '[赞同]') {
    return `/files/emojis/${emojiFileName('1')}`;
  }
  return '';
}

function kinds(segments: Array<EmojiSegment>): string {
  return segments.map((segment: EmojiSegment): string => segment.kind).join(',');
}

/**
 * host 侧 UnitTestArkTS 运行时里 @kit.ArkTS 的 Base64Helper 是空桩（返回空结果），
 * 与 PhoneLoginCrypto.test 相同的探测模式：桩环境下跳过真实解码断言。
 */
function hostBase64Capable(): boolean {
  try {
    return new util.Base64Helper().encodeToStringSync(new Uint8Array([1, 2, 3])) === 'AQID';
  } catch (_error) {
    return false;
  }
}

export default function emojiRulesTest(): void {
  describe('emojiRulesTest', () => {
    it('parsesStickerGroupResponse', 0, () => {
      const body = '{"data":{"title":"小表情","stickers":[' +
        '{"id":"111","placeholder":"[惊喜]","static_image_url":"data:image/png;base64,AAAA"},' +
        '{"id":"222","placeholder":"[赞同]","static_image_url":"data:image/png;base64,BBBB"},' +
        '{"id":"333","placeholder":"缺图","static_image_url":""},' +
        '{"id":"","placeholder":"[空id]","static_image_url":"data:image/png;base64,CCCC"},' +
        '{"id":"444","placeholder":"不是占位符","static_image_url":"data:image/png;base64,DDDD"}' +
        ']}}';
      const stickers: Array<EmojiSticker> = parseStickerResponse(body);
      expect(stickers.length).assertEqual(2);
      expect(stickers[0].id).assertEqual('111');
      expect(stickers[0].placeholder).assertEqual('[惊喜]');
      expect(stickers[1].placeholder).assertEqual('[赞同]');
    });

    it('rejectsMalformedStickerResponse', 0, () => {
      expect(parseStickerResponse('not json').length).assertEqual(0);
      expect(parseStickerResponse('{}').length).assertEqual(0);
      expect(parseStickerResponse('{"data":{}}').length).assertEqual(0);
    });

    it('validatesEmojiPlaceholder', 0, () => {
      expect(isValidEmojiPlaceholder('[惊喜]')).assertTrue();
      expect(isValidEmojiPlaceholder('[知乎益蜂]')).assertTrue();
      expect(isValidEmojiPlaceholder('惊喜')).assertFalse();
      expect(isValidEmojiPlaceholder('[]')).assertFalse();
      expect(isValidEmojiPlaceholder('[惊喜')).assertFalse();
    });

    it('buildsEmojiFileName', 0, () => {
      expect(emojiFileName('1114211823741685761')).assertEqual('emoji_1114211823741685761.png');
    });

    it('splitsTextWithEmojiPlaceholders', 0, () => {
      const segments = parseEmojiSegments('前文[惊喜]后文', resolveKnown);
      expect(kinds(segments)).assertEqual('text,emoji,text');
      expect(segments[0].text).assertEqual('前文');
      expect(segments[1].text).assertEqual('[惊喜]');
      expect(segments[1].path.length > 0).assertTrue();
      expect(segments[2].text).assertEqual('后文');
    });

    it('keepsUnknownPlaceholdersAsText', 0, () => {
      const segments = parseEmojiSegments('[不存在][惊喜]', resolveKnown);
      expect(kinds(segments)).assertEqual('text,emoji');
      expect(segments[0].text).assertEqual('[不存在]');
      expect(segments[1].text).assertEqual('[惊喜]');
    });

    it('keepsUnclosedBracketAsText', 0, () => {
      // 与上游一致：未闭合的 `[` 连同后续字符在收尾时原样并入文本。
      const segments = parseEmojiSegments('看看 [惊喜 和 收尾', resolveKnown);
      expect(kinds(segments)).assertEqual('text');
      expect(segments[0].text).assertEqual('看看 [惊喜 和 收尾');
    });

    it('keepsDanglingBracketAtEnd', 0, () => {
      const segments = parseEmojiSegments('文字[', resolveKnown);
      expect(kinds(segments)).assertEqual('text');
      expect(segments[0].text).assertEqual('文字[');
    });

    it('keepsLoneClosingBracketAsText', 0, () => {
      const segments = parseEmojiSegments('a]b[惊喜]', resolveKnown);
      expect(kinds(segments)).assertEqual('text,emoji');
      expect(segments[0].text).assertEqual('a]b');
    });

    it('mergesUnresolvedPlaceholderIntoText', 0, () => {
      const segments = parseEmojiSegments('x[不存在]y[惊喜]', resolveKnown);
      expect(kinds(segments)).assertEqual('text,emoji');
      expect(segments[0].text).assertEqual('x[不存在]y');
    });

    it('accumulatesNestedBracketsLikeUpstream', 0, () => {
      // 上游行为：emoji 缓冲遇到第二个 `[` 继续累积，整体无法命中则保持原文。
      const segments = parseEmojiSegments('a[b[惊喜]c', resolveKnown);
      expect(kinds(segments)).assertEqual('text');
      expect(segments[0].text).assertEqual('a[b[惊喜]c');
    });

    it('parsesBase64DataUrl', 0, () => {
      // 'ZW1vag==' 解码为 4 字节；host 空桩环境下 Base64Helper 无真实解码能力，跳过字节断言。
      if (hostBase64Capable()) {
        const bytes = decodeStickerDataUrl('data:image/png;base64,ZW1vag==');
        expect(bytes?.length).assertEqual(4);
      }
      expect(decodeStickerDataUrl('https://picx.zhimg.com/a.png') === undefined).assertTrue();
      expect(decodeStickerDataUrl('data:image/png;base64,') === undefined).assertTrue();
    });
  });
}
