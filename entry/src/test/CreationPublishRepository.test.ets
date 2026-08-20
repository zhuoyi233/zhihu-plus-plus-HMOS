import { describe, expect, it } from '@ohos/hypium';
import {
  AnswerPublishInput,
  buildAnswerPublishRequest,
  buildAnswerRemoteDraftRequest,
  buildAnswerRelationshipRequest,
  buildPinPublishRequest,
  buildPinTopicRecommendationRequest,
  HttpFailure,
  HttpFailureKind,
  isExistingAnswerConflict,
  parsePublishedContentId,
  prepareZhihuHttpRequest,
  PinPublishInput,
  PublishFailure,
  PublishFailureKind,
  toPublishFailure,
  ZhihuHttpMethod
} from 'data';

const TRACE_ID: string = '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';

export default function creationPublishRepositoryTest(): void {
  describe('creationPublishRepositoryTest', () => {
    it('freezesAnswerEndpointsAndProtectedRequestShape', 0, () => {
      const input: AnswerPublishInput = {
        questionId: '123',
        answerId: '456',
        html: '<p>HarmonyOS</p>',
        tocEnabled: true,
        traceId: TRACE_ID
      };
      const relationship = buildAnswerRelationshipRequest(input.questionId);
      const draft = buildAnswerRemoteDraftRequest(input);
      const publish = buildAnswerPublishRequest(input);
      const prepared = prepareZhihuHttpRequest({
        url: publish.url,
        method: publish.method,
        body: publish.body,
        useSession: publish.useSession,
        signWithZse: publish.signWithZse,
        includeXsrfToken: publish.includeXsrfToken,
        refererPath: publish.refererPath
      }, [
        { name: 'd_c0', value: 'device' },
        { name: '_xsrf', value: 'xsrf' }
      ], 1);

      expect(relationship.url).assertEqual('https://api.zhihu.com/questions/123?include=relationship%2Crelationship.my_answer');
      expect(relationship.method).assertEqual(ZhihuHttpMethod.GET);
      expect(draft.url).assertEqual('https://www.zhihu.com/api/v4/questions/123/draft');
      expect(draft.refererPath).assertEqual('/question/123/answer/456');
      expect(publish.url).assertEqual('https://www.zhihu.com/api/v4/content/publish');
      expect(publish.method).assertEqual(ZhihuHttpMethod.POST);
      expect(publish.body?.includes('"action":"answer"')).assertTrue();
      expect(publish.body?.includes('"question_id":"123"')).assertTrue();
      expect(publish.body?.includes('"table_of_contents_enabled":true')).assertTrue();
      const serializedHeaders = JSON.stringify(prepared.headers);
      expect(serializedHeaders.includes('"x-xsrftoken":"xsrf"')).assertTrue();
      expect(serializedHeaders.includes('"x-zse-96":"2.0_')).assertTrue();
      expect(prepared.maxRedirects).assertEqual(0);
    });

    it('freezesDistinctPinPayloadAndTopicEncoding', 0, () => {
      const input: PinPublishInput = {
        title: '鸿蒙迁移',
        html: '<p>创作合同</p>',
        textLength: 4,
        images: [{
          imageId: '1',
          url: 'https://picx.zhimg.com/v2-image.jpg',
          originalUrl: 'https://picx.zhimg.com/v2-image-original.jpg',
          width: 1080,
          height: 720,
          watermark: 'original'
        }],
        topics: [{ topicId: '2', displayName: 'HarmonyOS' }],
        traceId: TRACE_ID
      };
      const recommendation = buildPinTopicRecommendationRequest('Harmony OS', input.title, input.html);
      const publish = buildPinPublishRequest(input);

      expect(recommendation.url).assertEqual(
        'https://api.zhihu.com/content/publish/topics/recommend?recommend_type=pin&key_word=Harmony+OS'
      );
      expect(publish.url).assertEqual('https://www.zhihu.com/api/v4/content/publish');
      expect(publish.body?.includes('"action":"pin"')).assertTrue();
      expect(publish.body?.includes('"textLength":4')).assertTrue();
      expect(publish.body?.includes('"topic_name":"#HarmonyOS#"')).assertTrue();
      expect(publish.body?.includes('"originalUrl":"https://picx.zhimg.com/v2-image-original.jpg"')).assertTrue();
    });

    it('parsesOnlyBoundedNestedPublishIdsAndConflictCodes', 0, () => {
      const valid = '{"message":"success","data":{"result":"{\\"publish\\":{\\"id\\":\\"789\\"}}"}}';
      const directId = '{"message":"success","data":{"result":"{\\"id\\":123}"}}';
      const invalid = '{"data":{"result":"{\\"publish\\":{\\"id\\":\\"not-id\\"}}"}}';
      const conflict = '{"code":103003,"message":"redacted"}';

      expect(parsePublishedContentId(valid)).assertEqual('789');
      expect(parsePublishedContentId(directId)).assertEqual('123');
      expect(parsePublishedContentId(invalid)).assertUndefined();
      expect(parsePublishedContentId('{"data":{"result":"not json"}}')).assertUndefined();
      expect(isExistingAnswerConflict(conflict)).assertTrue();
      expect(isExistingAnswerConflict('{"code":103004}')).assertFalse();
    });

    it('rejectsUnsafeCreationInputsAndUsesFixedFailureMapping', 0, () => {
      let invalid: PublishFailure | undefined = undefined;
      const unsafeInput: AnswerPublishInput = {
        questionId: '../123',
        html: '<p>unsafe target</p>',
        tocEnabled: false,
        traceId: TRACE_ID
      };
      try {
        buildAnswerPublishRequest(unsafeInput);
      } catch (error) {
        if (error instanceof PublishFailure) {
          invalid = error;
        }
      }
      const authentication = toPublishFailure(new HttpFailure(HttpFailureKind.AUTHENTICATION, 401));
      const forbidden = toPublishFailure(new HttpFailure(HttpFailureKind.AUTHENTICATION, 403));
      const rateLimited = toPublishFailure(new HttpFailure(HttpFailureKind.RATE_LIMITED, 429));
      const timeout = toPublishFailure(new HttpFailure(HttpFailureKind.TIMEOUT, 504));
      const cancelled = toPublishFailure(new HttpFailure(HttpFailureKind.CANCELLED));

      expect(invalid?.kind).assertEqual(PublishFailureKind.INVALID_INPUT);
      expect(invalid?.preservesLocalDraft).assertTrue();
      expect(authentication.kind).assertEqual(PublishFailureKind.AUTHENTICATION);
      expect(forbidden.kind).assertEqual(PublishFailureKind.FORBIDDEN);
      expect(rateLimited.kind).assertEqual(PublishFailureKind.RATE_LIMITED);
      expect(rateLimited.retryable).assertTrue();
      expect(timeout.kind).assertEqual(PublishFailureKind.TIMEOUT);
      expect(cancelled.kind).assertEqual(PublishFailureKind.CANCELLED);
    });
  });
}
