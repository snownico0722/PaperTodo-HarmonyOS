'use strict';
// Runs production ArkTS logic under explicit platform mocks. These assertions
// complement Hypium/ArkTS compilation; they do NOT simulate a device compositor.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');
const root = path.resolve(__dirname, '../../entry/src/main/ets');

function harness(options = {}) {
  const values = new Map();
  const cache = new Map();
  const events = [];
  const state = {
    useCapsuleMode: true, useDeepCapsuleMode: true, useMasterCapsule: true,
    showDeepCapsuleWhileExpanded: false, capsuleCollapseAllActive: false,
    capsuleStartTop: 48, capsuleGap: 4,
    papers: [{ id: 'p1', isVisible: true, isCollapsed: false, capsuleWidth: 108, alwaysOnTop: false }]
  };
  const storage = {
    get: k => values.get(k), setOrCreate: (k, v) => { values.set(k, v); return true; },
    delete: k => values.delete(k)
  };
  let Runtime;
  let flushIndex = 0;
  const store = {
    initialize() {}, refreshSystemLanguage() {}, loadState: () => state,
    listPapers: () => state.papers.slice(), getPaper: id => state.papers.find(p => p.id === id) || null,
    canPaperDisplayAsCapsule: () => true,
    listEdgeCapsulePapers: () => state.useCapsuleMode && state.useDeepCapsuleMode ? state.papers.filter(p =>
      p.isVisible && (p.isCollapsed || state.showDeepCapsuleWhileExpanded || Runtime.isPending(p.id))) : [],
    setPaperVisible(id, v) { const p = this.getPaper(id); if (p) p.isVisible = v; },
    setPaperCollapsed(id, v) { const p = this.getPaper(id); if (p) p.isCollapsed = v; },
    setCapsuleCollapseAllActive(v) { state.capsuleCollapseAllActive = v; },
    setCapsuleStartTop(v) { state.capsuleStartTop = v; },
    updatePaper() {},
    flushNow() { events.push('flush'); return (options.flushResults || [true])[flushIndex++] ?? true; }
  };
  const tray = {
    async remove() { events.push('remove-tray'); return true; },
    async install() { events.push('install-tray'); return true; }
  };
  const context = {
    config: { colorMode: 0 },
    async startAbility(want) {
      events.push(`${want.abilityName}:${want.parameters?.paperCommand || want.parameters?.capsuleCommand || ''}`);
      if (want.abilityName === 'MasterCapsuleAbility') {
        if (want.parameters.capsuleCommand === 'close') {
          Runtime.end('host'); storage.setOrCreate('masterCapsuleOpen', false); return;
        }
        if (options.startRejected) throw new Error('injected start failure');
        Runtime.begin('host'); storage.setOrCreate('masterCapsuleOpen', true);
        const request = Runtime.currentRequest();
        const finish = () => {
          if (options.hostFails) Runtime.fail('host', 'injected mask/show failure');
          else { Runtime.parentPrepared('host'); Runtime.confirm('host', request); }
        };
        if (options.onHostStart) options.onHostStart(finish);
        else finish();
      }
      if (want.abilityName === 'PaperAbility') {
        const show = ['show', 'expand'].includes(want.parameters.paperCommand);
        storage.setOrCreate(`paperOpen:${want.parameters.paperId}`, show);
      }
    },
    async terminateSelf() { events.push('terminate'); },
    getApplicationContext() { return { async killAllProcesses() { events.push('kill'); } }; }
  };
  storage.setOrCreate('paperOpen:p1', true);
  storage.setOrCreate('trayResidentReady', true);
  storage.setOrCreate('trayResidentToken', 'resident');
  function load(relative) {
    const file = path.resolve(root, relative.endsWith('.ets') ? relative : relative + '.ets');
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    const text = fs.readFileSync(file, 'utf8');
    const output = ts.transpileModule(text, {
      compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
      reportDiagnostics: true, fileName: file.replace(/\.ets$/, '.ts')
    });
    const errors = (output.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error);
    assert.equal(errors.length, 0, ts.formatDiagnosticsWithColorAndContext(errors, {
      getCanonicalFileName: x => x, getCurrentDirectory: () => root, getNewLine: () => '\n'
    }));
    function localRequire(spec) {
      if (spec === '@kit.AbilityKit') return {
        UIAbility: class { constructor() { this.context = context; } },
        ConfigurationConstant: { ColorMode: { COLOR_MODE_LIGHT: 0 } },
        contextConstant: { ProcessMode: { ATTACH_TO_STATUS_BAR_ITEM: 1 }, StartupVisibility: { STARTUP_HIDE: 1 } }
      };
      if (spec === '@kit.ArkUI') return { display: options.display, window: {} };
      if (spec === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {}, error() {} } };
      if (spec.endsWith('/PaperStore') || spec === './PaperStore') return { PaperStore: store };
      if (spec.endsWith('/TrayService') || spec === './TrayService') return { TrayService: tray };
      if (spec.startsWith('@kit.')) throw new Error(`Unmocked platform dependency: ${spec}`);
      return load(path.relative(root, path.resolve(path.dirname(file), spec)));
    }
    vm.runInNewContext(`(function(require,module,exports){${output.outputText}\n})`, {
      AppStorage: storage, setTimeout, clearTimeout, Date, Map, LocalStorage: class {},
      console: { warn() {}, error() {}, info() {} }
    }, { filename: file })(localRequire, mod, mod.exports);
    return mod.exports;
  }
  Runtime = load('common/CapsuleRuntime').CapsuleRuntime;
  return { load, Runtime, context, store, state, storage, events };
}

for (const [name, action] of [
  ['requires parent readiness and exact request acknowledgement', h => {
    const n = h.Runtime.request(); h.Runtime.begin('a');
    assert.equal(h.Runtime.confirm('a', n), false);
    h.Runtime.parentPrepared('a'); assert.equal(h.Runtime.confirm('a', n), true);
    assert.equal(h.Runtime.isReady(), true);
    h.Runtime.request(); assert.equal(h.Runtime.isReady(), false);
  }],
  ['ignores stale owners, stale requests and late completion after failure', h => {
    const old = h.Runtime.request(); h.Runtime.begin('old');
    const n = h.Runtime.request(); h.Runtime.begin('new'); h.Runtime.parentPrepared('new');
    assert.equal(h.Runtime.confirm('old', n), false);
    assert.equal(h.Runtime.confirm('new', old), false);
    h.Runtime.end('old'); assert.equal(h.Runtime.isOwner('new'), true);
    h.Runtime.fail('old', 'stale'); assert.equal(h.Runtime.hasFailed(), false);
    h.Runtime.fail('new', 'mask failed'); assert.equal(h.Runtime.confirm('new', n), false);
  }],
  ['superseded collapse intent cannot commit', h => {
    const old = h.Runtime.stageCollapse('p1'); const current = h.Runtime.stageCollapse('p1');
    assert.equal(h.Runtime.ownsCollapse('p1', old), false);
    assert.equal(h.Runtime.ownsCollapse('p1', current), true);
    h.Runtime.cancelCollapse('p1'); assert.equal(h.Runtime.isPending('p1'), false);
  }]
]) test(name, () => action(harness()));

test('readiness timeout latches a failure, and retry requires a fresh ack', async () => {
  const h = harness(); const n = h.Runtime.request(); h.Runtime.begin('host');
  assert.equal(await h.Runtime.waitFor(n, 0), false);
  assert.equal(h.Runtime.hasFailed(), true);
  h.Runtime.retry(); assert.equal(h.Runtime.isReady(), false);
  h.Runtime.parentPrepared('host'); assert.equal(h.Runtime.confirm('host', n), true);
});

for (const height of [300, 600, 900]) for (const gap of [0, 4, 8]) {
  test(`all 100 papers remain reachable within ${height}vp, gap ${gap}`, () => {
    const { capsuleViewport } = harness().load('common/CapsuleViewport');
    for (const master of [false, true]) {
      const first = capsuleViewport(height, 100, gap, master, false, 0);
      const seen = [];
      for (let page = 0; page < first.pages; page++) {
        const v = capsuleViewport(height, 100, gap, master, false, page);
        assert.equal(v.fits, true); assert.ok(v.height <= height - 16);
        for (let n = v.start; n < v.end; n++) seen.push(n);
      }
      assert.deepEqual(seen, Array.from({ length: 100 }, (_, i) => i));
    }
  });
}

test('retraction, page shrink, invalid input and too-small displays are bounded', () => {
  const { capsuleViewport: v } = harness().load('common/CapsuleViewport');
  const retract = v(300, 100, 4, true, true, 99);
  assert.equal(retract.height, 46); assert.equal(retract.pager, false); assert.equal(retract.end, 0);
  assert.equal(v(900, 2, 4, true, false, 99).page, 0);
  assert.equal(v(900, NaN, NaN, true, false, NaN).page, 0);
  assert.equal(v(50, 100, 4, true, false, 0).fits, false);
});

test('pending handoff keeps original expanded until successful readiness', async () => {
  let release;
  const h = harness({ onHostStart: done => { release = done; } });
  const shell = h.load('common/DesktopShell').DesktopShell;
  const p = shell.setPaperCollapsed(h.context, 'p1', true);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(h.state.papers[0].isCollapsed, false);
  assert.equal(h.Runtime.isPending('p1'), true);
  assert.equal(h.events.includes('PaperAbility:close'), false);
  release();
  // The final committed-state reconciliation also needs its own acknowledgement.
  await new Promise(resolve => setTimeout(resolve, 35));
  release(); await p;
  assert.equal(h.state.papers[0].isCollapsed, true);
  assert.equal(h.Runtime.isPending('p1'), false);
  assert.equal(h.events.includes('PaperAbility:close'), true);
});

for (const failure of ['hostFails', 'startRejected']) {
  test(`${failure}: failed handoff never closes the original`, async () => {
    const h = harness({ [failure]: true });
    await h.load('common/DesktopShell').DesktopShell.setPaperCollapsed(h.context, 'p1', true);
    assert.equal(h.state.papers[0].isCollapsed, false);
    assert.equal(h.events.includes('PaperAbility:close'), false);
    assert.equal(h.Runtime.isPending('p1'), false);
    assert.equal(h.Runtime.hasFailed(), true);
  });
}

test('persisted cold-start collapses are restored if the host fails', async () => {
  const h = harness({ hostFails: true }); h.state.papers[0].isCollapsed = true;
  h.storage.setOrCreate('paperOpen:p1', false);
  await h.load('common/DesktopShell').DesktopShell.syncCapsules(h.context);
  assert.equal(h.state.papers[0].isCollapsed, false);
  assert.equal(h.events.includes('PaperAbility:show'), true);
});

test('successful close operations are not counted as a reachable surface', async () => {
  const h = harness(); h.state.useDeepCapsuleMode = false; h.state.papers[0].isVisible = false;
  const reachable = await h.load('common/DesktopShell').DesktopShell.syncCapsules(h.context);
  assert.equal(reachable, false); assert.equal(h.events.includes('PaperAbility:close'), true);
});

test('hide while handoff is pending cancels the collapse and does not resurrect the paper', async () => {
  let release;
  const h = harness({ onHostStart: done => { release = done; } });
  const shell = h.load('common/DesktopShell').DesktopShell;
  const collapse = shell.setPaperCollapsed(h.context, 'p1', true);
  await new Promise(resolve => setImmediate(resolve));
  const hide = shell.hidePaper(h.context, 'p1');
  release(); await Promise.all([collapse, hide]);
  assert.equal(h.state.papers[0].isVisible, false);
  assert.equal(h.state.papers[0].isCollapsed, false);
  assert.equal(h.Runtime.isPending('p1'), false);
});

test('hiding already-closed papers does not create UIAbilities to close them', async () => {
  const h = harness(); h.storage.setOrCreate('paperOpen:p1', false);
  await h.load('common/DesktopShell').DesktopShell.hideAll(h.context);
  assert.equal(h.events.some(e => e.startsWith('PaperAbility:')), false);
});

for (const [name, flushResults, removed, killed] of [
  ['first save failure cancels exit before tray removal', [false], false, false],
  ['second save failure restores tray and cancels exit', [true, false], true, false],
  ['successful saves permit explicit exit', [true, true], true, true]
]) test(name, async () => {
  const h = harness({ flushResults });
  await h.load('common/DesktopShell').DesktopShell.exitApplication(h.context);
  assert.equal(h.events.includes('remove-tray'), removed);
  assert.equal(h.events.includes('kill'), killed);
  assert.equal(h.storage.get('saveExitBlocked'), !killed);
  if (removed && !killed) {
    assert.equal(h.events.includes('install-tray'), true);
    assert.equal(h.storage.get('applicationExitRequested'), false);
  }
});

test('taskbar recovery expands and restores hidden papers without requiring capsules', async () => {
  const h = harness({ hostFails: true });
  h.state.papers[0].isVisible = false; h.state.papers[0].isCollapsed = true;
  await h.load('common/DesktopShell').DesktopShell.restoreAllPapers(h.context);
  assert.equal(h.state.papers[0].isVisible, true);
  assert.equal(h.state.papers[0].isCollapsed, false);
  assert.equal(h.events.includes('PaperAbility:show'), true);
});

function fakeWindows(clamped = false) {
  const calls = [];
  function make(name) {
    let content = false;
    const rect = { left: 0, top: 0, width: 100, height: 100 };
    const w = {
      getWindowProperties: () => ({ windowRect: { ...rect } }),
      getUIContext() {
        if (name === 'child' && !content) throw new Error('UIContext used before content');
        return { vp2px: n => n, px2vp: n => n };
      },
      async resizeAsync(width, height) { rect.width = width; rect.height = height; },
      async resize(width, height) { rect.width = width; rect.height = height; },
      async moveWindowToAsync(left, top) { rect.left = clamped && name === 'parent' ? 50 : left; rect.top = top; },
      async moveWindowTo(left, top) { rect.left = left; rect.top = top; },
      setUIContent(_url, cb) { content = true; calls.push(`${name}:content`); cb({ code: 0 }); },
      on() {}, off() {}
    };
    for (const method of ['setWindowDecorVisible','setWindowTitleButtonVisible','setWindowTitleMoveEnabled',
      'setWindowBackgroundColor','setWindowContainerColor','setWindowShadowEnabled','setWindowTouchable',
      'setWindowFocusable','showWindow','setWindowTopmost','setFollowParentWindowLayoutEnabled',
      'setResizeByDragEnabled','destroyWindow']) {
      w[method] = async () => { calls.push(`${name}:${method}`); };
    }
    return w;
  }
  const parent = make('parent'); const child = make('child');
  const display = {
    width: 800, height: 600, on() {}, off() {},
    async getAvailableArea() { return { left: 0, top: 0, width: 800, height: 580 }; }
  };
  return { calls, parent, child, display };
}

for (const clamped of [false, true]) test(`host setup: parent topmost, no unmasked show, clamped=${clamped}`, async () => {
  const w = fakeWindows(clamped);
  const h = harness({ display: { getDefaultDisplaySync: () => w.display } });
  h.state.papers[0].isCollapsed = true;
  const Ability = h.load('mastercapsuleability/MasterCapsuleAbility').default;
  const ability = new Ability(); h.Runtime.request();
  ability.onCreate({ parameters: {} }, {});
  ability.onWindowStageCreate({
    getMainWindowSync: () => w.parent,
    loadContent(_path, cb) { cb({ code: 0 }); },
    async createSubWindow() { return w.child; }, on() {}, off() {}
  });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(w.calls.includes('parent:setWindowTopmost'), true);
  assert.equal(w.calls.includes('child:setWindowTopmost'), false);
  assert.equal(w.calls.includes('child:showWindow'), false);
  assert.equal(h.Runtime.isReady(), false);
  assert.equal(h.Runtime.hasFailed(), clamped);
  if (!clamped) assert.equal(w.calls.includes('child:content'), true);
  else assert.equal(h.events.includes('terminate'), true);
  ability.onDestroy();
});

test('PaperAbility retains the original on failed delegation', async () => {
  const h = harness({ hostFails: true }); h.state.papers[0].isCollapsed = true;
  const Ability = h.load('paperability/PaperAbility').default;
  const ability = new Ability();
  ability.paperId = 'p1'; ability.openToken = 'paper';
  ability.mainWindow = {}; ability.windowStage = {}; ability.contentLoaded = true;
  let restored = 0;
  ability.showAndConfigure = async () => { restored++; };
  ability.setInitialWindowInteraction = async () => {};
  await ability.delegateCollapsedPaperToEdge();
  assert.equal(h.state.papers[0].isCollapsed, false);
  assert.equal(restored, 1);
  assert.equal(h.events.includes('terminate'), false);
});
