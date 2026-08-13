import { PeopleProfile } from '../domain/DomainModels';
import { decodePeopleDetail } from '../domain/PeoplePinDetailDecoder';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';
import { PeopleDetailRepository } from './PeopleRepository';

export const PEOPLE_DETAIL_INCLUDE =
  'allow_message,is_followed,is_following,is_org,is_blocking,badge_v2,answer_count,follower_count,' +
    'following_count,articles_count,question_count,pins_count';

export enum PeopleRepositoryFailureKind {
  INVALID_IDENTIFIER = 'invalid_identifier',
  CANCELLED = 'cancelled'
}

export class PeopleRepositoryFailure extends Error {
  readonly kind: PeopleRepositoryFailureKind;

  constructor(kind: PeopleRepositoryFailureKind) {
    super(kind === PeopleRepositoryFailureKind.INVALID_IDENTIFIER ? '用户标识无效' : '用户详情请求已取消');
    this.name = 'PeopleRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizePeopleIdentifier(idOrToken: string): string {
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(idOrToken)) {
    throw new PeopleRepositoryFailure(PeopleRepositoryFailureKind.INVALID_IDENTIFIER);
  }
  return idOrToken;
}

export function buildPeopleDetailUrl(idOrToken: string): string {
  const identifier = normalizePeopleIdentifier(idOrToken);
  return `https://api.zhihu.com/people/${encodeURIComponent(identifier)}?include=${encodeURIComponent(
    PEOPLE_DETAIL_INCLUDE
  )}`;
}

export class DefaultPeopleRepository implements PeopleDetailRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getUser(idOrToken: string): Promise<PeopleProfile> {
    const identifier = normalizePeopleIdentifier(idOrToken);
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: buildPeopleDetailUrl(identifier),
      accept: 'application/json'
    });
    if (generation !== this.generation) {
      throw new PeopleRepositoryFailure(PeopleRepositoryFailureKind.CANCELLED);
    }
    return decodePeopleDetail(response.body, identifier);
  }
}
