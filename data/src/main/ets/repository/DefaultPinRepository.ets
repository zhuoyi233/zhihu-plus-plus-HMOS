import { PinDetail } from '../domain/DomainModels';
import { decodePinDetail } from '../domain/PeoplePinDetailDecoder';
import { ZhihuHttpClient } from '../network/ZhihuHttpClient';
import { PinRepository } from './PinRepository';

export enum PinRepositoryFailureKind {
  INVALID_ID = 'invalid_id',
  CANCELLED = 'cancelled'
}

export class PinRepositoryFailure extends Error {
  readonly kind: PinRepositoryFailureKind;

  constructor(kind: PinRepositoryFailureKind) {
    super(kind === PinRepositoryFailureKind.INVALID_ID ? '想法 ID 无效' : '想法详情请求已取消');
    this.name = 'PinRepositoryFailure';
    this.kind = kind;
  }
}

export function normalizePinId(id: string): string {
  if (!/^[1-9][0-9]{0,29}$/.test(id)) {
    throw new PinRepositoryFailure(PinRepositoryFailureKind.INVALID_ID);
  }
  return id;
}

export function buildPinDetailUrl(id: string): string {
  return `https://www.zhihu.com/api/v4/pins/${normalizePinId(id)}?include=topics`;
}

export class DefaultPinRepository implements PinRepository {
  private readonly httpClient: ZhihuHttpClient;
  private generation: number = 0;

  constructor(httpClient: ZhihuHttpClient) {
    this.httpClient = httpClient;
  }

  cancel(): void {
    this.generation += 1;
    this.httpClient.cancel();
  }

  async getPin(id: string): Promise<PinDetail> {
    const normalizedId = normalizePinId(id);
    const generation = this.generation;
    const response = await this.httpClient.execute({
      url: buildPinDetailUrl(normalizedId),
      accept: 'application/json',
      useSession: true,
      signWithZse: true
    });
    if (generation !== this.generation) {
      throw new PinRepositoryFailure(PinRepositoryFailureKind.CANCELLED);
    }
    return decodePinDetail(response.body, normalizedId);
  }
}
