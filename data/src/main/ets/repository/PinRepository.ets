import { PinDetail } from '../domain/DomainModels';

export interface PinRepository {
  getPin(id: string): Promise<PinDetail>;
  cancel(): void;
}
