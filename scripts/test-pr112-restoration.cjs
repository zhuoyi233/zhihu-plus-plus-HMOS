/** PR112 behavior gates. Runs real ArkTS classes/methods with platform IO replaced.
 * node scripts/test-pr112-restoration.cjs --typescript <typescript module path>
 * --baseline only accepts the explicitly recorded defects; it is NOT a passing acceptance run.
 */
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const typeScriptArg = args.indexOf('--typescript');
const ts = require(typeScriptArg >= 0 ? path.resolve(args[typeScriptArg + 1]) : 'typescript');
const baseline = args.includes('--baseline');
const cache = new Map();
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const compile = source => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
}).outputText;
function load(file) {
  const full = path.resolve(root, file);
  if (cache.has(full)) return cache.get(full).exports;
  const mod = { exports: {} };
  cache.set(full, mod);
  const localRequire = spec => {
    if (spec === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
    if (spec.startsWith('@kit.')) return {};
    if (spec.endsWith('/CookieSession')) return { toCookieHeader: () => 'd_c0=test' };
    if (spec.endsWith('/ZhihuFetchSignature')) return { createZse96Header: () => 'test', ZHIHU_WEB_ZSE93: 'test' };
    if (spec.endsWith('/ContentDetailDecoder')) return {
      decodeAnswerDetail: JSON.parse, decodeArticleDetail: JSON.parse, decodeQuestionDetail: JSON.parse
    };
    if (spec.endsWith('/DomainModels')) return {};
    if (spec === 'data') return {
      ...load('data/src/main/ets/domain/CommentModels.ets'),
      ...load('data/src/main/ets/repository/ContentRepository.ets'),
      ...load('data/src/main/ets/repository/DefaultContentRepository.ets'),
      ...load('data/src/main/ets/network/HttpFailure.ets'),
      QuestionAnswerSortOrder: { DEFAULT: 'default' },
      DomainDecodeError: class DomainDecodeError extends Error {}
    };
    return load(path.relative(root, path.resolve(path.dirname(full), spec + '.ets')));
  };
  vm.runInThisContext('(function(require,module,exports){' + compile(read(file)) + '\n})',
    { filename: full })(localRequire, mod, mod.exports);
  return mod.exports;
}
function methodHarness(file, name, globals = {}) {
  let source = read(file);
  if (file.endsWith('NativeContentDocument.ets')) source = source.slice(source.indexOf('export struct NativeContentDocument'));
  const begin = source.search(new RegExp('  (?:private )?(?:async )?' + name + '\\('));
  assert(begin >= 0, `method missing: ${name}`);
  const end = source.indexOf('\n  }', begin);
  assert(end > begin, `method end missing: ${name}`);
  return vm.runInNewContext(compile('class Harness {\n' + source.slice(begin, end + 4) + '\n}') + '\nHarness', globals);
}
const pages = 'entry/src/main/ets/pages/';
const { ContentDetailController, ContentDetailPhase, acceptsContentDocumentEvent } = load(pages + 'ContentDetailState.ets');
const { ContentDetailKind } = load('data/src/main/ets/repository/ContentRepository.ets');
const answer = id => ({id, questionId: '123', contentHtml: '<p>body</p>', excerpt: '', url: '',
  voteupCount: 0, commentCount: 0, createdAt: 1, updatedAt: 1});
const tests = [];
function contract(name, expectedDefect, run) { tests.push({name, expectedDefect, run}); }
function controllerFixture() {
  const repository = {fail: false, getAnswer: async id => {
    if (repository.fail) throw Error('network');
    return answer(id);
  }, cancel() {}};
  const controller = new ContentDetailController(repository);
  controller.activate();
  return {controller, repository};
}
// These are page methods executed with real navigation/controller/prefetch state and controlled UI IO.
function pageFixture(repository = {getAnswer: async id => answer(id), cancel() {}}, prefetchRepository) {
  const {QuestionAnswerNavigator} = load(pages + 'QuestionAnswerNavigator.ets');
  const {AnswerDetailPrefetcher} = load(pages + 'AnswerSwitchPrefetch.ets');
  const broadcasts = [];
  const storage = {setOrCreate: (key, value) => broadcasts.push({key, value})};
  const names = ['applyAnswerMove', 'moveAnswer', 'commitAnswerSwitch', 'invalidateAnswerSwitch',
    'waitForAnswerViewport', 'finishAnswerViewportWait', 'showAnswerSwitchFailure', 'applyVoteState', 'onLoginChanged', 'isDisplayedContent',
    'resetHotComments', 'refreshHotComments', 'onHotCommentsChanged', 'answerDocumentKey', 'setAnswerPanes', 'publishAnswerPanes',
    'answerNeighbor', 'answerPaneDirection', 'answerPaneForDirection', 'candidatePane', 'mountAnswerCandidate', 'unmountAnswerCandidate',
    'commitAnswerPanes', 'pruneAnswerNeighbors', 'answerDragDirection', 'answerSwitchHintOffset', 'answerSwitchHintAlignment',
    'answerSwitchWaitText', 'prefetchNeighborAnswers',
    'onAnswerDocumentPrepared', 'onAnswerViewportPrepared', 'trackAnswerPaneViewport', 'trackAnswerPaneEdges',
    'beginAnswerSwitchWait', 'dismissAnswerSwitchWait', 'prepareSwitchAnswer', 'cancelAnswerDrag',
    'onAnswerTitleLayoutChanged', 'contentTopInsetVp', 'answerIdentityLayout', 'measureAnswerIdentity', 'updateAnswerTitleScrolled', 'syncAnswerTitle', 'answerPageVisible', 'publishActiveAnswerDocument', 'onReaderOwnerChanged', 'answerPaneTranslate', 'answerPaneVisible', 'answerSwitchPageTranslate', 'answerSwitchExtentVp', 'applyOverscrollOffset'];
  const Harness = methodHarness(pages + 'ContentDetailPages.ets', names[0],
    {AppStorage: storage, ContentDetailKind, ContentDetailPhase, acceptsContentDocumentEvent, readerPositionKey: (kind, id) => kind + ':' + id, FLOATING_TITLE_BAR_OFFSET: 94, ROOT_TITLE_BAR_CONTENT_HEIGHT: 56, contentAuthorName: c => c.value.author?.name ?? '', contentContextTitle: c => c.value.questionTitle ?? '', contentAuthorAvatarUrl: () => '', contentAuthorBadge: () => undefined, publishAnswerTitle: value => broadcasts.push({key: 'answerTitle', value})});
  for (const name of names.slice(1)) {
    Harness.prototype[name] = methodHarness(pages + 'ContentDetailPages.ets', name,
      {AppStorage: storage, ContentDetailKind, ContentDetailPhase, acceptsContentDocumentEvent, readerPositionKey: (kind, id) => kind + ':' + id, FLOATING_TITLE_BAR_OFFSET: 94, ROOT_TITLE_BAR_CONTENT_HEIGHT: 56, contentAuthorName: c => c.value.author?.name ?? '', contentContextTitle: c => c.value.questionTitle ?? '', contentAuthorAvatarUrl: () => '', contentAuthorBadge: () => undefined, publishAnswerTitle: value => broadcasts.push({key: 'answerTitle', value}), SessionStatus: {AUTHENTICATED: 'authenticated'}, setTimeout, clearTimeout}).prototype[name];
  }
  const page = new Harness();
  const opened = [];
  const controller = new ContentDetailController(repository, {upsert: async record => {opened.push(record.contentKey);}}, state => {
    page.phase = state.phase;
    page.content = state.content;
    if (state.content?.kind === ContentDetailKind.ANSWER &&
      !page.answerPanes.some(pane => page.answerDocumentKey(pane) === page.answerDocumentKey(state.content))) {
      page.answerNeighborPanes.clear();
      page.setAnswerPanes([state.content]);
    }
    if (state.content?.kind === ContentDetailKind.ANSWER) page.syncAnswerTitle();
  });
  const seed = {phase: 'ready', items: ['1', '2', '3'].map(id => ({feedItem: {target: answer(id)}})),
    loadingMore: false, canLoadMore: false, sortOrder: 'default', errorMessage: '', requiresLogin: false};
  const navigator = new QuestionAnswerNavigator('123', '1', seed, {cancel() {}, loadPage() {throw Error('unexpected paging');}});
  let voteDeactivated = false;
  const messages = [];
  Object.assign(page, {kind: ContentDetailKind.ANSWER, answerNavigator: navigator, navigatorRevision: 0,
    pageActive: true, contentId: '1', readerVisibleOwner: 'answer:1', activeContentId: '1', phase: 'ready', controller, answerQuestionId: '123',
    navigatorBusy: false, interactionPending: false, answerSwitchEpoch: 0, favoriteStateEpoch: 0,
    answerPanes: [], answerPaneScope: 1, answerPaneRevision: 0,
    answerNeighborPanes: new Map(),
    answerPaneLayout: new (load(pages + 'AnswerPaneLayout.ets').AnswerPaneLayout)(),
    answerSwitchWaitDirection: 0,
    answerSwitchWaitTimer: -1, answerPaneViewports: new Map(), statusBarHeightVp: 0,
    answerTitleGeometry: new (load(pages + 'AnswerTitleGeometry.ets').AnswerTitleGeometry)(),
    answerPanePreparation: new (load(pages + 'AnswerPanePreparation.ets').AnswerPanePreparation)(),
    session: {getState: () => ({status: 'authenticated'})}, answerDataSource: {replace() {}}, ensureAnswers() {}, answerViewportWidthVp: 360,
    answerViewportHeightVp: 800, answerViewportTimer: -1, ensureAnswerPrefetcher() {},
    answerPrefetcher: prefetchRepository ? new AnswerDetailPrefetcher(prefetchRepository) : undefined,
    voteController: {deactivate() {voteDeactivated = true;}},
    animateOverscrollTo: async () => {},
    answerSwitchMode: 'horizontal', answerOverscrollOffset: 0, resetAnswerOverscroll() {}, prefetchNeighborAnswer() {},
    getUIContext: () => ({getPromptAction: () => ({showToast(item) {messages.push(item.message);}})})});
  page.automaticallyPrepareCandidate = true;
  const mount = page.mountAnswerCandidate.bind(page);
  page.mountAnswerCandidate = (content, direction) => {
    mount(content, direction);
    if (page.automaticallyMeasureCandidate !== false) page.measureAnswerIdentity(content, {height: 100});
    if (page.automaticallyPrepareCandidate) queueMicrotask(() => {
      page.onAnswerDocumentPrepared(content);
      page.onAnswerViewportPrepared(content, true);
    });
  };
  controller.activate();
  return {page, controller, navigator, opened, messages, broadcasts, voteDeactivated: () => voteDeactivated,
    dispose() {page.invalidateAnswerSwitch(); page.answerPrefetcher?.dispose(); navigator.dispose(); controller.deactivate();}};
}
contract('target-failure-keeps-current-body-and-identity', false, async () => {
  const repository = {fail: false, getAnswer: async id => {
    if (repository.fail) throw Error('network'); return answer(id);
  }, cancel() {}};
  const fixture = pageFixture(repository);
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    repository.fail = true;
    assert.equal(await fixture.page.applyAnswerMove(1), false);
    assert.equal(fixture.page.activeContentId, '1');
    assert.equal(fixture.navigator.currentId(), '1');
    assert.equal(fixture.controller.snapshot().content.value.id, '1');
    assert.equal(fixture.controller.snapshot().phase, 'ready');
    assert.equal(fixture.voteDeactivated(), false);
    assert.deepEqual(fixture.opened, ['answer:1']);
    assert.equal(fixture.page.navigatorBusy, false);
  } finally {fixture.dispose();}
});
contract('prepare-failure-keeps-current-document', false, async () => {
  const {controller, repository} = controllerFixture();
  try {
    await controller.load(ContentDetailKind.ANSWER, '1');
    const original = controller.snapshot().content;
    assert.equal(typeof controller.prepareAnswer, 'function', 'restore preparation API');
    repository.fail = true;
    assert.equal(await controller.prepareAnswer('2'), undefined);
    assert.deepEqual(controller.snapshot().content, original);
    assert.equal(controller.snapshot().phase, 'ready');
  } finally { controller.deactivate(); }
});
contract('candidate-commits-once-and-admits-both-neighbors', false, async () => {
  const {controller} = controllerFixture();
  try {
    await controller.load(ContentDetailKind.ANSWER, '1');
    assert.equal(typeof controller.admitAnswer, 'function', 'restore admission API');
    const previous = controller.admitAnswer(answer('2'));
    const next = controller.admitAnswer(answer('3'));
    assert(previous && next);
    // 前后两答同时处于只读准备态：另一邻答登记完成不得让本次目标失效。
    assert.equal(controller.canCommitPreparedAnswer(previous), true);
    assert.equal(controller.commitPreparedAnswer(next), true);
    assert.equal(controller.snapshot().content.value.id, '3');
    assert.equal(controller.commitPreparedAnswer(next), false);
    // 离开的正文仍是登记态，回退时原样提交（正文代次不变，实例键不重建）。
    assert.equal(controller.commitPreparedAnswer(previous), true);
    assert.equal(controller.snapshot().content.value.id, '2');
    const departed = controller.admitAnswer(answer('4'));
    controller.deactivate(); controller.activate();
    assert.equal(controller.commitPreparedAnswer(departed), false);
  } finally { controller.deactivate(); }
});
contract('non-entry-answer-restores-its-own-position', false, () => {
  const saved = {blockIndex: 4, fraction: 0.5};
  const keys = [];
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'prepareReaderPosition', {
    getAbilityContext: () => ({}), createReaderPositionStore: () => ({load: key => {keys.push(key); return saved;}}),
    readerPositionBlockIndex: () => 4
  });
  const document = new Harness();
  Object.assign(document, {positionIsActive: () => true, readingLayout: true, empty: false,
    positionKey: 'answer:2', positionOwnerKey: 'answer:1', blocks: []});
  document.prepareReaderPosition();
  assert.deepEqual(keys, ['answer:2']);
  assert.equal(document.pendingPosition, saved);
  assert.equal(document.positionWritable, false, 'do not overwrite saved progress before restoration');
});
contract('independent-prefetch-does-not-block-foreground', false, async () => {
  const {ZhihuHttpClient} = load('data/src/main/ets/network/ZhihuHttpClient.ets');
  const {DefaultContentRepository} = load('data/src/main/ets/repository/DefaultContentRepository.ets');
  // Use Index's actual repository wiring: shared on PR, isolated after factory restoration.
  const index = read(pages + 'Index.ets');
  let finish;
  const cookies = {getCookies: () => [{name: 'd_c0', value: 'test'}]};
  // Execute the actual repository construction statements, not a hand-written alternative wiring.
  const foregroundStatement = index.match(/this\.answerRepository = new DefaultContentRepository[^;]+;/)?.[0];
  assert(foregroundStatement, 'Index answer repository wiring missing');
  const factoryStatement = index.match(/this\.answerPrefetchRepositoryFactory = \(\): ContentRepository =>[\s\S]*?;/)?.[0] ?? '';
  let requestCount = 0;
  class HarnessClient extends ZhihuHttpClient {
    constructor(session) {
      super(session, {create: () => ({request: () => {
        requestCount++;
        if (requestCount === 1) return new Promise(resolve => {finish = resolve;});
        return Promise.resolve({statusCode: 200, body: JSON.stringify(answer('1'))});
      }, destroy() {}})});
    }
  }
  const Wiring = vm.runInNewContext(compile('class Wiring { constructor() {' +
    foregroundStatement + factoryStatement + '} }') + '\nWiring',
    {DefaultContentRepository, ZhihuHttpClient: HarnessClient, session: cookies});
  const wiring = new Wiring();
  const foreground = wiring.answerRepository;
  const background = wiring.answerPrefetchRepositoryFactory?.() ?? foreground;
  const pending = background.getAnswer('2');
  // Handle rejection immediately so a failed assertion never leaves an unhandled promise.
  const result = foreground.getAnswer('1').then(value => ({value}), error => ({error}));
  await Promise.resolve();
  finish({statusCode: 200, body: JSON.stringify(answer('2'))});
  await pending;
  const response = await result;
  assert.equal(response.error, undefined, 'foreground must not fail BUSY while neighbor is fetching');
  assert.equal(response.value.id, '1');
});
contract('navigation-prepare-and-peek-do-not-advance-or-fetch', false, async () => {
  const {QuestionAnswerNavigator} = load(pages + 'QuestionAnswerNavigator.ets');
  let calls = 0;
  const seed = {phase: 'ready', items: ['1', '2'].map(id => ({feedItem: {target: answer(id)}})),
    loadingMore: false, canLoadMore: true, sortOrder: 'default', errorMessage: '', requiresLogin: false, nextCursor: 'next'};
  const navigator = new QuestionAnswerNavigator('123', '1', seed, {cancel() {}, getPage: async () => {calls++; throw Error('unexpected paging');}});
  try {
    assert.equal(typeof navigator.prepareMove, 'function', 'restore navigation preparation');
    assert.equal(await navigator.prepareMove(1), '2');
    assert.equal(navigator.currentId(), '1');
    assert.equal(navigator.peekId(1), '2');
    assert.equal(navigator.peekId(-1), undefined);
    assert.equal(calls, 0);
  } finally { navigator.dispose(); }
});
contract('prefetch-queue-deduplicates-prioritizes-and-drops-late-results', false, async () => {
  const file = pages + 'AnswerSwitchPrefetch.ets';
  assert(fs.existsSync(path.join(root, file)), 'restore independent prefetcher');
  const {AnswerDetailPrefetcher, ANSWER_PREFETCH_CAPACITY} = load(file);
  const requests = [], pending = [];
  let cancelled = 0;
  const repository = {getAnswer: id => {requests.push(id); return new Promise((resolve, reject) =>
    pending.push({id, resolve, reject}));}, cancel() {cancelled++;}};
  const prefetcher = new AnswerDetailPrefetcher(repository);
  const tick = () => new Promise(resolve => setTimeout(resolve, 0));
  const resolveNext = () => {const item = pending.shift(); item.resolve(answer(item.id));};
  try {
    const first = prefetcher.request('2', false);
    const duplicate = prefetcher.request('2', false);
    const behind = prefetcher.request('3', false);
    await tick();
    assert.deepEqual(requests, ['2']);
    const foreground = prefetcher.request('4', true);
    resolveNext(); await tick();
    assert.deepEqual(requests, ['2', '4']);
    resolveNext(); await tick(); resolveNext();
    assert.equal((await first).id, '2'); assert.equal((await duplicate).id, '2');
    assert.equal((await foreground).id, '4'); assert.equal((await behind).id, '3');
    for (let i = 5; i < 5 + ANSWER_PREFETCH_CAPACITY; i++) {
      const task = prefetcher.request(String(i), false); await tick(); resolveNext(); await task;
    }
    assert.equal(prefetcher.cacheSize(), ANSWER_PREFETCH_CAPACITY);
    assert.equal(prefetcher.peek('2'), undefined);
    const failed = prefetcher.request('99', false); await tick(); pending.shift().reject(Error('network'));
    assert.equal(await failed, undefined); assert.equal(prefetcher.peek('99'), undefined);
    const late = prefetcher.request('100', false); await tick(); prefetcher.reset(); resolveNext();
    assert.equal(await late, undefined); assert.equal(prefetcher.cacheSize(), 0); assert(cancelled > 0);
    prefetcher.dispose(); prefetcher.dispose();
    assert.equal(await prefetcher.request('101', true), undefined);
  } finally { prefetcher.dispose(); }
});
contract('cancelled-candidate-does-not-write-progress', false, () => {
  let writes = 0;
  const saved = {blockIndex: 4, fraction: 0.5};
  const store = {load: () => saved, save: () => {writes++;}};
  const prepare = methodHarness(pages + 'NativeContentDocument.ets', 'prepareReaderPosition', {
    getAbilityContext: () => ({}), createReaderPositionStore: () => store, readerPositionBlockIndex: () => 4
  });
  const persist = methodHarness(pages + 'NativeContentDocument.ets', 'persistReaderPosition', {clearTimeout() {}});
  const document = new prepare();
  Object.assign(document, {positionIsActive: () => false, readingLayout: true, empty: false,
    positionKey: 'answer:2', positionOwnerKey: 'answer:1', blocks: [], positionSaveTimer: -1,
    captureReaderPosition: () => ({blockIndex: -1, fraction: 0})});
  document.prepareReaderPosition();
  persist.prototype.persistReaderPosition.call(document, true);
  assert.equal(writes, 0, 'candidate disposal must not overwrite target progress');
});
contract('name-resources-and-share-fallback-match-main', false, () => {
  for (const [file, key, value] of [
    ['AppScope/resources/base/element/string.json', 'app_name', '知乎++鸿蒙版'],
    ['entry/src/main/resources/base/element/string.json', 'EntryAbility_label', '知乎++鸿蒙版'],
    ['entry/src/main/resources/en_US/element/string.json', 'EntryAbility_label', 'Zhihu++HMOS']]) {
    assert.equal(JSON.parse(read(file)).string.find(item => item.name === key).value, value);
  }
  for (const name of ['AppShell', 'SystemUpdateSettingsPage']) {
    assert(read(pages + name + '.ets').includes("Text($r('app.string.EntryAbility_label'))"), name + ' must use localized resource');
  }
  const update = read(pages + 'SystemUpdateSettingsPage.ets');
  assert(update.includes("context.resourceManager.getStringSync($r('app.string.EntryAbility_label').id)"));
  assert(!update.includes('知乎++鸿蒙版'), 'download text must use resource too');
  for (const name of ['AppShell', 'SystemUpdateSettingsPage', 'ContentDetailPages', 'NativeContentDocument', 'PeoplePinDetailPages']) {
    assert(!read(pages + name + '.ets').includes('知乎Plus'), name);
  }
});
contract('same-id-favorite-query-drops-old-account-result', false, async () => {
  const pending = [];
  const Harness = methodHarness(pages + 'ContentDetailPages.ets', 'refreshContentFavoriteState',
    {SessionStatus: {AUTHENTICATED: 'authenticated'}, ContentDetailKind});
  const page = new Harness();
  Object.assign(page, {pageActive: true, kind: ContentDetailKind.ANSWER, activeContentId: '1',
    favoriteStateEpoch: 0, contentFavorited: false,
    session: {getState: () => ({status: 'authenticated'})},
    collectionRepository: {getContentCollections: () => new Promise(resolve => pending.push(resolve))}});
  page.refreshContentFavoriteState();
  page.favoriteStateEpoch++; // account invalidation
  page.refreshContentFavoriteState();
  pending[1]([{isFavorited: false}]); await Promise.resolve();
  pending[0]([{isFavorited: true}]); await Promise.resolve();
  assert.equal(page.contentFavorited, false);
});
const tick = () => new Promise(resolve => setTimeout(resolve, 0));
for (const entry of ['moveAnswer', 'commitAnswerSwitch-horizontal', 'commitAnswerSwitch-vertical']) {
  contract('entry-' + entry + '-commits-only-after-preparation-and-animation', false, async () => {
    let finish;
    const background = {getAnswer: id => new Promise(resolve => {finish = () => resolve(answer(id));}), cancel() {}};
    const fixture = pageFixture(undefined, background);
    let land;
    try {
      await fixture.controller.load(ContentDetailKind.ANSWER, '1');
      fixture.page.answerSwitchMode = entry.endsWith('vertical') ? 'vertical' : 'horizontal';
      fixture.page.animateOverscrollTo = () => new Promise(resolve => {land = resolve;});
      const moving = entry === 'moveAnswer' ? fixture.page.moveAnswer(1) : fixture.page.commitAnswerSwitch(false);
      await tick();
      assert.equal(fixture.page.activeContentId, '1');
      assert.equal(fixture.navigator.currentId(), '1');
      assert.deepEqual(fixture.opened, ['answer:1']);
      finish(); await tick();
      assert.equal(fixture.controller.snapshot().content.value.id, '1');
      assert.equal(fixture.voteDeactivated(), false);
      land(); await moving;
      assert.equal(fixture.page.activeContentId, '2');
      assert.equal(fixture.navigator.currentId(), '2');
      assert.equal(fixture.controller.snapshot().content.value.id, '2');
      assert.equal(fixture.voteDeactivated(), true);
      assert.deepEqual(fixture.opened, ['answer:1', 'answer:2']);
    } finally {fixture.dispose();}
  });
}
contract('account-or-page-invalidation-rejects-late-answer', false, async () => {
  let finish;
  const background = {getAnswer: id => new Promise(resolve => {finish = () => resolve(answer(id));}), cancel() {}};
  const fixture = pageFixture(undefined, background);
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    const moving = fixture.page.applyAnswerMove(1); await tick();
    fixture.page.onLoginChanged();
    finish();
    assert.equal(await moving, false);
    assert.equal(fixture.page.activeContentId, '1');
    assert.equal(fixture.navigator.currentId(), '1');
    assert.equal(fixture.controller.snapshot().content.value.id, '1');
    assert.deepEqual(fixture.opened, ['answer:1', 'answer:1']); // account reload of current answer is allowed
    assert.equal(fixture.page.answerPrefetcher.peek('2'), undefined);
  } finally {fixture.dispose();}
});
contract('cancel-during-animation-cannot-commit-or-clear-new-transaction', false, async () => {
  const fixture = pageFixture();
  let land;
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.animateOverscrollTo = () => new Promise(resolve => {land = resolve;});
    const old = fixture.page.applyAnswerMove(1); await tick();
    fixture.page.invalidateAnswerSwitch();
    fixture.page.navigatorBusy = true; // represents a newer transaction owning the lock
    land(); assert.equal(await old, false);
    assert.equal(fixture.page.navigatorBusy, true);
    assert.equal(fixture.navigator.currentId(), '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('vote-or-thanks-invalidates-prepared-and-cached-snapshots', false, async () => {
  const fixture = pageFixture(undefined, {getAnswer: async id => answer(id), cancel() {}});
  let land;
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    await fixture.page.answerPrefetcher.request('2', false);
    fixture.page.animateOverscrollTo = () => new Promise(resolve => {land = resolve;});
    const old = fixture.page.applyAnswerMove(1); await tick();
    fixture.page.applyVoteState({pending: true});
    land(); assert.equal(await old, false);
    assert.equal(fixture.page.answerPrefetcher.cacheSize(), 0);
    fixture.page.applyVoteState({pending: false});
    assert.equal(fixture.page.answerPrefetcher.cacheSize(), 0);
    assert.equal(fixture.navigator.currentId(), '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('current-history-completion-survives-candidate-cancellation', false, async () => {
  let finish;
  const controller = new ContentDetailController({getAnswer: async id => answer(id), cancel() {}},
    {upsert: () => new Promise(resolve => {finish = resolve;})});
  controller.activate();
  try {
    const loading = controller.load(ContentDetailKind.ANSWER, '1'); await tick();
    const candidate = controller.admitAnswer(answer('2'));
    controller.cancelPreparedAnswer();
    finish(); await loading;
    assert.equal(controller.snapshot().openedRecordPhase, 'recorded');
    assert.equal(controller.commitPreparedAnswer(candidate), false);
  } finally {controller.deactivate();}
});
contract('viewport-lost-during-animation-keeps-current-identity', false, async () => {
  const fixture = pageFixture();
  let land;
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.animateOverscrollTo = target => target === 0 ? Promise.resolve() : new Promise(resolve => {land = resolve;});
    const moving = fixture.page.applyAnswerMove(1); await tick();
    fixture.page.answerViewportWidthVp = 0;
    land(); assert.equal(await moving, false);
    assert.equal(fixture.navigator.currentId(), '1');
    assert.equal(fixture.page.activeContentId, '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('animation-and-toast-errors-release-transaction-without-changing-identity', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.animateOverscrollTo = async () => {throw Error('window lost');};
    fixture.page.getUIContext = () => {throw Error('window lost');};
    assert.equal(await fixture.page.applyAnswerMove(1), false);
    assert.equal(fixture.page.navigatorBusy, false);
    assert.equal(fixture.navigator.currentId(), '1');
    assert.equal(fixture.page.activeContentId, '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('unavailable-viewport-and-cancellation-do-not-commit', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.answerViewportWidthVp = 0;
    const moving = fixture.page.applyAnswerMove(1); await tick();
    assert.equal(fixture.navigator.currentId(), '1');
    fixture.page.finishAnswerViewportWait(false);
    assert.equal(await moving, false);
    assert.equal(fixture.messages[0], '回答正文准备超时，请重试');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
for (const mode of ['horizontal', 'vertical']) {
  contract('real-candidate-' + mode + '-waits-for-both-signals-and-retains-key', false, async () => {
    const fixture = pageFixture();
    try {
      await fixture.controller.load(ContentDetailKind.ANSWER, '1');
      fixture.page.automaticallyPrepareCandidate = false;
      fixture.page.answerSwitchMode = mode;
      let animations = 0;
      fixture.page.animateOverscrollTo = async target => {if (target !== 0) animations++;};
      const moving = fixture.page.applyAnswerMove(1); await tick();
      const departed = fixture.page.content;
      const candidate = fixture.page.candidatePane();
      const key = fixture.page.answerDocumentKey(candidate);
      fixture.page.answerOverscrollOffset = -100;
      const position = fixture.page.answerPaneTranslate(candidate);
      assert.equal(mode === 'horizontal' ? position.x : position.y, (mode === 'horizontal' ? 360 : 800) - 100);
      fixture.page.onAnswerViewportPrepared(candidate, true); await tick();
      assert.equal(animations, 0, 'viewport alone cannot start landing');
      assert.equal(fixture.page.activeContentId, '1');
      fixture.page.onAnswerDocumentPrepared(candidate); await moving;
      assert.equal(animations, 1);
      // 提交后离开的正文保留为反方向邻答（实例键不重建），整页集合因此是两份。
      assert.equal(fixture.page.answerPanes.length, 2);
      assert.equal(fixture.page.answerPanes[0], departed, 'departed body must be retained as previous pane');
      assert.equal(fixture.page.answerNeighborPanes.get(-1), departed);
      assert.equal(fixture.page.answerDocumentKey(candidate), key);
      assert.equal(fixture.page.answerPaneDirection(candidate), 0);
      assert.equal(fixture.controller.snapshot().content.value.id, '2');
      assert.equal(fixture.controller.snapshot().content.loadGeneration, candidate.loadGeneration);
    } finally {fixture.dispose();}
  });
}
contract('previous-answer-preview-uses-the-retained-body-and-commits-back', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    // 当前正文在真实渲染中由 NativeContentDocument 回报解析与视口就绪，这里等价地补上。
    fixture.page.measureAnswerIdentity(fixture.page.content, {height: 100});
    fixture.page.onAnswerViewportPrepared(fixture.page.content, true);
    fixture.page.onAnswerDocumentPrepared(fixture.page.content);
    assert.equal(await fixture.page.applyAnswerMove(1), true);
    assert.equal(fixture.page.activeContentId, '2');
    // A → B 后 A 的正文实例保留为上一答：代次与实例键都不应变化。
    const retained = fixture.page.answerNeighborPanes.get(-1);
    assert(retained, 'departed body must stay mounted as previous answer');
    const retainedKey = fixture.page.answerDocumentKey(retained);
    const retainedGeneration = retained.loadGeneration;
    assert.equal(retained.value.id, '1');
    assert.equal(fixture.page.answerPaneDirection(retained), -1);
    // 上一答从切换轴另一侧进入：正偏移时位移为 d - E。
    fixture.page.answerOverscrollOffset = 120;
    const position = fixture.page.answerPaneTranslate(retained);
    assert.equal(fixture.page.answerSwitchMode === 'horizontal' ? position.x : position.y, 120 - 360);
    fixture.page.answerOverscrollOffset = 0;
    const prepared = await fixture.page.prepareSwitchAnswer('1', -1, fixture.page.answerSwitchEpoch);
    assert.equal(prepared, retained, 'preview must reuse the retained instance instead of refetching');
    assert.equal(await fixture.page.applyAnswerMove(-1), true);
    assert.equal(fixture.page.activeContentId, '1');
    assert.equal(fixture.controller.snapshot().content.value.id, '1');
    assert.equal(fixture.controller.snapshot().content.loadGeneration, retainedGeneration);
    assert.equal(fixture.page.answerDocumentKey(fixture.page.content), retainedKey);
    // 离开的 B 反过来成为下一答，方向与实例键同样保持。
    assert.equal(fixture.page.answerNeighborPanes.get(1).value.id, '2');
  } finally {fixture.dispose();}
});
contract('candidate-ready-callback-after-cancellation-cannot-unblock-another-instance', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.automaticallyPrepareCandidate = false;
    const cancelled = fixture.page.applyAnswerMove(1); await tick();
    const old = fixture.page.candidatePane();
    fixture.page.invalidateAnswerSwitch(); assert.equal(await cancelled, false);
    const retry = fixture.page.applyAnswerMove(1); await tick();
    const fresh = fixture.page.candidatePane();
    fixture.page.onAnswerDocumentPrepared(old); fixture.page.onAnswerViewportPrepared(old, true);
    await tick();
    assert.equal(fixture.page.activeContentId, '1');
    assert.notEqual(fixture.page.answerDocumentKey(old), fixture.page.answerDocumentKey(fresh));
    fixture.page.onAnswerDocumentPrepared(fresh); fixture.page.onAnswerViewportPrepared(fresh, true);
    assert.equal(await retry, true);
    assert.equal(fixture.page.activeContentId, '2');
  } finally {fixture.dispose();}
});
contract('native-viewport-ready-waits-for-position-restoration-and-invalidates-on-zero-area', false, () => {
  const events = [];
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'reportViewportPrepared');
  const document = new Harness();
  Object.assign(document, {positionMounted: true, headerHasLayout: true, viewportWidthVp: 360,
    viewportHeightVp: 800, viewportPreparedReported: false, pendingPosition: {blockIndex: 4},
    positionPreparationFailed: false, onViewportPrepared: ready => events.push(ready), requestDocumentFocus() {}});
  document.reportViewportPrepared(); assert.deepEqual(events, []);
  document.pendingPosition = undefined; document.reportViewportPrepared(); assert.deepEqual(events, [true]);
  document.viewportWidthVp = 0; document.reportViewportPrepared(); assert.deepEqual(events, [true, false]);
});
contract('candidate-page-turn-never-consumes-input-or-writes-progress', false, () => {
  let turns = 0;
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'turnPage');
  const document = new Harness();
  Object.assign(document, {answerDocumentKey: 'candidate:2', positionIsActive: () => false,
    cancelPositionRestore() {throw Error('candidate must not cancel restoration');},
    onPageTurnPastStart() {turns++;}, onPageTurnPastEnd() {turns++;}});
  document.turnPage(1); document.turnPage(-1); assert.equal(turns, 0);
});
contract('native-candidate-activation-keeps-restored-position-and-takes-focus-once', false, async () => {
  let active = false, focus = 0, metadata = 0, restores = 0;
  const names = ['onPositionActiveChanged', 'requestDocumentFocus'];
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', names[0]);
  Harness.prototype.requestDocumentFocus = methodHarness(pages + 'NativeContentDocument.ets', names[1], {setTimeout, clearTimeout}).prototype.requestDocumentFocus;
  const document = new Harness();
  Object.assign(document, {positionMounted: true, positionWasActive: false, positionEverActive: false,
    answerDocumentKey: 'candidate:2', positionIsActive: () => active, pendingPosition: undefined,
    viewportPreparedReported: true, volumeKeyPageTurn: true, focusRequested: false, focusRequestTimer: -1, focusRequestAttempts: 0,
    documentFocusId: 'native:2', scrollYVp: 300, loadLinkCardMetas() {metadata++; this.linkCardMetaLoader = {};},
    schedulePositionRestore() {if (this.pendingPosition !== undefined) restores++;},
    getUIContext: () => ({getFocusController: () => ({requestFocus() {focus++; document.focusRequested = true;}})})});
  document.onPositionActiveChanged(); assert.equal(focus, 0); assert.equal(metadata, 0);
  active = true; document.onPositionActiveChanged(); document.onPositionActiveChanged();
  await new Promise(resolve => setTimeout(resolve, 70));
  assert.equal(focus, 1); assert.equal(metadata, 1); assert.equal(restores, 0);
  assert.equal(document.scrollYVp, 300); assert.equal(document.positionEverActive, true);
});
contract('disposing-one-native-document-keeps-shared-formula-cache-for-survivors', false, () => {
  let mounted = 0, clears = 0, parses = 0;
  const globals = () => {
    const context = {clearTimeout, console: {info() {}}, clearFormulaByteCache: () => {clears++;},
      parseZhihuHtml: () => {parses++; return [];}};
    Object.defineProperty(context, 'mountedNativeDocuments', {get: () => mounted, set: value => {mounted = value;}});
    return context;
  };
  const appear = methodHarness(pages + 'NativeContentDocument.ets', 'aboutToAppear', globals());
  const disappear = methodHarness(pages + 'NativeContentDocument.ets', 'aboutToDisappear', globals());
  const make = key => {
    const document = new appear();
    Object.assign(document, {registeredDocument: false, html: '', answerDocumentKey: key,
      previousBlocks: new Map(), dataSource: {replace() {}}, positionIsActive: () => false,
      prepareReaderPosition() {}, positionWasActive: false, reportViewportPrepared() {},
      positionRestoreTimer: -1, positionSaveTimer: -1});
    return document;
  };
  const current = make('1:1'), candidate = make('2:2');
  current.aboutToAppear(); candidate.aboutToAppear();
  assert.equal(mounted, 2); assert.equal(parses, 2);
  disappear.prototype.aboutToDisappear.call(candidate); assert.equal(mounted, 1); assert.equal(clears, 0);
  disappear.prototype.aboutToDisappear.call(current); assert.equal(mounted, 0); assert.equal(clears, 1);
  disappear.prototype.aboutToDisappear.call(current); assert.equal(clears, 1);
});
contract('hidden-answer-page-cannot-publish-active-document-or-start-switch', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.publishActiveAnswerDocument();
    const published = fixture.broadcasts.length;
    assert(published > 0, 'visible page must publish its document identity');
    fixture.page.readerVisibleOwner = 'answer:other-page';
    fixture.page.publishActiveAnswerDocument();
    assert.equal(fixture.broadcasts.length, published);
    assert.equal(fixture.page.answerPageVisible(), false);
    assert.equal(fixture.page.isDisplayedContent(fixture.page.content), false);
    assert.equal(await fixture.page.applyAnswerMove(1), false);
    assert.equal(fixture.navigator.currentId(), '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('route-owner-change-cancels-candidate-awaiting-layout', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.automaticallyPrepareCandidate = false;
    const moving = fixture.page.applyAnswerMove(1); await tick();
    const candidate = fixture.page.candidatePane();
    fixture.page.readerVisibleOwner = 'answer:other-page';
    fixture.page.onReaderOwnerChanged();
    fixture.page.onAnswerDocumentPrepared(candidate); fixture.page.onAnswerViewportPrepared(candidate, true);
    assert.equal(await moving, false);
    assert.equal(fixture.page.navigatorBusy, false);
    assert.equal(fixture.page.activeContentId, '1');
    assert.deepEqual(fixture.opened, ['answer:1']);
  } finally {fixture.dispose();}
});
contract('volume-key-release-turns-once-and-candidate-never-consumes-it', false, () => {
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'handleReaderKey', {KeyType: {Down: 0, Up: 1}});
  const document = new Harness();
  const turns = [];
  let active = true;
  Object.assign(document, {volumeKeyPageTurn: true, answerDocumentKey: 'b:2', positionIsActive: () => active,
    turnPage: direction => turns.push(direction)});
  assert.equal(document.handleReaderKey({keyCode: 17, type: 0}), true);
  assert.deepEqual(turns, []);
  assert.equal(document.handleReaderKey({keyCode: 17, type: 1}), true);
  assert.deepEqual(turns, [1]);
  assert.equal(document.handleReaderKey({keyCode: 16, type: 1}), true); // device sends release only
  assert.deepEqual(turns, [1, -1]);
  active = false;
  assert.equal(document.handleReaderKey({keyCode: 17, type: 0}), false);
  assert.equal(document.handleReaderKey({keyCode: 17, type: 1}), false);
  assert.deepEqual(turns, [1, -1]);
});
contract('hidden-page-defers-account-refresh-until-its-route-is-visible', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.readerVisibleOwner = 'answer:another-page';
    fixture.page.onLoginChanged(); await tick();
    assert.equal(fixture.page.sessionReloadPending, true);
    assert.deepEqual(fixture.opened, ['answer:1']);
    fixture.page.readerVisibleOwner = 'answer:1';
    fixture.page.onReaderOwnerChanged(); await tick();
    assert.equal(fixture.page.sessionReloadPending, false);
    assert.deepEqual(fixture.opened, ['answer:1', 'answer:1']);
  } finally {fixture.dispose();}
});
contract('candidate-viewport-waits-for-identity-measurement-before-title-handoff', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.automaticallyMeasureCandidate = false;
    const switching = fixture.page.applyAnswerMove(1); await tick();
    const candidate = fixture.page.candidatePane();
    assert(candidate); assert.equal(fixture.page.answerPanePreparation.ready(fixture.page.answerDocumentKey(candidate)), false);
    assert.equal(fixture.page.activeContentId, '1');
    fixture.page.measureAnswerIdentity(candidate, {height: 100});
    assert.equal(await switching, true); assert.equal(fixture.page.activeContentId, '2');
  } finally {fixture.dispose();}
});
contract('title-mode-change-invalidates-candidate-until-its-identity-is-remeasured', false, async () => {
  const fixture = pageFixture();
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    const candidate = await fixture.page.prepareSwitchAnswer('2', 1, fixture.page.answerSwitchEpoch); await tick();
    const key = fixture.page.answerDocumentKey(candidate);
    assert.equal(fixture.page.answerPanePreparation.ready(key), true);
    fixture.page.questionInTitleBar = true; fixture.page.onAnswerTitleLayoutChanged();
    assert.equal(fixture.page.answerPanePreparation.ready(key), false);
    fixture.page.measureAnswerIdentity(candidate, {height: 40});
    assert.equal(fixture.page.answerPanePreparation.ready(key), true);
  } finally {fixture.dispose();}
});
contract('title-publishes-route-key-with-candidate-geometry-and-committed-identity', false, async () => {
  const fixture = pageFixture({getAnswer: async id => ({...answer(id), questionTitle: 'question', author: {name: 'author-' + id}}), cancel() {}});
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    const original = fixture.page.content;
    fixture.page.measureAnswerIdentity(original, {height: 100});
    fixture.page.updateAnswerTitleScrolled(original, 150);
    assert.equal(fixture.broadcasts.at(-1).value.authorVisible, true);
    const candidate = await fixture.page.prepareSwitchAnswer('2', 1, fixture.page.answerSwitchEpoch);
    fixture.page.measureAnswerIdentity(candidate, {height: 160});
    fixture.page.trackAnswerPaneViewport(candidate, 80);
    assert.equal(fixture.broadcasts.at(-1).value.activeAnswerId, '1');
    assert.equal(await fixture.page.applyAnswerMove(1), true);
    const committed = fixture.broadcasts.filter(item => item.key === 'answerTitle').at(-1).value;
    assert.equal(committed.id, '1'); assert.equal(committed.activeAnswerId, '2');
    assert.equal(committed.authorName, 'author-2'); assert.equal(committed.authorVisible, false);
    fixture.page.updateAnswerTitleScrolled(original, 1000);
    assert.equal(fixture.broadcasts.filter(item => item.key === 'answerTitle').at(-1).value, committed);
  } finally {fixture.dispose();}
});
contract('layout-change-updates-title-without-scroll-and-rejects-pruned-generation', false, async () => {
  const fixture = pageFixture({getAnswer: async id => ({...answer(id), author: {name: 'author'}}), cancel() {}});
  try {
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    const original = fixture.page.content;
    fixture.page.measureAnswerIdentity(original, {height: 60});
    fixture.page.updateAnswerTitleScrolled(original, 100);
    assert.equal(fixture.broadcasts.at(-1).value.authorVisible, true);
    fixture.page.measureAnswerIdentity(original, {height: 150});
    assert.equal(fixture.broadcasts.at(-1).value.authorVisible, false);
    await fixture.controller.load(ContentDetailKind.ANSWER, '1');
    fixture.page.updateAnswerTitleScrolled(fixture.page.content, 200);
    fixture.page.measureAnswerIdentity(original, {height: 1});
    fixture.page.updateAnswerTitleScrolled(original, 1000);
    assert.equal(fixture.broadcasts.at(-1).value.authorVisible, false);
    fixture.page.measureAnswerIdentity(fixture.page.content, {height: 100});
    assert.equal(fixture.broadcasts.at(-1).value.authorVisible, true);
  } finally {fixture.dispose();}
});
const preferencesSource = ts.createSourceFile('preferences.ets', read('data/src/main/ets/preferences/AppPreferencesStore.ets'), ts.ScriptTarget.Latest, true);
const preferenceNames = new Set(['AnswerSwitchMode', 'ShareActionMode', 'defaultExperiencePreferences', 'normalizeExperiencePreferences', 'normalizeBottomBarItems']);
const preferencesModule = {exports: {}};
vm.runInNewContext(compile(preferencesSource.statements.filter(node => preferenceNames.has(node.name?.text)).map(node => node.getFullText(preferencesSource)).join('\n')), {exports: preferencesModule.exports});
contract('old-and-invalid-title-preferences-load-defaults-and-existing-booleans-survive', false, async () => {
  let saved = {};
  const Harness = methodHarness('data/src/main/ets/preferences/AppPreferencesStore.ets', 'loadExperiencePreferences', {
    ...preferencesModule.exports, PREFERENCES_NAME: 'test', preferences: {getPreferences: async () => ({get: async (key, fallback) => saved[key] ?? fallback})}
  });
  const store = new Harness(); store.saveQueue = Promise.resolve();
  let value = await store.loadExperiencePreferences();
  assert.equal(value.questionInTitleBar, false); assert.equal(value.titleAutoHide, false);
  saved = {questionInTitleBar: 'true', titleAutoHide: 1}; value = await store.loadExperiencePreferences();
  assert.equal(value.questionInTitleBar, false); assert.equal(value.titleAutoHide, false);
  for (const questionInTitleBar of [false, true]) for (const titleAutoHide of [false, true]) {
    saved = {questionInTitleBar, titleAutoHide}; value = await store.loadExperiencePreferences();
    assert.equal(value.questionInTitleBar, questionInTitleBar); assert.equal(value.titleAutoHide, titleAutoHide);
  }
});
contract('answer-identity-change-does-not-animate-through-old-author', false, () => {
  let animations = 0;
  const Harness = methodHarness(pages + 'AnswerTitleBar.ets', 'onStatesChanged', {Curve: {EaseInOut: 0}});
  const bar = new Harness();
  let state = {documentKey: 'a:1', scrolled: true, authorVisible: true};
  Object.assign(bar, {documentKey: 'a:1', folded: true, authorVisible: true, state: () => state,
    getUIContext: () => ({animateTo: (_, apply) => {animations++; apply();}})});
  state = {documentKey: 'b:2', scrolled: false, authorVisible: false}; bar.onStatesChanged();
  assert.equal(bar.folded, false); assert.equal(bar.authorVisible, false); assert.equal(animations, 0);
  state = {...state, scrolled: true, authorVisible: true}; bar.onStatesChanged();
  assert.equal(bar.folded, true); assert.equal(bar.authorVisible, true); assert.equal(animations, 1);
});

contract('reader-focus-scope-is-independent-of-volume-setting-and-excludes-candidates', false, () => {
  const Harness = methodHarness(pages + 'NativeContentDocument.ets', 'documentCanFocus');
  const document = new Harness();
  Object.assign(document, {answerDocumentKey: 'a:1', positionIsActive: () => true, volumeKeyPageTurn: false});
  assert.equal(document.documentCanFocus(), true);
  document.positionIsActive = () => false;
  assert.equal(document.documentCanFocus(), false);
  document.answerDocumentKey = '';
  assert.equal(document.documentCanFocus(), true);
});
const {HotCommentController, HotCommentPhase} = load(pages + 'HotCommentState.ets');
const {commentImageUrls, stripCommentHtml} = load(pages + 'CommentText.ets');
function hotFixture() {
  const requests = [];
  const controller = new HotCommentController(() => {
    const deferred = {};
    const result = new Promise((resolve, reject) => Object.assign(deferred, {resolve, reject}));
    const request = {id: '', cancelled: 0, getRootCommentsPage: (kind, id, sort) => {
      assert.equal(kind, 'answer'); assert.equal(sort, 'score'); request.id = id; return result;
    }, cancel() {request.cancelled++;}, ...deferred};
    requests.push(request); return request;
  }, () => {});
  return {controller, requests};
}
const commentPage = items => ({items, cursor: {isEnd: true, isStart: true, page: 1, total: items.length}});
const hotComment = (id, contentHtml = '<p>text[赞同]</p>') => ({id, contentHtml, likeCount: 3, isDelete: false, collapsed: false});
contract('hot-comments-failure-retry-empty-and-success-are-distinct', false, async () => {
  const f = hotFixture();
  const failed = f.controller.load('1', '1:1', 'user');
  assert.equal(f.controller.snapshot().phase, HotCommentPhase.LOADING);
  f.requests[0].reject(Error('offline')); await failed;
  assert.equal(f.controller.snapshot().phase, HotCommentPhase.ERROR);
  const retry = f.controller.load('1', '1:1', 'user', true);
  f.requests[1].resolve(commentPage([])); await retry;
  assert.equal(f.controller.snapshot().phase, HotCommentPhase.EMPTY);
  const refresh = f.controller.load('1', '1:2', 'user');
  f.requests[2].resolve(commentPage([
    {...hotComment('zero'), likeCount: 0}, {...hotComment('deleted'), isDelete: true},
    hotComment('image', '<img src="https://pic1.zhimg.com/a.gif">'), hotComment('2'), hotComment('3'), hotComment('4')
  ])); await refresh;
  assert.equal(f.controller.snapshot().phase, HotCommentPhase.READY);
  assert.deepEqual(Array.from(f.controller.snapshot().comments, item => item.id), ['image', '2', '3']);
});
contract('hot-comments-old-A-and-old-account-cannot-replace-current-A', false, async () => {
  const f = hotFixture();
  const a1 = f.controller.load('1', '1:1', 'a');
  const b = f.controller.load('2', '2:1', 'a');
  const a2 = f.controller.load('1', '1:2', 'a');
  const account = f.controller.load('1', '1:2', 'b');
  f.requests[3].resolve(commentPage([hotComment('current')])); await account;
  f.requests[0].resolve(commentPage([hotComment('oldA')])); f.requests[1].reject(Error('oldB'));
  f.requests[2].resolve(commentPage([hotComment('oldAccount')])); await Promise.all([a1, b, a2]);
  assert.equal(f.controller.snapshot().comments[0].id, 'current');
  assert.deepEqual(f.requests.map(item => item.cancelled), [1, 1, 1, 0]);
});
contract('hot-comments-factory-failure-does-not-reject-page-or-look-empty', false, async () => {
  const controller = new HotCommentController(() => {throw Error('factory unavailable');}, () => {});
  await controller.load('1', '1:1', 'a');
  assert.equal(controller.snapshot().phase, HotCommentPhase.ERROR);
});
function hotPageFixture() {
  const f = pageFixture();
  const names = ['resetHotComments', 'refreshHotComments', 'onHotCommentsChanged'];
  const globals = {ContentDetailKind, HotCommentController};
  for (const name of names) f.page[name] = methodHarness(pages + 'ContentDetailPages.ets', name, {...globals}).prototype[name];
  const requests = [];
  Object.assign(f.page, {showHotComments: true, loginTick: 1,
    hotCommentRepositoryFactory() {
      const deferred = {}; const promise = new Promise((resolve, reject) => Object.assign(deferred, {resolve, reject}));
      const request = {cancelled: 0, cancel() {this.cancelled++;}, getRootCommentsPage: () => promise, ...deferred};
      requests.push(request); return request;
    }});
  return {...f, requests};
}
contract('hot-comment-page-toggle-and-hidden-route-discard-inflight-and-reopen-fresh', false, async () => {
  const f = hotPageFixture();
  try {
    await f.controller.load(ContentDetailKind.ANSWER, '1'); f.page.refreshHotComments(f.page.content);
    f.page.showHotComments = false; f.page.onHotCommentsChanged();
    f.requests[0].resolve(commentPage([hotComment('old')])); await tick();
    assert.equal(f.page.hotCommentState.phase, HotCommentPhase.IDLE);
    f.page.showHotComments = true; f.page.onHotCommentsChanged(); assert.equal(f.requests.length, 2);
    f.page.readerVisibleOwner = 'answer:another'; f.page.onReaderOwnerChanged();
    assert.equal(f.requests[1].cancelled, 1);
    f.requests[1].resolve(commentPage([hotComment('hidden')])); await tick();
    assert.equal(f.page.hotCommentState.phase, HotCommentPhase.IDLE);
    f.page.readerVisibleOwner = 'answer:1'; f.page.onReaderOwnerChanged(); assert.equal(f.requests.length, 3);
    f.requests[2].resolve(commentPage([])); await tick(); assert.equal(f.page.hotCommentState.phase, HotCommentPhase.EMPTY);
  } finally {f.page.resetHotComments(); f.dispose();}
});
contract('hot-comments-follow-only-committed-documents-and-refresh-on-same-id-generation', false, async () => {
  const f = hotPageFixture();
  try {
    await f.controller.load(ContentDetailKind.ANSWER, '1'); f.page.refreshHotComments(f.page.content);
    f.requests[0].resolve(commentPage([hotComment('first')])); await tick();
    f.page.refreshHotComments(f.page.content); assert.equal(f.requests.length, 1);
    const candidate = {...f.page.content, value: answer('2'), loadGeneration: 100};
    // Candidate events cannot issue IO or discard the committed preview.
    f.page.refreshHotComments(candidate); assert.equal(f.requests.length, 1);
    f.page.refreshHotComments(f.page.content); assert.equal(f.requests.length, 1);
    assert.equal(f.page.hotCommentState.comments[0].id, 'first');
    await f.controller.load(ContentDetailKind.ANSWER, '1'); f.page.refreshHotComments(f.page.content);
    assert.equal(f.requests.length, 2); assert.equal(f.page.hotCommentState.phase, HotCommentPhase.LOADING);
    f.page.onLoginChanged(); f.requests[1].resolve(commentPage([hotComment('oldAccount')])); await tick();
    assert.equal(f.page.hotCommentState.phase, HotCommentPhase.IDLE);
  } finally {f.page.resetHotComments(); f.dispose();}
});
contract('comment-text-keeps-unsupported-fallback-and-all-supported-images-in-order', false, () => {
  const html = '<img src="https://pic1.zhimg.com/a.png">文字[微笑]' +
    '<a class="comment_gif" href="https://pica.zhimg.com/b.gif">动图</a>' +
    '<a class="comment_img" href="https://example.com/c">查看原图</a><img src="bad" alt="图片说明">';
  assert.deepEqual(Array.from(commentImageUrls(html)), ['https://pic1.zhimg.com/a.png', 'https://pica.zhimg.com/b.gif']);
  assert.equal(stripCommentHtml(html), '文字[微笑]查看原图图片说明');
});


contract('feed-scroll-owner-ignores-hidden-feeds-and-resets-on-source-change', false, () => {
  const values = new Map(); global.AppStorage = {get: key => values.get(key), setOrCreate: (key, value) => values.set(key, value)};
  try {
    const {setFeedScrollOwner, publishFeedScroll} = load(pages + 'FeedScrollOwnership.ets');
    setFeedScrollOwner('home'); publishFeedScroll('home', 10); assert.equal(values.get('bottomBarHiddenByScroll'), true);
    setFeedScrollOwner('hot'); assert.equal(values.get('bottomBarHiddenByScroll'), false);
    publishFeedScroll('home', 20); assert.equal(values.get('bottomBarHiddenByScroll'), false);
    publishFeedScroll('hot', 20); assert.equal(values.get('bottomBarHiddenByScroll'), true);
    setFeedScrollOwner('hot'); assert.equal(values.get('bottomBarHiddenByScroll'), true);
    setFeedScrollOwner(''); publishFeedScroll('hot', 20); assert.equal(values.get('bottomBarHiddenByScroll'), false);
    setFeedScrollOwner('following'); publishFeedScroll('following-recommend', 20);
    assert.equal(values.get('bottomBarHiddenByScroll'), false);
  } finally {delete global.AppStorage;}
});
contract('tab-order-and-following-subtab-broadcast-stable-scroll-owner', false, () => {
  const values = new Map(); const owners = []; const TopLevelTab = {HOME:0,FOLLOWING:1,HOT:2,DAILY:3,HISTORY:4,COLLECTIONS:5,ACCOUNT:6};
  const H = methodHarness(pages + 'AppShell.ets', 'broadcastBottomBarScrollOwner', {
    TopLevelTab, setFeedScrollOwner: key => owners.push(key), AppStorage: {setOrCreate: (key,value) => values.set(key,value)}
  });
  const p = new H(); p.bottomBarOrder = [6,3,0,5,1,2,4]; p.topLevelTabIndex = 0;
  p.scrollKeysForTab = tab => [['home'],['recommend'],['hot'],['daily']][tab] || [];
  p.broadcastBottomBarScrollOwner(); assert.equal(owners.at(-1), ''); assert.equal(values.get('topLevelFeedTabActive'), false);
  p.topLevelTabIndex = 4; p.broadcastBottomBarScrollOwner(); assert.equal(owners.at(-1),'recommend');
  p.scrollKeysForTab = () => ['following']; p.broadcastBottomBarScrollOwner(); assert.equal(owners.at(-1),'following');
});
contract('progress-hide-cancels-drag-timers-and-waits-for-real-scroll-after-switch', false, () => {
  const file = pages + 'components/ReadingProgressBar.ets'; const cleared=[]; const notices=[];
  const H = methodHarness(file, 'resetBar');
  for (const name of ['onAvailabilityChanged', 'onBarInputChanged', 'notifySeekEnd']) {
    H.prototype[name] = methodHarness(file, name, { }).prototype[name];
  }
  const p = new H(); p.clearFadeTimer = () => cleared.push('fade'); p.clearUnmountTimer = () => cleared.push('unmount');
  p.dragging=true; p.alpha=1; p.mounted=true; p.seekNotified=true; p.onSeekStateChange = x => notices.push(x);
  p.onAvailabilityChanged(); assert.equal(p.dragging,false); assert.equal(p.mounted,false); assert.equal(p.alpha,0);
  assert.deepEqual(notices,[false]); assert.deepEqual(cleared,['fade','unmount']);
  p.active=true; p.switchActive=true; p.scrollable=()=>true; let shown=0;
  p.showBar=()=>shown++; p.scheduleFadeOut=()=>{}; p.onBarInputChanged(); assert.equal(shown,0);
  p.switchActive=false; p.onAvailabilityChanged(); assert.equal(shown,0); p.onBarInputChanged(); assert.equal(shown,1);
});
contract('window-listener-registration-failure-can-retry-and-old-window-event-is-inert', false, () => {
  const H = methodHarness('entry/src/main/ets/entryability/EntryAbility.ets', 'ensureAvoidAreaListener', {
    window:{AvoidAreaType:{TYPE_SYSTEM:0,TYPE_NAVIGATION_INDICATOR:1}}
  });
  const p=new H(); p.windowGeneration=1;p.avoidAreaListening=false;p.windowCleanup=[];
  const listeners=[]; let fails=true; let published=0; let logged=0;
  const w={on:(_event,callback)=>{if(fails)throw Error('1300002');listeners.push(callback);},off(){}};
  p.logWindowListenerFailure=()=>logged++;p.publishAvoidArea=()=>published++;
  p.ensureAvoidAreaListener(w,1); assert.equal(logged,1);assert.equal(p.avoidAreaListening,false);
  fails=false;p.ensureAvoidAreaListener(w,1);assert.equal(p.avoidAreaListening,true);assert.equal(p.windowCleanup.length,1);
  listeners[0]({type:0,area:{}});assert.equal(published,1);p.windowGeneration=2;
  listeners[0]({type:0,area:{}});assert.equal(published,1);
});
contract('zero-local-overscroll-reset-still-clears-global-transition-state', false, () => {
  const H=methodHarness(pages+'ContentDetailPages.ets','resetAnswerOverscroll');const p=new H();
  p.answerOverscrollOffset=0;p.overscrollRawDrag=0;const offsets=[];p.applyOverscrollOffset=x=>offsets.push(x);
  p.resetAnswerOverscroll(false);assert.deepEqual(offsets,[0]);
});


contract('bottom-actions-hit-only-visible-capsules-and-keep-child-buttons-enabled', false, () => {
  const H=methodHarness(pages+'ContentDetailPages.ets','bottomActionHitTest',{ContentDetailKind,HitTestMode:{None:0,Transparent:1,Default:2}});
  H.prototype.bottomActionAreaContains=methodHarness(pages+'ContentDetailPages.ets','bottomActionAreaContains').prototype.bottomActionAreaContains;
  const p=new H();p.pageActive=true;p.immersiveReading=false;p.kind=ContentDetailKind.ANSWER;p.answerOverscrollOffset=0;
  p.bottomActionLeftArea={globalPosition:{x:12,y:640},width:120,height:48};
  p.bottomActionRightArea={globalPosition:{x:300,y:640},width:140,height:48};
  const event=(x,y)=>({touches:[{windowX:x,windowY:y}]});
  assert.equal(p.bottomActionHitTest(event(50,650)),2);assert.equal(p.bottomActionHitTest(event(350,650)),2);
  assert.equal(p.bottomActionHitTest(event(200,650)),1);assert.equal(p.bottomActionHitTest(event(350,700)),1);
  assert.equal(p.bottomActionHitTest(event(350,500)),1);assert.equal(p.bottomActionHitTest({touches:[]}),1);
  p.answerOverscrollOffset=1;assert.equal(p.bottomActionHitTest(event(50,650)),0);
  p.answerOverscrollOffset=0;p.pageActive=false;assert.equal(p.bottomActionHitTest(event(50,650)),0);
});


contract('offscreen-identity-keeps-normal-title-measurement-across-immersive-mode', false, () => {
  const {AnswerTitleGeometry}=load(pages+'AnswerTitleGeometry.ets');const geometry=new AnswerTitleGeometry();
  geometry.measure('doc','body',180);assert.equal(geometry.resolve('doc','body',400,94,94,false,true).compact,true);
  geometry.measure('doc','immersive',40);geometry.resolve('doc','immersive',400,0,0,false,true);
  const restored=geometry.resolve('doc','body',400,94,94,false,true);
  assert.equal(restored.compact,true);assert.equal(restored.authorVisible,true);
  geometry.retain([]);assert.equal(geometry.measured('doc','body'),false);assert.equal(geometry.measured('doc','immersive'),false);
});

(async () => {
  let failed = 0;
  let selected = 0;
  const step3 = new Set(['non-entry-answer-restores-its-own-position', 'cancelled-candidate-does-not-write-progress']);
  for (const item of tests) {
    if (args.includes('--step2') && step3.has(item.name)) continue;
    selected++;
    try {
      await item.run();
      console.log('PASS ' + item.name);
      if (baseline && item.expectedDefect) { failed++; console.error('Baseline changed: remove resolved defect from expected list'); }
    } catch (error) {
      // Runtime/fixture errors are never accepted as a known regression.
      const known = baseline && item.expectedDefect && error.code === 'ERR_ASSERTION';
      console.log((known ? 'KNOWN-FAIL ' : 'FAIL ') + item.name + ': ' + error.message);
      if (!known) failed++;
    }
  }
  console.log('Selected ' + selected + ' contracts; failures: ' + failed + (args.includes('--step2') ? ' (step 3 document/position gates excluded)' : ''));
  console.log(baseline ? 'Baseline capture only; KNOWN-FAIL cases are unresolved acceptance gates.' : 'Acceptance run (all selected contracts must pass).');
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
