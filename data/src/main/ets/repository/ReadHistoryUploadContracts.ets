/** 对齐上游 addReadHistory 的上云通道：打开内容时单条上报，contentKey 形如 "answer:123456"。 */
export interface ReadHistoryUploadRepository {
  add(contentKey: string): Promise<void>;
  /** 对齐上游 PeopleScreen 的 addReadHistory(person.id, "profile")：访问个人主页上报。 */
  addProfile(personId: string): Promise<void>;
}
