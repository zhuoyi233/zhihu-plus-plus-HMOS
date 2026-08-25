import { describe, expect, it } from '@ohos/hypium';
import {
  ContentDraftIdentity,
  ContentDraftKind,
  ContentDraftLoadStatus,
  ContentDraftMetadata,
  ContentDraftMetadataStore,
  ContentDraftSaveInput,
  createAnswerDraftIdentity,
  createPinDraftIdentity,
  DRAFT_KEY_ALIAS,
  DraftBodyStore,
  DraftRepository,
  hashDraftAccountId,
  isSafeDraftAccountKey
} from 'data';

const FIRST_ACCOUNT: string = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const SECOND_ACCOUNT: string = 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const PIN_DRAFT_ID: string = '01234567-89ab-4cde-8fab-0123456789ab';

class MemoryMetadataStore implements ContentDraftMetadataStore {
  private readonly records: Map<string, ContentDraftMetadata> = new Map<string, ContentDraftMetadata>();

  find(identity: ContentDraftIdentity): Promise<ContentDraftMetadata | undefined> {
    return Promise.resolve(this.records.get(identity.draftKey));
  }

  listForAccount(accountKey: string): Promise<Array<ContentDraftMetadata>> {
    const result: Array<ContentDraftMetadata> = [];
    this.records.forEach((metadata: ContentDraftMetadata): void => {
      if (metadata.accountKey === accountKey) {
        result.push(metadata);
      }
    });
    return Promise.resolve(result);
  }

  upsert(metadata: ContentDraftMetadata): Promise<void> {
    this.records.set(metadata.draftKey, metadata);
    return Promise.resolve();
  }

  remove(identity: ContentDraftIdentity): Promise<void> {
    this.records.delete(identity.draftKey);
    return Promise.resolve();
  }
}

class MemoryBodyStore implements DraftBodyStore {
  private readonly bodies: Map<string, string> = new Map<string, string>();
  failLoad: boolean = false;

  save(draftKey: string, html: string): Promise<void> {
    this.bodies.set(draftKey, html);
    return Promise.resolve();
  }

  load(draftKey: string): Promise<string | undefined> {
    if (this.failLoad) {
      return Promise.reject(new Error('encrypted envelope is damaged'));
    }
    return Promise.resolve(this.bodies.get(draftKey));
  }

  remove(draftKey: string): Promise<void> {
    this.bodies.delete(draftKey);
    return Promise.resolve();
  }
}

function answerInput(accountKey: string, html: string): ContentDraftSaveInput {
  const identity = createAnswerDraftIdentity(accountKey, '123');
  return {
    draftKey: identity.draftKey,
    accountKey: identity.accountKey,
    kind: identity.kind,
    targetId: identity.targetId,
    html: html,
    remoteContentId: '456',
    title: '',
    plainTextLength: html.length,
    tocEnabled: true,
    imageRefsJson: '[]',
    topicRefsJson: '[]',
    dirty: true
  };
}

export default function draftRepositoryTest(): void {
  describe('draftRepositoryTest', () => {
    it('buildsAccountIsolatedAnswerAndPinKeysWithoutRawAccountIdentity', 0, () => {
      const answer = createAnswerDraftIdentity(FIRST_ACCOUNT, '123');
      const pin = createPinDraftIdentity(FIRST_ACCOUNT, PIN_DRAFT_ID);
      const otherAccount = createAnswerDraftIdentity(SECOND_ACCOUNT, '123');

      expect(isSafeDraftAccountKey(FIRST_ACCOUNT)).assertTrue();
      expect(answer.draftKey).assertEqual(`answer:${FIRST_ACCOUNT}:123`);
      expect(pin.draftKey).assertEqual(`pin:${FIRST_ACCOUNT}:${PIN_DRAFT_ID}`);
      expect(otherAccount.draftKey === answer.draftKey).assertFalse();
      expect(answer.draftKey.includes('z_c0')).assertFalse();
      expect(DRAFT_KEY_ALIAS === 'zhihu-plus-cookie-session-key-v1').assertFalse();
    });

    it('hashesStableAccountIdentityWithoutUsingCookieMaterial', 0, async () => {
      const first = await hashDraftAccountId('people-123');
      const repeated = await hashDraftAccountId('people-123');
      const second = await hashDraftAccountId('people-456');

      expect(isSafeDraftAccountKey(first)).assertTrue();
      expect(first).assertEqual(repeated);
      expect(first === second).assertFalse();
      expect(first.includes('people-123')).assertFalse();
    });

    it('rejectsUnsafeAccountKeysAndWrongDraftTargets', 0, () => {
      expect(() => createAnswerDraftIdentity('account-id', '123')).assertThrowError('Draft identity is invalid');
      expect(() => createAnswerDraftIdentity(FIRST_ACCOUNT, 'abc')).assertThrowError('Draft identity is invalid');
      expect(() => createPinDraftIdentity(FIRST_ACCOUNT, 'not-a-uuid')).assertThrowError('Draft identity is invalid');
    });

    it('savesEncryptedBodyThroughRepositoryAndVersionsMetadata', 0, async () => {
      const metadataStore = new MemoryMetadataStore();
      const bodyStore = new MemoryBodyStore();
      const repository = new DraftRepository(metadataStore, bodyStore);
      const first = await repository.save(answerInput(FIRST_ACCOUNT, '<p>first</p>'), 100);
      const second = await repository.save(answerInput(FIRST_ACCOUNT, '<p>second</p>'), 200);
      const loaded = await repository.load(createAnswerDraftIdentity(FIRST_ACCOUNT, '123'));

      expect(first.version).assertEqual(1);
      expect(second.version).assertEqual(2);
      expect(second.createdAt).assertEqual(100);
      expect(second.updatedAt).assertEqual(200);
      expect(loaded.status).assertEqual(ContentDraftLoadStatus.FOUND);
      expect(loaded.draft?.html).assertEqual('<p>second</p>');
      expect(loaded.draft?.metadata.remoteContentId).assertEqual('456');
    });

    it('doesNotCrossLoadSameQuestionForAnotherAccount', 0, async () => {
      const metadataStore = new MemoryMetadataStore();
      const repository = new DraftRepository(metadataStore, new MemoryBodyStore());
      await repository.save(answerInput(FIRST_ACCOUNT, '<p>private draft</p>'), 100);

      const wrongAccount = await repository.load(createAnswerDraftIdentity(SECOND_ACCOUNT, '123'));
      const correctAccount = await repository.load(createAnswerDraftIdentity(FIRST_ACCOUNT, '123'));

      expect(wrongAccount.status).assertEqual(ContentDraftLoadStatus.NOT_FOUND);
      expect(correctAccount.status).assertEqual(ContentDraftLoadStatus.FOUND);
    });

    it('listsOnlyMetadataInTheRequestedAccountScopeWithoutReadingBodies', 0, async () => {
      const metadataStore = new MemoryMetadataStore();
      const bodyStore = new MemoryBodyStore();
      const repository = new DraftRepository(metadataStore, bodyStore);
      await repository.save(answerInput(FIRST_ACCOUNT, '<p>first private body</p>'), 100);
      await repository.save(answerInput(SECOND_ACCOUNT, '<p>second private body</p>'), 200);

      const firstAccount = await repository.listMetadataForAccount(FIRST_ACCOUNT);
      const secondAccount = await repository.listMetadataForAccount(SECOND_ACCOUNT);

      expect(firstAccount.length).assertEqual(1);
      expect(firstAccount[0].accountKey).assertEqual(FIRST_ACCOUNT);
      expect(firstAccount[0].draftKey.includes('first private body')).assertFalse();
      expect(secondAccount.length).assertEqual(1);
      expect(secondAccount[0].accountKey).assertEqual(SECOND_ACCOUNT);
    });

    it('containsDamagedEnvelopeAndDeletesMetadataAndBodyOnlyOnExplicitDiscard', 0, async () => {
      const metadataStore = new MemoryMetadataStore();
      const bodyStore = new MemoryBodyStore();
      const repository = new DraftRepository(metadataStore, bodyStore);
      const input = answerInput(FIRST_ACCOUNT, '<p>private draft</p>');
      await repository.save(input, 100);
      bodyStore.failLoad = true;

      const damaged = await repository.load(createAnswerDraftIdentity(FIRST_ACCOUNT, '123'));
      expect(damaged.status).assertEqual(ContentDraftLoadStatus.CORRUPT);

      bodyStore.failLoad = false;
      await repository.discard(createAnswerDraftIdentity(FIRST_ACCOUNT, '123'));
      const removed = await repository.load(createAnswerDraftIdentity(FIRST_ACCOUNT, '123'));
      expect(removed.status).assertEqual(ContentDraftLoadStatus.NOT_FOUND);
    });
  });
}
