import { describe, expect, it } from '@ohos/hypium';
import {
  AnswerPublishInput,
  DefaultCreationPublishRepository,
  DefaultPinPublishRepository,
  PinPublishInput,
  PinTopicSuggestion,
  PreparedZhihuHttpRequest,
  PublishFailure,
  PublishFailureKind,
  SessionCookie,
  SessionCookieProvider,
  ZhihuHttpClient,
  ZhihuHttpMethod,
  ZhihuHttpResponse,
  ZhihuHttpTransport,
  ZhihuHttpTransportFactory
} from 'data';

const TRACE_ID: string = '1770000000000,01234567-89ab-4cde-8fab-0123456789ab';

class FixedCookieProvider implements SessionCookieProvider {
  getCookies(): Array<SessionCookie> {
    return [
      { name: 'z_c0', value: 'login-token' },
      { name: 'd_c0', value: 'device-token' },
      { name: '_xsrf', value: 'xsrf-token' }
    ];
  }
}

class RecordingTransport implements ZhihuHttpTransport {
  private readonly factory: RecordingTransportFactory;

  constructor(factory: RecordingTransportFactory) {
    this.factory = factory;
  }

  request(request: PreparedZhihuHttpRequest): Promise<ZhihuHttpResponse> {
    this.factory.requests.push(request);
    const response = this.factory.responses.shift();
    return Promise.resolve(response === undefined ? { statusCode: 500, body: '{}' } : response);
  }

  destroy(): void {
  }
}

class RecordingTransportFactory implements ZhihuHttpTransportFactory {
  readonly requests: Array<PreparedZhihuHttpRequest> = [];
  readonly responses: Array<ZhihuHttpResponse> = [];

  create(): ZhihuHttpTransport {
    return new RecordingTransport(this);
  }
}

function createClient(factory: RecordingTransportFactory): ZhihuHttpClient {
  return new ZhihuHttpClient(new FixedCookieProvider(), factory);
}

function answerInput(): AnswerPublishInput {
  return {
    questionId: '123',
    answerId: '456',
    html: '<p>HarmonyOS</p>',
    tocEnabled: true,
    traceId: TRACE_ID
  };
}

function pinInput(): PinPublishInput {
  return {
    title: '迁移进度',
    html: '<p>API 26</p>',
    textLength: 6,
    images: [],
    topics: [],
    traceId: TRACE_ID
  };
}

export default function defaultCreationPublishRepositoryTest(): void {
  describe('defaultCreationPublishRepositoryTest', () => {
    it('usesProtectedContractsForAnswerRelationshipEditingDraftAndPublish', 0, async () => {
      const factory = new RecordingTransportFactory();
      factory.responses.push(
        { statusCode: 200, body: '{"relationship":{"my_answer":{"answer_id":"456","is_deleted":false}}}' },
        { statusCode: 200, body: '{"id":"456","editable_content":"<p>可编辑</p>",' +
          '"content":"<p>回退</p>","settings":{"table_of_contents":{"enabled":true}}}' },
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{"code":103003}' }
      );
      const repository = new DefaultCreationPublishRepository(createClient(factory));

      const answerId = await repository.findMyAnswerId('123');
      const existing = await repository.fetchAnswerForEditing('456');
      await repository.saveRemoteDraft(answerInput());
      const publishResponse = await repository.publish(answerInput());

      expect(answerId).assertEqual('456');
      expect(existing?.answerId).assertEqual('456');
      expect(existing?.html).assertEqual('<p>可编辑</p>');
      expect(existing?.tocEnabled).assertTrue();
      expect(publishResponse).assertEqual('{"code":103003}');
      expect(factory.requests.length).assertEqual(4);
      expect(factory.requests[0].method).assertEqual(ZhihuHttpMethod.GET);
      expect(factory.requests[0].url).assertEqual(
        'https://api.zhihu.com/questions/123?include=relationship%2Crelationship.my_answer'
      );
      expect(factory.requests[1].url.startsWith('https://www.zhihu.com/api/v4/answers/456?include=')).assertTrue();
      expect(factory.requests[2].url).assertEqual('https://www.zhihu.com/api/v4/questions/123/draft');
      expect(JSON.stringify(factory.requests[2].headers).includes('"x-xsrftoken":"xsrf-token"')).assertTrue();
      expect(factory.requests[2].body?.includes('"table_of_contents_enabled":true')).assertTrue();
      expect(factory.requests[3].url).assertEqual('https://www.zhihu.com/api/v4/content/publish');
      expect(JSON.stringify(factory.requests[3].headers).includes('"x-xsrftoken":"xsrf-token"')).assertTrue();
      expect(factory.requests[3].maxRedirects).assertEqual(0);
    });

    it('parsesSafePinTopicsAndReturnsOnlyNestedPublishedId', 0, async () => {
      const factory = new RecordingTransportFactory();
      factory.responses.push(
        { statusCode: 200, body: '{"data":{"list":[' +
          '{"id":"first","name":"HarmonyOS","topic_id":2,"discuss_count":"10 条讨论"},' +
          '{"id":"unsafe","name":"#bad#","topic_id":3,"discuss_count":"1"}]}}' },
        { statusCode: 200, body: '{}' },
        { statusCode: 200, body: '{"data":{"result":"{\\"publish\\":{\\"id\\":\\"789\\"}}"}}' }
      );
      const repository = new DefaultPinPublishRepository(createClient(factory));

      const suggestions: Array<PinTopicSuggestion> = await repository.recommendTopics('Harmony OS', '迁移进度', '<p>API 26</p>');
      await repository.saveRemoteDraft(pinInput());
      const publishedId = await repository.publish(pinInput());

      expect(suggestions.length).assertEqual(1);
      expect(suggestions[0].topicId).assertEqual('2');
      expect(suggestions[0].displayName).assertEqual('HarmonyOS');
      expect(suggestions[0].discussCount).assertEqual('10 条讨论');
      expect(publishedId).assertEqual('789');
      expect(factory.requests[0].url).assertEqual(
        'https://api.zhihu.com/content/publish/topics/recommend?recommend_type=pin&key_word=Harmony+OS'
      );
      expect(JSON.stringify(factory.requests[0].headers).includes('"x-xsrftoken":"xsrf-token"')).assertTrue();
      expect(factory.requests[1].url).assertEqual('https://api.zhihu.com/content/drafts');
      expect(factory.requests[1].body?.includes('"action":"pin"')).assertTrue();
      expect(factory.requests[2].url).assertEqual('https://www.zhihu.com/api/v4/content/publish');
      expect(factory.requests[2].body?.includes('"action":"pin"')).assertTrue();
    });

    it('fallsBackToContentWhenExistingAnswerHasNoEditableContent', 0, async () => {
      const factory = new RecordingTransportFactory();
      factory.responses.push({ statusCode: 200, body: '{"id":456,"content":"<p>回退正文</p>"}' });

      const existing = await new DefaultCreationPublishRepository(createClient(factory)).fetchAnswerForEditing('456');

      expect(existing?.answerId).assertEqual('456');
      expect(existing?.html).assertEqual('<p>回退正文</p>');
      expect(existing?.tocEnabled).assertFalse();
    });

    it('mapsMalformedCreationResponsesToSafeServerFailures', 0, async () => {
      const relationshipFactory = new RecordingTransportFactory();
      relationshipFactory.responses.push({ statusCode: 200, body: 'not-json' });
      let relationshipFailure: PublishFailure | undefined = undefined;
      try {
        await new DefaultCreationPublishRepository(createClient(relationshipFactory)).findMyAnswerId('123');
      } catch (error) {
        if (error instanceof PublishFailure) {
          relationshipFailure = error;
        }
      }

      const publishFactory = new RecordingTransportFactory();
      publishFactory.responses.push({ statusCode: 200, body: '{"data":{"result":"invalid"}}' });
      let publishFailure: PublishFailure | undefined = undefined;
      try {
        await new DefaultPinPublishRepository(createClient(publishFactory)).publish(pinInput());
      } catch (error) {
        if (error instanceof PublishFailure) {
          publishFailure = error;
        }
      }

      expect(relationshipFailure?.kind).assertEqual(PublishFailureKind.SERVER);
      expect(relationshipFailure?.preservesLocalDraft).assertTrue();
      expect(publishFailure?.kind).assertEqual(PublishFailureKind.SERVER);
      expect(publishFailure?.preservesLocalDraft).assertTrue();
    });
  });
}
