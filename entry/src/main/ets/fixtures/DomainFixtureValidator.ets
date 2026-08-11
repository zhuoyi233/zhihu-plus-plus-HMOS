import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  decodeAnswer,
  decodeArticle,
  decodeFeedPage,
  decodeQuestion,
  decodeUser,
  DomainDecodeError,
  DomainDecodeFailureKind
} from 'data';

export enum DomainFixtureTarget {
  USER = 'user',
  QUESTION = 'question',
  ANSWER = 'answer',
  ARTICLE = 'article',
  FEED_PAGE = 'feed_page',
  MIXED_FEED_PAGE = 'mixed_feed_page',
  EMPTY_FEED_PAGE = 'empty_feed_page',
  ERROR_RESPONSE = 'error_response'
}

export interface DomainFixtureSpec {
  fileName: string;
  target: DomainFixtureTarget;
  expectedFailure?: DomainDecodeFailureKind;
}

export const DOMAIN_FIXTURE_SPECS: ReadonlyArray<DomainFixtureSpec> = [
  { fileName: 'user.json', target: DomainFixtureTarget.USER },
  { fileName: 'question.json', target: DomainFixtureTarget.QUESTION },
  { fileName: 'answer.json', target: DomainFixtureTarget.ANSWER },
  { fileName: 'article.json', target: DomainFixtureTarget.ARTICLE },
  { fileName: 'feed-page.json', target: DomainFixtureTarget.FEED_PAGE },
  { fileName: 'feed-page-mixed.json', target: DomainFixtureTarget.MIXED_FEED_PAGE },
  { fileName: 'empty-fields.json', target: DomainFixtureTarget.EMPTY_FEED_PAGE },
  {
    fileName: 'error-response.json',
    target: DomainFixtureTarget.ERROR_RESPONSE,
    expectedFailure: DomainDecodeFailureKind.UPSTREAM_ERROR
  }
];

export enum DomainFixtureGateFailureKind {
  RESOURCE_READ_FAILED = 'resource_read_failed',
  DECODER_REJECTED = 'decoder_rejected',
  EXPECTED_FAILURE_MISSING = 'expected_failure_missing',
  WRONG_FAILURE_KIND = 'wrong_failure_kind',
  CONTRACT_MISMATCH = 'contract_mismatch'
}

export interface DomainFixtureCaseResult {
  fileName: string;
  passed: boolean;
  summary: string;
}

export interface DomainFixtureValidationReport {
  total: number;
  passed: number;
  results: Array<DomainFixtureCaseResult>;
}

export class DomainFixtureValidator {
  private readonly context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async validateAll(): Promise<DomainFixtureValidationReport> {
    const results: Array<DomainFixtureCaseResult> = [];
    for (let index = 0; index < DOMAIN_FIXTURE_SPECS.length; index += 1) {
      const spec = DOMAIN_FIXTURE_SPECS[index];
      try {
        const bytes = await this.context.resourceManager.getRawFileContent(`fixtures/${spec.fileName}`);
        const json = util.TextDecoder.create('utf-8').decodeToString(bytes);
        results.push(this.validateFixture(spec, json));
      } catch (_error) {
        results.push(this.failure(spec, DomainFixtureGateFailureKind.RESOURCE_READ_FAILED));
      }
    }
    return {
      total: results.length,
      passed: results.filter((result: DomainFixtureCaseResult): boolean => result.passed).length,
      results: results
    };
  }

  private validateFixture(spec: DomainFixtureSpec, json: string): DomainFixtureCaseResult {
    try {
      this.decodeAndAssert(spec.target, json);
      if (spec.expectedFailure !== undefined) {
        return this.failure(spec, DomainFixtureGateFailureKind.EXPECTED_FAILURE_MISSING);
      }
      return { fileName: spec.fileName, passed: true, summary: `${spec.fileName}：通过` };
    } catch (error) {
      if (spec.expectedFailure === undefined) {
        const kind = error instanceof DomainDecodeError ? error.kind : DomainFixtureGateFailureKind.CONTRACT_MISMATCH;
        return this.failure(spec, DomainFixtureGateFailureKind.DECODER_REJECTED, kind);
      }
      if (error instanceof DomainDecodeError && error.kind === spec.expectedFailure) {
        return { fileName: spec.fileName, passed: true, summary: `${spec.fileName}：按预期拒绝` };
      }
      return this.failure(spec, DomainFixtureGateFailureKind.WRONG_FAILURE_KIND);
    }
  }

  private decodeAndAssert(target: DomainFixtureTarget, json: string): void {
    if (target === DomainFixtureTarget.USER) {
      const user = decodeUser(json);
      if (user.id !== 'user-fixture-001' || user.urlToken !== 'fixture-user' || user.followerCount !== 42) {
        throw new Error('user contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.QUESTION) {
      const question = decodeQuestion(json);
      if (question.id !== '10000000000000001' || question.answerCount !== 3 || question.author?.id !== 'user-fixture-001') {
        throw new Error('question contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.ANSWER) {
      const answer = decodeAnswer(json);
      if (answer.id !== '20000000000000002' || answer.questionId !== '10000000000000001' || answer.voteupCount !== 27) {
        throw new Error('answer contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.ARTICLE) {
      const article = decodeArticle(json);
      if (article.id !== '30000000000000003' || article.author?.isOrganization !== true || article.commentCount !== 4) {
        throw new Error('article contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.FEED_PAGE) {
      const page = decodeFeedPage(json);
      if (page.items.length !== 2 || page.cursor.isEnd || page.cursor.page !== 1 || page.cursor.total !== 25) {
        throw new Error('feed page contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.MIXED_FEED_PAGE) {
      const page = decodeFeedPage(json);
      if (page.items.length !== 1 || page.items[0].id !== 'feed-answer-supported' ||
        page.cursor.isEnd || page.cursor.next === undefined) {
        throw new Error('mixed feed page contract mismatch');
      }
      return;
    }
    if (target === DomainFixtureTarget.EMPTY_FEED_PAGE) {
      const page = decodeFeedPage(json);
      if (page.items.length !== 0 || !page.cursor.isEnd || page.cursor.next !== undefined) {
        throw new Error('empty feed page contract mismatch');
      }
      return;
    }
    decodeFeedPage(json);
  }

  private failure(
    spec: DomainFixtureSpec,
    kind: DomainFixtureGateFailureKind,
    decoderKind?: DomainDecodeFailureKind | DomainFixtureGateFailureKind
  ): DomainFixtureCaseResult {
    const suffix = decoderKind === undefined ? kind : `${kind}/${decoderKind}`;
    return { fileName: spec.fileName, passed: false, summary: `${spec.fileName}：${suffix}` };
  }
}
