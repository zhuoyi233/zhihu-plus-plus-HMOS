import { SearchResultPage } from '../domain/SearchModels';

export interface SearchRepository {
  search(query: string, cursor?: string): Promise<SearchResultPage>;
  cancel(): void;
}
