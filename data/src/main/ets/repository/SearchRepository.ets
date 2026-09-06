import { SearchFilters, SearchHotItem, SearchTab, SearchResultPage } from '../domain/SearchModels';

export interface SearchRepository {
  search(query: string, filters?: SearchFilters, tab?: SearchTab, cursor?: string): Promise<SearchResultPage>;
  hotSearch(): Promise<Array<SearchHotItem>>;
  cancel(): void;
}
