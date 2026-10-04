/** 对齐上游 addReadHistory 的上云通道：打开内容时单条上报，contentKey 形如 "answer:123456"。 */
export interface ReadHistoryUploadRepository {
  add(contentKey: string): Promise<void>;
}
