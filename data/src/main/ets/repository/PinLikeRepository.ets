export interface PinLikeResult {
  readonly likeCount?: number;
}

export interface PinLikeRepository {
  setLiked(id: string, liked: boolean): Promise<PinLikeResult>;
  cancel(): void;
}
