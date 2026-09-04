import {
  UI_LANGUAGE_EN,
  UI_LANGUAGE_JA,
  UI_LANGUAGE_KO,
  UI_LANGUAGE_SYSTEM,
  UI_LANGUAGE_ZH_CN
} from './Models';

// Lightweight, strict-ArkTS-friendly localization. String switches are used
// deliberately: dynamic object indexes are rejected by ArkTS in strict mode.
// Unknown keys are shown verbatim so a missing catalog entry stays visible.

export function supportedLanguages(): string[] {
  return [
    UI_LANGUAGE_SYSTEM,
    UI_LANGUAGE_ZH_CN,
    UI_LANGUAGE_EN,
    UI_LANGUAGE_JA,
    UI_LANGUAGE_KO
  ];
}

export function normalizeLanguage(language: string): string {
  const normalized: string = language.trim().replace('_', '-').toLowerCase();
  if (normalized.length === 0 || normalized === 'system' || normalized === 'auto' ||
    normalized === 'default') {
    return UI_LANGUAGE_SYSTEM;
  }
  if (normalized === 'zh' || normalized.startsWith('zh-')) {
    return UI_LANGUAGE_ZH_CN;
  }
  if (normalized === 'en' || normalized.startsWith('en-')) {
    return UI_LANGUAGE_EN;
  }
  if (normalized === 'ja' || normalized.startsWith('ja-')) {
    return UI_LANGUAGE_JA;
  }
  if (normalized === 'ko' || normalized.startsWith('ko-')) {
    return UI_LANGUAGE_KO;
  }
  return UI_LANGUAGE_SYSTEM;
}

export function resolveLanguage(language: string, systemLanguage: string): string {
  const selected: string = normalizeLanguage(language);
  if (selected !== UI_LANGUAGE_SYSTEM) {
    return selected;
  }
  const detected: string = normalizeLanguage(systemLanguage);
  return detected === UI_LANGUAGE_SYSTEM ? UI_LANGUAGE_ZH_CN : detected;
}

// Use t() when language is already a concrete locale. Passing "system" uses
// zh-CN as the safe fallback. Use tForSystem() when the OS locale is available.
export function t(language: string, key: string): string {
  const normalized: string = normalizeLanguage(language);
  let localized: string = '';
  if (normalized === UI_LANGUAGE_EN) {
    localized = textEn(key);
  } else if (normalized === UI_LANGUAGE_JA) {
    localized = textJa(key);
  } else if (normalized === UI_LANGUAGE_KO) {
    localized = textKo(key);
  }
  if (localized.length > 0) {
    return localized;
  }
  const shared: string = textShared(key);
  return shared.length > 0 ? shared : textZhCn(key);
}

export function tForSystem(language: string, systemLanguage: string, key: string): string {
  return t(resolveLanguage(language, systemLanguage), key);
}

// Templates use named placeholders such as {count} and {error}.
export function formatText(template: string, name: string, value: string): string {
  return template.replace('{' + name + '}', value);
}

export function tf(language: string, key: string, name: string, value: string): string {
  return formatText(t(language, key), name, value);
}

export function languageLabel(language: string, displayLanguage: string = UI_LANGUAGE_ZH_CN): string {
  const selected: string = normalizeLanguage(language);
  if (selected === UI_LANGUAGE_ZH_CN) {
    return t(displayLanguage, 'language.zhCN');
  }
  if (selected === UI_LANGUAGE_EN) {
    return t(displayLanguage, 'language.en');
  }
  if (selected === UI_LANGUAGE_JA) {
    return t(displayLanguage, 'language.ja');
  }
  if (selected === UI_LANGUAGE_KO) {
    return t(displayLanguage, 'language.ko');
  }
  return t(displayLanguage, 'language.system');
}

function textShared(key: string): string {
  switch (key) {
    case 'app.name': return 'PaperTodo';
    case 'markdown.shortOff': return 'MD×';
    case 'markdown.shortBasic': return 'MD';
    case 'markdown.shortEnhanced': return 'MD+';
    case 'markdown.sampleCode': return '```\ncode\n```';
    case 'glyph.note': return '✎';
    case 'glyph.todo': return '☑';
    case 'glyph.pin': return '📌';
    case 'glyph.unpin': return '⌖';
    case 'glyph.drag': return '⋮⋮';
    case 'glyph.theme': return '◐';
    case 'glyph.collapse': return '▁';
    case 'glyph.newTodo': return '☑+';
    case 'glyph.newNote': return '✎+';
    case 'glyph.more': return '⋯';
    case 'glyph.minimize': return '—';
    case 'glyph.close': return '×';
    case 'glyph.undo': return '↶';
    case 'glyph.redo': return '↷';
    case 'glyph.checked': return '✓';
    case 'glyph.changeLink': return '⌁';
    case 'glyph.reorder': return '≡';
    case 'glyph.add': return '+';
    case 'glyph.bold': return 'B';
    case 'glyph.italic': return 'I';
    case 'glyph.strike': return 'S';
    case 'glyph.heading': return 'H';
    case 'glyph.quote': return '>';
    case 'glyph.bullet': return '•';
    case 'glyph.code': return '{}';
    case 'glyph.link': return '↗';
    case 'glyph.image': return '▧';
    case 'glyph.zoomOut': return '−';
    case 'glyph.resize': return '◢';
    case 'glyph.capsuleOpen': return '›';
    case 'glyph.notePrefix': return '✎ ';
    case 'glyph.todoPrefix': return '☑ ';
    case 'glyph.linkPrefix': return '↗ ';
    case 'glyph.quotePrefix': return '│ ';
    default: return '';
  }
}

function textZhCn(key: string): string {
  switch (key) {
    case 'language.system': return '跟随系统';
    case 'language.zhCN': return '简体中文';
    case 'language.en': return '英语';
    case 'language.ja': return '日语';
    case 'language.ko': return '韩语';

    case 'app.name': return 'PaperTodo';
    case 'app.subtitle': return '轻量待办与桌面笔记';
    case 'app.settingsSubtitle': return '设置';
    case 'tab.general': return '常规';
    case 'tab.shortcuts': return '快捷键';
    case 'tab.papers': return '纸片';
    case 'tab.basic': return '基础';
    case 'tab.capsule': return '胶囊';
    case 'tab.visual': return '视觉';
    case 'section.basicBehavior': return '基础行为';
    case 'section.capsule': return '胶囊';
    case 'section.singleScreenRightQueue': return '单屏右侧队列';
    case 'section.visual': return '视觉';
    case 'section.generalBehavior': return '常规';
    case 'section.paperToolbar': return '纸片顶栏';
    case 'section.capsuleBehavior': return '胶囊';
    case 'section.data': return '数据';
    case 'section.shortcuts': return '快捷键';
    case 'section.systemEntry': return '系统入口';

    case 'action.newTodo': return '☑ 新建待办';
    case 'action.newNote': return '✎ 新建笔记';
    case 'action.restorePapers': return '恢复全部纸片';
    case 'action.retryCapsules': return '重试侧边胶囊';
    case 'action.retrySave': return '重试保存';
    case 'status.capsuleRecovery': return '侧边胶囊未就绪，纸片已保留或恢复为展开状态。';
    case 'status.exitSaveFailed': return '尚有内容保存失败，已取消退出。请重试保存，不要强制结束应用。';
    case 'capsule.previousPage': return '上一页胶囊';
    case 'capsule.nextPage': return '下一页胶囊';
    case 'action.showAll': return '显示全部';
    case 'action.hideAll': return '隐藏全部';
    case 'action.restoreBackup': return '恢复备份';
    case 'action.focus': return '聚焦';
    case 'action.show': return '显示';
    case 'action.hide': return '隐藏';
    case 'action.cancel': return '取消';
    case 'action.confirmDelete': return '确认删除';
    case 'action.confirm': return '确认';
    case 'action.edit': return '编辑';
    case 'action.browse': return '预览';
    case 'action.theme': return '主题';
    case 'action.collapse': return '折叠';
    case 'action.newTodoShort': return '新待办';
    case 'action.newNoteShort': return '新笔记';
    case 'action.clearCompleted': return '清除已完成项';
    case 'action.markDone': return '标为完成';
    case 'action.markUndone': return '标为未完成';
    case 'action.openAssociation': return '打开关联';
    case 'action.addAssociation': return '添加关联';
    case 'action.openContainingFolder': return '打开所在位置';
    case 'action.changeAssociation': return '更改关联';
    case 'action.removeAssociation': return '解除关联';
    case 'action.deleteTodo': return '删除此项';
    case 'action.dropTodoToDelete': return '松手删除此待办';
    case 'action.deletePaper': return '删除纸片';
    case 'dialog.deletePaperTitle': return '删除这张纸片？';
    case 'dialog.deletePaperMessage': return '纸片内容和附件将被永久删除，此操作无法撤销。';
    case 'action.expand': return '展开';
    case 'action.pin': return '置顶';
    case 'action.unpin': return '取消置顶';
    case 'action.openExternally': return '外部打开 Markdown';
    case 'action.settings': return '设置';
    case 'action.exit': return '退出 PaperTodo';
    case 'action.closeSettings': return '关闭设置';
    case 'action.retryStatusBar': return '重试状态栏';
    case 'action.retryingStatusBar': return '正在重试…';
    case 'tray.newTodo': return '新建待办';
    case 'tray.newNote': return '新建笔记';
    case 'tray.toggleAll': return '显示 / 隐藏全部';

    case 'setting.language': return '语言：';
    case 'setting.theme': return '主题：';
    case 'setting.colorScheme': return '配色：';
    case 'setting.markdown': return 'Markdown：';
    case 'setting.todoSize': return '待办大小：';
    case 'setting.clearAfterComplete': return '完成后清除：';
    case 'setting.completedToBottom': return '完成项置底：';
    case 'setting.paperLinks': return '允许新增纸片关联：';
    case 'setting.hideLinkedPapersFromCapsules': return '关联纸片退出胶囊队列：';
    case 'setting.imageCompression': return '大图自动压缩：';
    case 'setting.globalHotkeys': return '运行期间全局快捷键：';
    case 'setting.globalHotkeysHint':
      return '运行期间：Ctrl+Alt+S/H/P 显示/隐藏/切换全部，T/N 新建待办/笔记，Q 退出。';
    case 'setting.animations': return '动画：';
    case 'setting.newTodoButton': return '纸片顶栏新待办：';
    case 'setting.newNoteButton': return '纸片顶栏新笔记：';
    case 'setting.externalOpenButton': return '纸片顶栏外部打开：';
    case 'setting.capsule': return '胶囊：';
    case 'setting.deepCapsule': return '侧边胶囊：';
    case 'setting.expandedDeepCapsule': return '纸片展开时保留侧边胶囊：';
    case 'setting.masterCapsule': return '主胶囊：';
    case 'setting.titleCharacters': return '标题最大字数：';
    case 'setting.autoDockEdge': return '右侧深胶囊队列：';
    case 'setting.capsuleGap': return '胶囊间距：';
    case 'setting.rememberExpandedPosition': return '记住展开位置：';
    case 'setting.collapseOnSecondClick': return '再次点击展开纸片的侧边胶囊时折叠：';
    case 'setting.hideCloseOnHover': return '隐藏侧边胶囊关闭按钮：';
    case 'setting.edgeTitle': return '侧边胶囊标题字数：';
    case 'setting.overallFontSize': return '纸片内容整体字号：';
    case 'setting.noteFontSize': return '笔记字号：';
    case 'setting.noteBold': return '笔记加粗：';
    case 'setting.todoBold': return '待办加粗：';
    case 'setting.titleFontSize': return '标题字号：';
    case 'setting.titleBold': return '标题加粗：';
    case 'setting.capsuleFontSize': return '胶囊字号：';
    case 'setting.capsuleBold': return '胶囊加粗：';
    case 'setting.resizeHandle': return '缩放角标：';
    case 'setting.backupHint': return '恢复后会重新打开备份中可见的纸片。';
    case 'setting.statusBarEntry': return '状态栏入口';

    case 'value.enabled': return '开启';
    case 'value.disabled': return '关闭';
    case 'value.visible': return '显示';
    case 'value.hidden': return '隐藏';
    case 'value.system': return '跟随系统';
    case 'value.light': return '浅色';
    case 'value.dark': return '深色';
    case 'value.warmPaper': return '暖纸';
    case 'value.ink': return '墨';
    case 'value.forest': return '林';
    case 'value.sunset': return '霞';
    case 'value.markdownOff': return '不启用';
    case 'value.markdownBasic': return '启用';
    case 'value.markdownEnhanced': return '增强';
    case 'value.small': return '小';
    case 'value.medium': return '中';
    case 'value.large': return '大';
    case 'value.extraLarge': return '特大';
    case 'value.all': return '全部';
    case 'value.characters': return '{count} 字';
    case 'value.resizeStandard': return '标准';
    case 'value.resizeSoft': return '柔和';
    case 'value.resizeHidden': return '隐藏';

    case 'status.storageProtectionDetected':
      return '检测到主数据与备份均异常，已进入数据保护状态，不会用空白数据覆盖原存储。';
    case 'status.hotkeysIdle': return '全局快捷键已关闭';
    case 'status.hotkeysActive': return '全局快捷键已注册';
    case 'status.hotkeysConflict': return '快捷键已被系统或其他应用占用；请关闭后重试。';
    case 'status.hotkeysUnsupported': return '当前设备不支持全局快捷键。';
    case 'status.hotkeysError': return '全局快捷键注册失败；请关闭后重试。';
    case 'status.statusBarActive': return '状态栏入口已就绪';
    case 'status.statusBarUnknown': return '状态栏入口状态未知';
    case 'status.statusBarUnsupported': return '此设备当前不支持状态栏入口';
    case 'status.statusBarRetrying': return '正在恢复状态栏入口…';
    case 'status.statusBarUncertain': return '系统尚未确认状态栏入口；正在等待驻留能力接管';
    case 'status.statusBarResidentError': return '状态栏入口已添加，但驻留能力未启动';
    case 'status.statusBarResidentRemoved': return '驻留能力未启动，已移除不完整的状态栏入口';
    case 'status.statusBarRemoveError': return '状态栏入口移除失败；请重新启动应用后重试';
    case 'status.statusBarError': return '状态栏入口不可用；可在此重试';
    case 'status.openPaperFailed': return '打开纸片失败：{error}';
    case 'status.createBlockedByProtection': return '数据处于保护状态，暂不允许新建纸片。';
    case 'status.paperLimit': return '最多支持 {count} 张纸片。';
    case 'status.noValidBackup': return '没有可恢复的有效备份';
    case 'status.backupRestored': return '已恢复上一份成功保存的自动备份';
    case 'status.createPaperBlocked': return '无法继续新建纸片：已达数量上限或数据处于保护状态';
    case 'status.createPaperFailed': return '新建纸片失败：{error}';
    case 'status.todoPasteLimit': return '单次最多添加 {count} 条待办';
    case 'status.linkedPaperMissing': return '关联纸片已不存在，可重新关联或解除';
    case 'status.openLinkedPaperFailed': return '打开关联纸片失败：{error}';
    case 'status.noteLengthLimit': return '笔记已达到安全长度上限';
    case 'status.openLinkFailed': return '无法打开链接：{error}';
    case 'status.quickLaunchPickerFailed': return '无法选择快启目标：{error}';
    case 'status.quickLaunchPermissionFailed': return '已关联快启目标，但无法保留长期访问权限：{error}';
    case 'status.quickLaunchOpenFailed': return '无法打开快启目标：{error}';
    case 'status.quickLaunchMissing': return '快启目标已失效，可重新选择或解除';
    case 'status.quickLaunchDropUnsupported': return '拖入的内容不是可关联的文件或文件夹。';
    case 'status.quickLaunchContainingFolderFailed': return '无法打开所在位置：{error}';
    case 'status.paperLinkDropDisabled': return '纸片关联已在设置中关闭。';
    case 'status.paperLinkDropSelf': return '不能把待办关联到它所在的纸片。';
    case 'status.paperLinkDropLinked': return '已关联到“{title}”';
    case 'status.todoDragDeleted': return '待办已删除，可使用撤销恢复。';
    case 'status.imagePickerFailed': return '无法选择图片：{error}';
    case 'status.imageDropUnsupported': return '拖入的内容不是受支持的图片文件。';
    case 'status.imagePasteUnsupported': return '剪贴板中没有可插入的图片或图片文件。';
    case 'status.imagePastePermissionFailed': return '未获得本次剪贴板访问权限。';
    case 'status.imageImporting': return '正在导入并校验图片…';
    case 'status.imageImported': return '图片已导入并插入笔记';
    case 'status.imageInputTooLarge': return '图片源文件超过 32 MiB 上限';
    case 'status.imageDimensionsTooLarge': return '图片边长超过 4096 像素上限';
    case 'status.imageCompressionDisabled': return '图片超过 8 MiB 或 2048 像素，请开启大图自动压缩';
    case 'status.imageAnimatedTooLarge': return '超限的 GIF/TIFF 不会自动重编码，以免丢失动画或多帧';
    case 'status.imageStorageFull': return '图片附件总量已达到 120 MiB 上限';
    case 'status.imageOutputTooLarge': return '压缩后的图片仍超过 8 MiB 上限';
    case 'status.imageInvalid': return '所选文件不是可读取的有效图片';
    case 'status.imageImportFailed': return '导入图片失败：{error}';
    case 'status.imageImportFailedGeneric': return '导入图片失败，请确认文件仍可访问且格式受支持。';
    case 'status.externalMarkdownOpenFailed': return '无法用系统应用打开 Markdown：{error}';

    case 'empty.storageProtectionTitle': return '数据保护模式';
    case 'empty.noPapersTitle': return '桌面上还没有纸片';
    case 'empty.storageProtectionBody': return '原数据未被覆盖。请先尝试恢复备份。';
    case 'empty.noPapersBody': return '新建一张待办纸或笔记纸即可开始。';
    case 'empty.noteStart': return '点击开始记录';

    case 'paper.note': return '笔记';
    case 'paper.todo': return '待办';
    case 'paper.todoCount': return '{count} 项待办';
    case 'paper.unnamedNote': return '未命名笔记';
    case 'paper.unnamedTodo': return '未命名待办';
    case 'paper.notePaper': return '笔记纸';
    case 'paper.todoPaper': return '待办纸';
    case 'paper.visible': return '显示';
    case 'paper.hidden': return '隐藏';
    case 'paper.topmost': return '置顶';
    case 'paper.capsule': return '胶囊';
    case 'capsule.retractQueue': return '▾ 收起';
    case 'capsule.retractedCount': return '▸ {count} 个';

    case 'placeholder.todoItem': return '待办事项';
    case 'placeholder.addTodo': return '添加待办；可直接粘贴多行';
    case 'placeholder.noteContent': return '写点什么…';
    case 'link.to': return '关联到';
    case 'link.none': return '无';
    case 'link.invalid': return '失效';
    case 'quick.file': return '▤ 文件';
    case 'quick.folder': return '▣ 文件夹';
    case 'quick.unnamed': return '未命名目标';
    case 'image.filterLabel': return '图片';
    case 'image.alt': return '图片';
    case 'image.missing': return '附件缺失';

    case 'markdown.shortOff': return 'MD×';
    case 'markdown.shortBasic': return 'MD';
    case 'markdown.shortEnhanced': return 'MD+';
    case 'markdown.sampleBold': return '**文本**';
    case 'markdown.sampleItalic': return '*文本*';
    case 'markdown.sampleStrike': return '~~文本~~';
    case 'markdown.sampleHeading': return '## 标题';
    case 'markdown.sampleQuote': return '> 引用';
    case 'markdown.sampleList': return '- 列表';
    case 'markdown.sampleInlineCode': return '行内代码';
    case 'markdown.sampleCode': return '```\ncode\n```';
    case 'markdown.sampleLink': return '[链接](https://)';

    case 'button.editShort': return '编';
    case 'button.browseShort': return '览';
    case 'footer.autosave':
      return '编辑先更新内存；空闲约 1 秒落盘，持续输入最长约 10 秒强制保存，并保留上一份成功状态。';

    case 'glyph.note': return '✎';
    case 'glyph.todo': return '☑';
    case 'glyph.pin': return '📌';
    case 'glyph.unpin': return '⌖';
    case 'glyph.drag': return '⋮⋮';
    case 'glyph.theme': return '◐';
    case 'glyph.collapse': return '▁';
    case 'glyph.newTodo': return '☑+';
    case 'glyph.newNote': return '✎+';
    case 'glyph.more': return '⋯';
    case 'glyph.minimize': return '—';
    case 'glyph.close': return '×';
    case 'glyph.undo': return '↶';
    case 'glyph.redo': return '↷';
    case 'glyph.checked': return '✓';
    case 'glyph.changeLink': return '⌁';
    case 'glyph.reorder': return '≡';
    case 'glyph.add': return '+';
    case 'glyph.bold': return 'B';
    case 'glyph.italic': return 'I';
    case 'glyph.strike': return 'S';
    case 'glyph.heading': return 'H';
    case 'glyph.quote': return '>';
    case 'glyph.bullet': return '•';
    case 'glyph.code': return '{}';
    case 'glyph.link': return '↗';
    case 'glyph.zoomOut': return '−';
    case 'glyph.resize': return '◢';
    case 'glyph.capsuleOpen': return '›';
    case 'glyph.notePrefix': return '✎ ';
    case 'glyph.todoPrefix': return '☑ ';
    case 'glyph.linkPrefix': return '↗ ';
    case 'glyph.quotePrefix': return '│ ';
    default: return key;
  }
}

function textEn(key: string): string {
  switch (key) {
    case 'language.system': return 'Follow system';
    case 'language.zhCN': return 'Simplified Chinese';
    case 'language.en': return 'English';
    case 'language.ja': return 'Japanese';
    case 'language.ko': return 'Korean';
    case 'app.subtitle': return 'Lightweight to-dos and desktop notes';
    case 'app.settingsSubtitle': return 'Settings';
    case 'tab.general': return 'General';
    case 'tab.shortcuts': return 'Shortcuts';
    case 'tab.papers': return 'Papers';
    case 'tab.basic': return 'Basic';
    case 'tab.capsule': return 'Capsule';
    case 'tab.visual': return 'Appearance';
    case 'section.basicBehavior': return 'Basic behavior';
    case 'section.capsule': return 'Capsule';
    case 'section.singleScreenRightQueue': return 'Single-screen right-edge queue';
    case 'section.visual': return 'Appearance';
    case 'section.generalBehavior': return 'General';
    case 'section.paperToolbar': return 'Paper title bar';
    case 'section.capsuleBehavior': return 'Capsules';
    case 'section.data': return 'Data';
    case 'section.shortcuts': return 'Shortcuts';
    case 'section.systemEntry': return 'System entry';
    case 'action.newTodo': return '☑ New to-do';
    case 'action.newNote': return '✎ New note';
    case 'action.restorePapers': return 'Restore all papers';
    case 'action.retryCapsules': return 'Retry edge capsules';
    case 'action.retrySave': return 'Retry save';
    case 'status.capsuleRecovery': return 'Edge capsules are not ready. Papers have been kept or restored as expanded windows.';
    case 'status.exitSaveFailed': return 'Some changes could not be saved. Exit was cancelled. Retry saving before closing the app.';
    case 'capsule.previousPage': return 'Previous capsule page';
    case 'capsule.nextPage': return 'Next capsule page';
    case 'action.showAll': return 'Show all';
    case 'action.hideAll': return 'Hide all';
    case 'action.restoreBackup': return 'Restore backup';
    case 'action.focus': return 'Focus';
    case 'action.show': return 'Show';
    case 'action.hide': return 'Hide';
    case 'action.cancel': return 'Cancel';
    case 'action.confirmDelete': return 'Confirm delete';
    case 'action.confirm': return 'Confirm';
    case 'action.edit': return 'Edit';
    case 'action.browse': return 'Preview';
    case 'action.theme': return 'Theme';
    case 'action.collapse': return 'Collapse';
    case 'action.newTodoShort': return 'New to-do';
    case 'action.newNoteShort': return 'New note';
    case 'action.clearCompleted': return 'Clear done';
    case 'action.markDone': return 'Mark done';
    case 'action.markUndone': return 'Mark not done';
    case 'action.openAssociation': return 'Open association';
    case 'action.addAssociation': return 'Add association';
    case 'action.openContainingFolder': return 'Open containing folder';
    case 'action.changeAssociation': return 'Change association';
    case 'action.removeAssociation': return 'Remove association';
    case 'action.deleteTodo': return 'Delete item';
    case 'action.dropTodoToDelete': return 'Drop to delete this to-do';
    case 'action.deletePaper': return 'Delete paper';
    case 'dialog.deletePaperTitle': return 'Delete this paper?';
    case 'dialog.deletePaperMessage': return 'The paper and its attachments will be permanently deleted. This cannot be undone.';
    case 'action.expand': return 'Expand';
    case 'action.pin': return 'Always on top';
    case 'action.unpin': return 'Stop always on top';
    case 'action.openExternally': return 'Open Markdown externally';
    case 'action.settings': return 'Settings';
    case 'action.exit': return 'Exit PaperTodo';
    case 'action.closeSettings': return 'Close settings';
    case 'action.retryStatusBar': return 'Retry status bar';
    case 'action.retryingStatusBar': return 'Retrying…';
    case 'tray.newTodo': return 'New to-do';
    case 'tray.newNote': return 'New note';
    case 'tray.toggleAll': return 'Show / hide all';
    case 'setting.language': return 'Language: ';
    case 'setting.theme': return 'Theme: ';
    case 'setting.colorScheme': return 'Colors: ';
    case 'setting.markdown': return 'Markdown: ';
    case 'setting.todoSize': return 'To-do size: ';
    case 'setting.clearAfterComplete': return 'Clear when done: ';
    case 'setting.completedToBottom': return 'Done items last: ';
    case 'setting.paperLinks': return 'Allow new paper links: ';
    case 'setting.hideLinkedPapersFromCapsules': return 'Hide linked papers from capsule queues: ';
    case 'setting.imageCompression': return 'Auto-compress large images: ';
    case 'setting.globalHotkeys': return 'Global shortcuts while running: ';
    case 'setting.globalHotkeysHint':
      return 'While running: Ctrl+Alt+S/H/P shows, hides, or toggles all; T/N creates a to-do or note; Q exits.';
    case 'setting.animations': return 'Animations: ';
    case 'setting.newTodoButton': return 'Paper toolbar new to-do: ';
    case 'setting.newNoteButton': return 'Paper toolbar new note: ';
    case 'setting.externalOpenButton': return 'Paper toolbar external open: ';
    case 'setting.capsule': return 'Capsule: ';
    case 'setting.deepCapsule': return 'Side capsule: ';
    case 'setting.expandedDeepCapsule': return 'Keep side capsule while paper is open: ';
    case 'setting.masterCapsule': return 'Main capsule: ';
    case 'setting.titleCharacters': return 'Maximum title length: ';
    case 'setting.autoDockEdge': return 'Right deep-capsule queue: ';
    case 'setting.capsuleGap': return 'Capsule gap: ';
    case 'setting.rememberExpandedPosition': return 'Remember open position: ';
    case 'setting.collapseOnSecondClick': return 'Collapse an open paper when its side capsule is clicked again: ';
    case 'setting.hideCloseOnHover': return 'Hide side-capsule close button: ';
    case 'setting.edgeTitle': return 'Side-capsule title length: ';
    case 'setting.overallFontSize': return 'Paper content text size: ';
    case 'setting.noteFontSize': return 'Note text size: ';
    case 'setting.noteBold': return 'Bold notes: ';
    case 'setting.todoBold': return 'Bold to-dos: ';
    case 'setting.titleFontSize': return 'Title size: ';
    case 'setting.titleBold': return 'Bold titles: ';
    case 'setting.capsuleFontSize': return 'Capsule text size: ';
    case 'setting.capsuleBold': return 'Bold capsules: ';
    case 'setting.resizeHandle': return 'Resize marker: ';
    case 'setting.backupHint': return 'Visible papers in the backup reopen after restoration.';
    case 'setting.statusBarEntry': return 'Status bar entry';
    case 'value.enabled': return 'On';
    case 'value.disabled': return 'Off';
    case 'value.visible': return 'Show';
    case 'value.hidden': return 'Hide';
    case 'value.system': return 'Follow system';
    case 'value.light': return 'Light';
    case 'value.dark': return 'Dark';
    case 'value.warmPaper': return 'Warm Paper';
    case 'value.ink': return 'Ink';
    case 'value.forest': return 'Forest';
    case 'value.sunset': return 'Sunset';
    case 'value.markdownOff': return 'Disabled';
    case 'value.markdownBasic': return 'Enabled';
    case 'value.markdownEnhanced': return 'Enhanced';
    case 'value.small': return 'Small';
    case 'value.medium': return 'Medium';
    case 'value.large': return 'Large';
    case 'value.extraLarge': return 'Extra large';
    case 'value.all': return 'All';
    case 'value.characters': return '{count} chars';
    case 'value.resizeStandard': return 'Standard';
    case 'value.resizeSoft': return 'Subtle';
    case 'value.resizeHidden': return 'Hidden';
    case 'status.storageProtectionDetected':
      return 'Both the main data and backup are invalid. Data protection is active, and stored data will not be overwritten with an empty state.';
    case 'status.hotkeysIdle': return 'Global shortcuts are off';
    case 'status.hotkeysActive': return 'Global shortcuts are registered';
    case 'status.hotkeysConflict':
      return 'A shortcut is already used by the system or another app. Turn this off and try again.';
    case 'status.hotkeysUnsupported': return 'Global shortcuts are not supported on this device.';
    case 'status.hotkeysError': return 'Global shortcut registration failed. Turn this off and try again.';
    case 'status.statusBarActive': return 'Status bar entry is ready';
    case 'status.statusBarUnknown': return 'Status bar entry status is unknown';
    case 'status.statusBarUnsupported': return 'This device does not currently support a status bar entry';
    case 'status.statusBarRetrying': return 'Restoring the status bar entry…';
    case 'status.statusBarUncertain': return 'The system has not confirmed the entry yet; waiting for the resident ability';
    case 'status.statusBarResidentError': return 'The entry was added, but the resident ability did not start';
    case 'status.statusBarResidentRemoved': return 'The resident ability did not start; the incomplete entry was removed';
    case 'status.statusBarRemoveError': return 'Could not remove the status bar entry. Restart the app and try again.';
    case 'status.statusBarError': return 'Status bar entry is unavailable. You can retry it here.';
    case 'status.openPaperFailed': return 'Could not open paper: {error}';
    case 'status.createBlockedByProtection': return 'Data protection is active. New papers cannot be created right now.';
    case 'status.paperLimit': return 'Up to {count} papers are supported.';
    case 'status.noValidBackup': return 'No valid backup is available';
    case 'status.backupRestored': return 'Restored the last successfully saved automatic backup';
    case 'status.createPaperBlocked': return 'Cannot create another paper: the limit was reached or data protection is active';
    case 'status.createPaperFailed': return 'Could not create paper: {error}';
    case 'status.todoPasteLimit': return 'You can add up to {count} to-dos at once';
    case 'status.linkedPaperMissing': return 'The linked paper no longer exists. Relink or remove the link.';
    case 'status.openLinkedPaperFailed': return 'Could not open linked paper: {error}';
    case 'status.noteLengthLimit': return 'This note has reached the safe length limit';
    case 'status.openLinkFailed': return 'Could not open link: {error}';
    case 'status.quickLaunchPickerFailed': return 'Could not select a quick-launch target: {error}';
    case 'status.quickLaunchPermissionFailed': return 'The target was linked, but long-term access could not be retained: {error}';
    case 'status.quickLaunchOpenFailed': return 'Could not open the quick-launch target: {error}';
    case 'status.quickLaunchMissing': return 'The quick-launch target is unavailable. Select it again or unlink it.';
    case 'status.quickLaunchDropUnsupported': return 'The dropped content is not a linkable file or folder.';
    case 'status.quickLaunchContainingFolderFailed': return 'Could not open the containing folder: {error}';
    case 'status.paperLinkDropDisabled': return 'Paper links are disabled in settings.';
    case 'status.paperLinkDropSelf': return 'A to-do cannot link to the paper that contains it.';
    case 'status.paperLinkDropLinked': return 'Linked to “{title}”';
    case 'status.todoDragDeleted': return 'To-do deleted. Use undo to restore it.';
    case 'status.imagePickerFailed': return 'Could not select an image: {error}';
    case 'status.imageDropUnsupported': return 'The dropped content is not a supported image file.';
    case 'status.imagePasteUnsupported': return 'The clipboard does not contain an image or supported image file.';
    case 'status.imagePastePermissionFailed': return 'Clipboard access was not granted for this paste.';
    case 'status.imageImporting': return 'Importing and validating image…';
    case 'status.imageImported': return 'Image imported and inserted into the note';
    case 'status.imageInputTooLarge': return 'The source image exceeds the 32 MiB limit';
    case 'status.imageDimensionsTooLarge': return 'An image edge exceeds the 4096-pixel limit';
    case 'status.imageCompressionDisabled': return 'This image exceeds 8 MiB or 2048 px. Enable large-image compression.';
    case 'status.imageAnimatedTooLarge': return 'Oversized GIF/TIFF files are not re-encoded to preserve animation or frames';
    case 'status.imageStorageFull': return 'Image attachments have reached the 120 MiB total limit';
    case 'status.imageOutputTooLarge': return 'The compressed image still exceeds the 8 MiB limit';
    case 'status.imageInvalid': return 'The selected file is not a readable image';
    case 'status.imageImportFailed': return 'Could not import image: {error}';
    case 'status.imageImportFailedGeneric': return 'Could not import the image. Check that it is accessible and supported.';
    case 'status.externalMarkdownOpenFailed': return 'Could not open Markdown in a system app: {error}';
    case 'empty.storageProtectionTitle': return 'Data protection mode';
    case 'empty.noPapersTitle': return 'No papers on the desktop yet';
    case 'empty.storageProtectionBody': return 'The original data was not overwritten. Try restoring the backup first.';
    case 'empty.noPapersBody': return 'Create a to-do paper or note paper to get started.';
    case 'empty.noteStart': return 'Click to start writing';
    case 'paper.note': return 'Note';
    case 'paper.todo': return 'To-do';
    case 'paper.todoCount': return 'To-dos: {count}';
    case 'paper.unnamedNote': return 'Untitled note';
    case 'paper.unnamedTodo': return 'Untitled to-do';
    case 'paper.notePaper': return 'Note paper';
    case 'paper.todoPaper': return 'To-do paper';
    case 'paper.visible': return 'Shown';
    case 'paper.hidden': return 'Hidden';
    case 'paper.topmost': return 'Always on top';
    case 'capsule.retractQueue': return '▾ Retract';
    case 'capsule.retractedCount': return '▸ {count}';
    case 'paper.capsule': return 'Capsule';
    case 'placeholder.todoItem': return 'To-do item';
    case 'placeholder.addTodo': return 'Add a to-do; paste multiple lines';
    case 'placeholder.noteContent': return 'Write something…';
    case 'link.to': return 'Link to';
    case 'link.none': return 'None';
    case 'link.invalid': return 'Missing';
    case 'quick.file': return '▤ File';
    case 'quick.folder': return '▣ Folder';
    case 'quick.unnamed': return 'Unnamed target';
    case 'image.filterLabel': return 'Images';
    case 'image.alt': return 'Image';
    case 'image.missing': return 'Attachment missing';
    case 'markdown.sampleBold': return '**text**';
    case 'markdown.sampleItalic': return '*text*';
    case 'markdown.sampleStrike': return '~~text~~';
    case 'markdown.sampleHeading': return '## Heading';
    case 'markdown.sampleQuote': return '> Quote';
    case 'markdown.sampleList': return '- List';
    case 'markdown.sampleInlineCode': return 'Inline code';
    case 'markdown.sampleLink': return '[link](https://)';
    case 'button.editShort': return 'E';
    case 'button.browseShort': return 'V';
    case 'footer.autosave':
      return 'Edits update memory first, save after about 1 second idle, force-save after about 10 seconds of continuous input, and retain the previous successful state.';
    default: return '';
  }
}

function textJa(key: string): string {
  switch (key) {
    case 'language.system': return 'システムに従う';
    case 'language.zhCN': return '簡体字中国語';
    case 'language.en': return '英語';
    case 'language.ja': return '日本語';
    case 'language.ko': return '韓国語';
    case 'app.subtitle': return '軽量 ToDo とデスクトップノート';
    case 'app.settingsSubtitle': return '設定';
    case 'tab.general': return '一般';
    case 'tab.shortcuts': return 'ショートカット';
    case 'tab.papers': return '紙片';
    case 'tab.basic': return '基本';
    case 'tab.capsule': return 'カプセル';
    case 'tab.visual': return '表示';
    case 'section.basicBehavior': return '基本動作';
    case 'section.capsule': return 'カプセル';
    case 'section.singleScreenRightQueue': return '単一画面・右端キュー';
    case 'section.visual': return '表示';
    case 'section.generalBehavior': return '一般';
    case 'section.paperToolbar': return '紙片タイトルバー';
    case 'section.capsuleBehavior': return 'カプセル';
    case 'section.data': return 'データ';
    case 'section.shortcuts': return 'ショートカット';
    case 'section.systemEntry': return 'システム入口';
    case 'action.newTodo': return '☑ ToDo を作成';
    case 'action.newNote': return '✎ ノートを作成';
    case 'action.restorePapers': return 'すべての紙片を復元';
    case 'action.retryCapsules': return 'サイドカプセルを再試行';
    case 'action.retrySave': return '保存を再試行';
    case 'status.capsuleRecovery': return 'サイドカプセルを表示できません。紙片は展開した状態で保持または復元されました。';
    case 'status.exitSaveFailed': return '保存できない変更があるため終了を中止しました。アプリを強制終了せず、保存を再試行してください。';
    case 'capsule.previousPage': return '前のカプセルページ';
    case 'capsule.nextPage': return '次のカプセルページ';
    case 'action.showAll': return 'すべて表示';
    case 'action.hideAll': return 'すべて隠す';
    case 'action.restoreBackup': return 'バックアップを復元';
    case 'action.focus': return 'フォーカス';
    case 'action.show': return '表示';
    case 'action.hide': return '隠す';
    case 'action.cancel': return 'キャンセル';
    case 'action.confirmDelete': return '削除する';
    case 'action.confirm': return '確認';
    case 'action.edit': return '編集';
    case 'action.browse': return 'プレビュー';
    case 'action.theme': return 'テーマ';
    case 'action.collapse': return '折りたたむ';
    case 'action.newTodoShort': return '新規 ToDo';
    case 'action.newNoteShort': return '新規ノート';
    case 'action.clearCompleted': return '完了済みを消去';
    case 'action.markDone': return '完了にする';
    case 'action.markUndone': return '未完了に戻す';
    case 'action.openAssociation': return '関連先を開く';
    case 'action.addAssociation': return '関連を追加';
    case 'action.openContainingFolder': return '保存場所を開く';
    case 'action.changeAssociation': return '関連を変更';
    case 'action.removeAssociation': return '関連を解除';
    case 'action.deleteTodo': return '項目を削除';
    case 'action.dropTodoToDelete': return 'ここにドロップして削除';
    case 'action.deletePaper': return '紙片を削除';
    case 'dialog.deletePaperTitle': return 'この紙片を削除しますか？';
    case 'dialog.deletePaperMessage': return '紙片の内容と添付ファイルは完全に削除されます。この操作は元に戻せません。';
    case 'action.expand': return '展開';
    case 'action.pin': return '常に手前に表示';
    case 'action.unpin': return '常に手前を解除';
    case 'action.openExternally': return 'Markdown を外部で開く';
    case 'action.settings': return '設定';
    case 'action.exit': return 'PaperTodo を終了';
    case 'action.closeSettings': return '設定を閉じる';
    case 'action.retryStatusBar': return 'ステータスバーを再試行';
    case 'action.retryingStatusBar': return '再試行中…';
    case 'tray.newTodo': return '新規 ToDo';
    case 'tray.newNote': return '新規ノート';
    case 'tray.toggleAll': return 'すべて表示 / 非表示';
    case 'setting.language': return '言語：';
    case 'setting.theme': return 'テーマ：';
    case 'setting.colorScheme': return '配色：';
    case 'setting.markdown': return 'Markdown：';
    case 'setting.todoSize': return 'ToDo サイズ：';
    case 'setting.clearAfterComplete': return '完了後に消去：';
    case 'setting.completedToBottom': return '完了項目を下へ：';
    case 'setting.paperLinks': return '新しい紙片リンクを許可：';
    case 'setting.hideLinkedPapersFromCapsules': return '関連紙をカプセル列から外す：';
    case 'setting.imageCompression': return '大きな画像を自動圧縮：';
    case 'setting.globalHotkeys': return '実行中のグローバルショートカット：';
    case 'setting.globalHotkeysHint':
      return '実行中：Ctrl+Alt+S/H/P で全表示/非表示/切替、T/N で ToDo/ノート作成、Q で終了します。';
    case 'setting.animations': return 'アニメーション：';
    case 'setting.newTodoButton': return '紙片ツールバーの新規 ToDo：';
    case 'setting.newNoteButton': return '紙片ツールバーの新規ノート：';
    case 'setting.externalOpenButton': return '紙片ツールバーの外部で開く：';
    case 'setting.capsule': return 'カプセル：';
    case 'setting.deepCapsule': return 'サイドカプセル：';
    case 'setting.expandedDeepCapsule': return '紙片展開中もサイドカプセルを表示：';
    case 'setting.masterCapsule': return 'メインカプセル：';
    case 'setting.titleCharacters': return 'タイトルの最大文字数：';
    case 'setting.autoDockEdge': return '右側ディープカプセルキュー：';
    case 'setting.capsuleGap': return 'カプセル間隔：';
    case 'setting.rememberExpandedPosition': return '展開位置を記憶：';
    case 'setting.collapseOnSecondClick': return '展開中の紙片のサイドカプセルを再クリックして折りたたむ：';
    case 'setting.hideCloseOnHover': return 'サイドカプセルの閉じるボタンを隠す：';
    case 'setting.edgeTitle': return 'サイドカプセルのタイトル文字数：';
    case 'setting.overallFontSize': return '紙片内容の全体文字サイズ：';
    case 'setting.noteFontSize': return 'ノート文字サイズ：';
    case 'setting.noteBold': return 'ノートを太字：';
    case 'setting.todoBold': return 'ToDo を太字：';
    case 'setting.titleFontSize': return 'タイトル文字サイズ：';
    case 'setting.titleBold': return 'タイトルを太字：';
    case 'setting.capsuleFontSize': return 'カプセル文字サイズ：';
    case 'setting.capsuleBold': return 'カプセルを太字：';
    case 'setting.resizeHandle': return 'サイズ変更マーカー：';
    case 'setting.backupHint': return '復元後、バックアップで表示中だった紙片を再度開きます。';
    case 'setting.statusBarEntry': return 'ステータスバー入口';
    case 'value.enabled': return 'オン';
    case 'value.disabled': return 'オフ';
    case 'value.visible': return '表示';
    case 'value.hidden': return '非表示';
    case 'value.system': return 'システムに従う';
    case 'value.light': return 'ライト';
    case 'value.dark': return 'ダーク';
    case 'value.warmPaper': return 'ウォームペーパー';
    case 'value.ink': return '墨';
    case 'value.forest': return '森';
    case 'value.sunset': return '夕焼け';
    case 'value.markdownOff': return '無効';
    case 'value.markdownBasic': return '有効';
    case 'value.markdownEnhanced': return '拡張';
    case 'value.small': return '小';
    case 'value.medium': return '中';
    case 'value.large': return '大';
    case 'value.extraLarge': return '特大';
    case 'value.all': return 'すべて';
    case 'value.characters': return '{count} 文字';
    case 'value.resizeStandard': return '標準';
    case 'value.resizeSoft': return '控えめ';
    case 'value.resizeHidden': return '非表示';
    case 'status.storageProtectionDetected':
      return 'メインデータとバックアップの両方に異常があります。データ保護モードに入り、空のデータで元の保存内容を上書きしません。';
    case 'status.hotkeysIdle': return 'グローバルショートカットはオフです';
    case 'status.hotkeysActive': return 'グローバルショートカットを登録しました';
    case 'status.hotkeysConflict':
      return 'ショートカットはシステムまたは別のアプリで使用中です。オフにしてから再試行してください。';
    case 'status.hotkeysUnsupported': return 'このデバイスはグローバルショートカットに対応していません。';
    case 'status.hotkeysError':
      return 'グローバルショートカットの登録に失敗しました。オフにしてから再試行してください。';
    case 'status.statusBarActive': return 'ステータスバー入口の準備ができました';
    case 'status.statusBarUnknown': return 'ステータスバー入口の状態が不明です';
    case 'status.statusBarUnsupported': return 'このデバイスは現在ステータスバー入口に対応していません';
    case 'status.statusBarRetrying': return 'ステータスバー入口を復旧しています…';
    case 'status.statusBarUncertain': return 'システムが入口をまだ確認していません。常駐アビリティを待機中です';
    case 'status.statusBarResidentError': return '入口は追加されましたが、常駐アビリティを開始できませんでした';
    case 'status.statusBarResidentRemoved': return '常駐アビリティを開始できなかったため、不完全な入口を削除しました';
    case 'status.statusBarRemoveError': return 'ステータスバー入口を削除できません。アプリを再起動して再試行してください。';
    case 'status.statusBarError': return 'ステータスバー入口を利用できません。ここで再試行できます。';
    case 'status.openPaperFailed': return '紙片を開けませんでした：{error}';
    case 'status.createBlockedByProtection': return 'データ保護中のため、現在は紙片を作成できません。';
    case 'status.paperLimit': return '紙片は最大 {count} 枚まで作成できます。';
    case 'status.noValidBackup': return '復元できる有効なバックアップがありません';
    case 'status.backupRestored': return '最後に正常保存された自動バックアップを復元しました';
    case 'status.createPaperBlocked': return '紙片を作成できません：上限に達したか、データ保護中です';
    case 'status.createPaperFailed': return '紙片の作成に失敗しました：{error}';
    case 'status.todoPasteLimit': return '一度に追加できる ToDo は最大 {count} 件です';
    case 'status.linkedPaperMissing': return 'リンク先の紙片がありません。再リンクするか、リンクを解除してください。';
    case 'status.openLinkedPaperFailed': return 'リンク先の紙片を開けませんでした：{error}';
    case 'status.noteLengthLimit': return 'ノートが安全な文字数上限に達しました';
    case 'status.openLinkFailed': return 'リンクを開けませんでした：{error}';
    case 'status.quickLaunchPickerFailed': return 'クイック起動先を選択できませんでした：{error}';
    case 'status.quickLaunchPermissionFailed': return '関連付けましたが、長期アクセス権を保持できませんでした：{error}';
    case 'status.quickLaunchOpenFailed': return 'クイック起動先を開けませんでした：{error}';
    case 'status.quickLaunchMissing': return 'クイック起動先が無効です。再選択するか解除してください。';
    case 'status.quickLaunchDropUnsupported': return 'ドロップした内容は関連付け可能なファイルまたはフォルダーではありません。';
    case 'status.quickLaunchContainingFolderFailed': return '保存場所を開けませんでした：{error}';
    case 'status.paperLinkDropDisabled': return '紙片の関連付けは設定で無効になっています。';
    case 'status.paperLinkDropSelf': return 'ToDo を同じ紙片に関連付けることはできません。';
    case 'status.paperLinkDropLinked': return '「{title}」に関連付けました';
    case 'status.todoDragDeleted': return 'ToDo を削除しました。元に戻すで復元できます。';
    case 'status.imagePickerFailed': return '画像を選択できませんでした：{error}';
    case 'status.imageDropUnsupported': return 'ドロップした内容は対応画像ファイルではありません。';
    case 'status.imagePasteUnsupported': return 'クリップボードに挿入できる画像がありません。';
    case 'status.imagePastePermissionFailed': return '今回のクリップボードアクセスが許可されませんでした。';
    case 'status.imageImporting': return '画像を読み込み、検証しています…';
    case 'status.imageImported': return '画像を読み込み、ノートに挿入しました';
    case 'status.imageInputTooLarge': return '元画像が 32 MiB の上限を超えています';
    case 'status.imageDimensionsTooLarge': return '画像の一辺が 4096 ピクセルの上限を超えています';
    case 'status.imageCompressionDisabled': return '8 MiB または 2048 px を超えています。大画像の自動圧縮を有効にしてください。';
    case 'status.imageAnimatedTooLarge': return 'アニメーションや複数フレームを保つため、超過 GIF/TIFF は再エンコードしません';
    case 'status.imageStorageFull': return '画像添付の合計が 120 MiB の上限に達しました';
    case 'status.imageOutputTooLarge': return '圧縮後も画像が 8 MiB の上限を超えています';
    case 'status.imageInvalid': return '選択したファイルは読み取れる画像ではありません';
    case 'status.imageImportFailed': return '画像の読み込みに失敗しました：{error}';
    case 'status.imageImportFailedGeneric': return '画像を読み込めませんでした。アクセス権と形式を確認してください。';
    case 'status.externalMarkdownOpenFailed': return 'システムアプリで Markdown を開けません：{error}';
    case 'empty.storageProtectionTitle': return 'データ保護モード';
    case 'empty.noPapersTitle': return 'デスクトップに紙片がありません';
    case 'empty.storageProtectionBody': return '元のデータは上書きされていません。先にバックアップの復元をお試しください。';
    case 'empty.noPapersBody': return 'ToDo 紙片またはノート紙片を作成して始めましょう。';
    case 'empty.noteStart': return 'クリックして記録を開始';
    case 'paper.note': return 'ノート';
    case 'paper.todo': return 'ToDo';
    case 'paper.todoCount': return 'ToDo {count}件';
    case 'paper.unnamedNote': return '無題のノート';
    case 'paper.unnamedTodo': return '無題の ToDo';
    case 'paper.notePaper': return 'ノート紙片';
    case 'paper.todoPaper': return 'ToDo 紙片';
    case 'paper.visible': return '表示';
    case 'paper.hidden': return '非表示';
    case 'paper.topmost': return '常に手前';
    case 'capsule.retractQueue': return '▾ 格納';
    case 'capsule.retractedCount': return '▸ {count} 件';
    case 'paper.capsule': return 'カプセル';
    case 'placeholder.todoItem': return 'ToDo 項目';
    case 'placeholder.addTodo': return 'ToDo を追加（複数行を貼り付け可能）';
    case 'placeholder.noteContent': return '何か書いてみましょう…';
    case 'link.to': return 'リンク先';
    case 'link.none': return 'なし';
    case 'link.invalid': return '無効';
    case 'quick.file': return '▤ ファイル';
    case 'quick.folder': return '▣ フォルダー';
    case 'quick.unnamed': return '名称未設定';
    case 'image.filterLabel': return '画像';
    case 'image.alt': return '画像';
    case 'image.missing': return '添付がありません';
    case 'markdown.sampleBold': return '**テキスト**';
    case 'markdown.sampleItalic': return '*テキスト*';
    case 'markdown.sampleStrike': return '~~テキスト~~';
    case 'markdown.sampleHeading': return '## 見出し';
    case 'markdown.sampleQuote': return '> 引用';
    case 'markdown.sampleList': return '- リスト';
    case 'markdown.sampleInlineCode': return 'インラインコード';
    case 'markdown.sampleLink': return '[リンク](https://)';
    case 'button.editShort': return '編';
    case 'button.browseShort': return '覧';
    case 'footer.autosave':
      return '編集はまずメモリに反映され、約 1 秒操作がないと保存します。入力が続く場合も約 10 秒で強制保存し、直前の正常な状態を保持します。';
    default: return '';
  }
}

function textKo(key: string): string {
  switch (key) {
    case 'language.system': return '시스템 설정 사용';
    case 'language.zhCN': return '중국어 간체';
    case 'language.en': return '영어';
    case 'language.ja': return '일본어';
    case 'language.ko': return '한국어';
    case 'app.subtitle': return '가벼운 할 일과 데스크톱 노트';
    case 'app.settingsSubtitle': return '설정';
    case 'tab.general': return '일반';
    case 'tab.shortcuts': return '단축키';
    case 'tab.papers': return '종이 메모';
    case 'tab.basic': return '기본';
    case 'tab.capsule': return '캡슐';
    case 'tab.visual': return '화면 표시';
    case 'section.basicBehavior': return '기본 동작';
    case 'section.capsule': return '캡슐';
    case 'section.singleScreenRightQueue': return '단일 화면 오른쪽 대기열';
    case 'section.visual': return '화면 표시';
    case 'section.generalBehavior': return '일반';
    case 'section.paperToolbar': return '종이 메모 제목 표시줄';
    case 'section.capsuleBehavior': return '캡슐';
    case 'section.data': return '데이터';
    case 'section.shortcuts': return '단축키';
    case 'section.systemEntry': return '시스템 진입점';
    case 'action.newTodo': return '☑ 할 일 만들기';
    case 'action.newNote': return '✎ 노트 만들기';
    case 'action.restorePapers': return '모든 종이 복원';
    case 'action.retryCapsules': return '가장자리 캡슐 다시 시도';
    case 'action.retrySave': return '저장 다시 시도';
    case 'status.capsuleRecovery': return '가장자리 캡슐을 표시하지 못했습니다. 종이는 펼친 상태로 유지되거나 복원되었습니다.';
    case 'status.exitSaveFailed': return '저장하지 못한 변경 사항이 있어 종료를 취소했습니다. 앱을 강제 종료하지 말고 저장을 다시 시도하세요.';
    case 'capsule.previousPage': return '이전 캡슐 페이지';
    case 'capsule.nextPage': return '다음 캡슐 페이지';
    case 'action.showAll': return '모두 표시';
    case 'action.hideAll': return '모두 숨기기';
    case 'action.restoreBackup': return '백업 복원';
    case 'action.focus': return '포커스';
    case 'action.show': return '표시';
    case 'action.hide': return '숨기기';
    case 'action.cancel': return '취소';
    case 'action.confirmDelete': return '삭제 확인';
    case 'action.confirm': return '확인';
    case 'action.edit': return '편집';
    case 'action.browse': return '미리 보기';
    case 'action.theme': return '테마';
    case 'action.collapse': return '접기';
    case 'action.newTodoShort': return '새 할 일';
    case 'action.newNoteShort': return '새 노트';
    case 'action.clearCompleted': return '완료 항목 지우기';
    case 'action.markDone': return '완료로 표시';
    case 'action.markUndone': return '미완료로 표시';
    case 'action.openAssociation': return '연결 열기';
    case 'action.addAssociation': return '연결 추가';
    case 'action.openContainingFolder': return '파일 위치 열기';
    case 'action.changeAssociation': return '연결 변경';
    case 'action.removeAssociation': return '연결 해제';
    case 'action.deleteTodo': return '항목 삭제';
    case 'action.dropTodoToDelete': return '여기에 놓아 할 일 삭제';
    case 'action.deletePaper': return '종이 삭제';
    case 'dialog.deletePaperTitle': return '이 종이 메모를 삭제할까요?';
    case 'dialog.deletePaperMessage': return '종이 메모 내용과 첨부 파일이 영구적으로 삭제되며 되돌릴 수 없습니다.';
    case 'action.expand': return '펼치기';
    case 'action.pin': return '항상 위';
    case 'action.unpin': return '항상 위 해제';
    case 'action.openExternally': return 'Markdown 외부에서 열기';
    case 'action.settings': return '설정';
    case 'action.exit': return 'PaperTodo 종료';
    case 'action.closeSettings': return '설정 닫기';
    case 'action.retryStatusBar': return '상태 표시줄 다시 시도';
    case 'action.retryingStatusBar': return '재시도 중…';
    case 'tray.newTodo': return '새 할 일';
    case 'tray.newNote': return '새 노트';
    case 'tray.toggleAll': return '모두 표시 / 숨기기';
    case 'setting.language': return '언어: ';
    case 'setting.theme': return '테마: ';
    case 'setting.colorScheme': return '색상: ';
    case 'setting.markdown': return 'Markdown: ';
    case 'setting.todoSize': return '할 일 크기: ';
    case 'setting.clearAfterComplete': return '완료 후 지우기: ';
    case 'setting.completedToBottom': return '완료 항목 아래로: ';
    case 'setting.paperLinks': return '새 종이 메모 연결 허용: ';
    case 'setting.hideLinkedPapersFromCapsules': return '연결된 종이를 캡슐 대기열에서 제외: ';
    case 'setting.imageCompression': return '큰 이미지 자동 압축: ';
    case 'setting.globalHotkeys': return '실행 중 전역 단축키: ';
    case 'setting.globalHotkeysHint':
      return '실행 중: Ctrl+Alt+S/H/P로 모두 표시/숨기기/전환, T/N으로 할 일/노트 생성, Q로 종료합니다.';
    case 'setting.animations': return '애니메이션: ';
    case 'setting.newTodoButton': return '종이 메모 도구 모음 새 할 일: ';
    case 'setting.newNoteButton': return '종이 메모 도구 모음 새 노트: ';
    case 'setting.externalOpenButton': return '종이 메모 도구 모음 외부 열기: ';
    case 'setting.capsule': return '캡슐: ';
    case 'setting.deepCapsule': return '사이드 캡슐: ';
    case 'setting.expandedDeepCapsule': return '종이 메모가 열려 있을 때도 사이드 캡슐 유지: ';
    case 'setting.masterCapsule': return '메인 캡슐: ';
    case 'setting.titleCharacters': return '제목 최대 글자 수: ';
    case 'setting.autoDockEdge': return '오른쪽 딥 캡슐 대기열: ';
    case 'setting.capsuleGap': return '캡슐 간격: ';
    case 'setting.rememberExpandedPosition': return '펼친 위치 기억: ';
    case 'setting.collapseOnSecondClick': return '열린 종이 메모의 사이드 캡슐을 다시 클릭해 접기: ';
    case 'setting.hideCloseOnHover': return '사이드 캡슐 닫기 버튼 숨기기: ';
    case 'setting.edgeTitle': return '사이드 캡슐 제목 글자 수: ';
    case 'setting.overallFontSize': return '종이 메모 내용 전체 글자 크기: ';
    case 'setting.noteFontSize': return '노트 글자 크기: ';
    case 'setting.noteBold': return '노트 굵게: ';
    case 'setting.todoBold': return '할 일 굵게: ';
    case 'setting.titleFontSize': return '제목 글자 크기: ';
    case 'setting.titleBold': return '제목 굵게: ';
    case 'setting.capsuleFontSize': return '캡슐 글자 크기: ';
    case 'setting.capsuleBold': return '캡슐 굵게: ';
    case 'setting.resizeHandle': return '크기 조절 표시: ';
    case 'setting.backupHint': return '복원 후 백업에서 표시 중이던 종이 메모를 다시 엽니다.';
    case 'setting.statusBarEntry': return '상태 표시줄 진입점';
    case 'value.enabled': return '켜짐';
    case 'value.disabled': return '꺼짐';
    case 'value.visible': return '표시';
    case 'value.hidden': return '숨김';
    case 'value.system': return '시스템 설정 사용';
    case 'value.light': return '라이트';
    case 'value.dark': return '다크';
    case 'value.warmPaper': return '따뜻한 종이';
    case 'value.ink': return '먹';
    case 'value.forest': return '숲';
    case 'value.sunset': return '노을';
    case 'value.markdownOff': return '사용 안 함';
    case 'value.markdownBasic': return '사용';
    case 'value.markdownEnhanced': return '향상';
    case 'value.small': return '작게';
    case 'value.medium': return '보통';
    case 'value.large': return '크게';
    case 'value.extraLarge': return '매우 크게';
    case 'value.all': return '전체';
    case 'value.characters': return '{count}자';
    case 'value.resizeStandard': return '표준';
    case 'value.resizeSoft': return '부드럽게';
    case 'value.resizeHidden': return '숨김';
    case 'status.storageProtectionDetected':
      return '기본 데이터와 백업이 모두 손상되었습니다. 데이터 보호 모드가 활성화되며 빈 데이터로 기존 저장 내용을 덮어쓰지 않습니다.';
    case 'status.hotkeysIdle': return '전역 단축키가 꺼져 있습니다';
    case 'status.hotkeysActive': return '전역 단축키가 등록되었습니다';
    case 'status.hotkeysConflict':
      return '단축키가 시스템 또는 다른 앱에서 사용 중입니다. 끈 후 다시 시도하세요.';
    case 'status.hotkeysUnsupported': return '이 기기에서는 전역 단축키를 지원하지 않습니다.';
    case 'status.hotkeysError': return '전역 단축키를 등록하지 못했습니다. 끈 후 다시 시도하세요.';
    case 'status.statusBarActive': return '상태 표시줄 진입점이 준비되었습니다';
    case 'status.statusBarUnknown': return '상태 표시줄 진입점 상태를 알 수 없습니다';
    case 'status.statusBarUnsupported': return '이 기기에서는 현재 상태 표시줄 진입점을 지원하지 않습니다';
    case 'status.statusBarRetrying': return '상태 표시줄 진입점을 복구하는 중…';
    case 'status.statusBarUncertain': return '시스템이 아직 진입점을 확인하지 않았습니다. 상주 Ability를 기다리는 중입니다';
    case 'status.statusBarResidentError': return '진입점은 추가되었지만 상주 Ability가 시작되지 않았습니다';
    case 'status.statusBarResidentRemoved': return '상주 Ability가 시작되지 않아 불완전한 진입점을 제거했습니다';
    case 'status.statusBarRemoveError': return '상태 표시줄 진입점을 제거하지 못했습니다. 앱을 다시 시작한 뒤 시도하세요.';
    case 'status.statusBarError': return '상태 표시줄 진입점을 사용할 수 없습니다. 여기서 다시 시도할 수 있습니다.';
    case 'status.openPaperFailed': return '종이 메모를 열 수 없습니다: {error}';
    case 'status.createBlockedByProtection': return '데이터 보호 중에는 새 종이 메모를 만들 수 없습니다.';
    case 'status.paperLimit': return '종이 메모는 최대 {count}개까지 지원합니다.';
    case 'status.noValidBackup': return '복원할 수 있는 유효한 백업이 없습니다';
    case 'status.backupRestored': return '마지막으로 정상 저장된 자동 백업을 복원했습니다';
    case 'status.createPaperBlocked': return '새 종이 메모를 만들 수 없습니다. 개수 제한에 도달했거나 데이터 보호 중입니다';
    case 'status.createPaperFailed': return '종이 메모 만들기 실패: {error}';
    case 'status.todoPasteLimit': return '한 번에 할 일을 최대 {count}개까지 추가할 수 있습니다';
    case 'status.linkedPaperMissing': return '연결된 종이 메모가 없습니다. 다시 연결하거나 연결을 해제하세요.';
    case 'status.openLinkedPaperFailed': return '연결된 종이 메모를 열 수 없습니다: {error}';
    case 'status.noteLengthLimit': return '노트가 안전한 길이 제한에 도달했습니다';
    case 'status.openLinkFailed': return '링크를 열 수 없습니다: {error}';
    case 'status.quickLaunchPickerFailed': return '빠른 실행 대상을 선택할 수 없습니다: {error}';
    case 'status.quickLaunchPermissionFailed': return '대상을 연결했지만 장기 접근 권한을 유지할 수 없습니다: {error}';
    case 'status.quickLaunchOpenFailed': return '빠른 실행 대상을 열 수 없습니다: {error}';
    case 'status.quickLaunchMissing': return '빠른 실행 대상이 유효하지 않습니다. 다시 선택하거나 연결을 해제하세요.';
    case 'status.quickLaunchDropUnsupported': return '드롭한 항목은 연결할 수 있는 파일 또는 폴더가 아닙니다.';
    case 'status.quickLaunchContainingFolderFailed': return '파일 위치를 열 수 없습니다: {error}';
    case 'status.paperLinkDropDisabled': return '종이 메모 연결이 설정에서 꺼져 있습니다.';
    case 'status.paperLinkDropSelf': return '할 일을 해당 항목이 있는 종이 메모에 연결할 수 없습니다.';
    case 'status.paperLinkDropLinked': return '“{title}”에 연결했습니다';
    case 'status.todoDragDeleted': return '할 일을 삭제했습니다. 실행 취소로 복원할 수 있습니다.';
    case 'status.imagePickerFailed': return '이미지를 선택할 수 없습니다: {error}';
    case 'status.imageDropUnsupported': return '드롭한 항목은 지원되는 이미지 파일이 아닙니다.';
    case 'status.imagePasteUnsupported': return '클립보드에 삽입할 수 있는 이미지가 없습니다.';
    case 'status.imagePastePermissionFailed': return '이번 붙여넣기에 대한 클립보드 접근 권한이 없습니다.';
    case 'status.imageImporting': return '이미지를 가져와 확인하는 중…';
    case 'status.imageImported': return '이미지를 가져와 노트에 삽입했습니다';
    case 'status.imageInputTooLarge': return '원본 이미지가 32 MiB 제한을 초과합니다';
    case 'status.imageDimensionsTooLarge': return '이미지 한 변이 4096픽셀 제한을 초과합니다';
    case 'status.imageCompressionDisabled': return '8 MiB 또는 2048px를 초과합니다. 큰 이미지 자동 압축을 켜세요.';
    case 'status.imageAnimatedTooLarge': return '애니메이션과 프레임을 보존하기 위해 초과 GIF/TIFF는 다시 인코딩하지 않습니다';
    case 'status.imageStorageFull': return '이미지 첨부 파일이 총 120 MiB 제한에 도달했습니다';
    case 'status.imageOutputTooLarge': return '압축한 이미지가 여전히 8 MiB 제한을 초과합니다';
    case 'status.imageInvalid': return '선택한 파일은 읽을 수 있는 이미지가 아닙니다';
    case 'status.imageImportFailed': return '이미지를 가져올 수 없습니다: {error}';
    case 'status.imageImportFailedGeneric': return '이미지를 가져올 수 없습니다. 접근 가능 여부와 형식을 확인하세요.';
    case 'status.externalMarkdownOpenFailed': return '시스템 앱에서 Markdown을 열 수 없습니다: {error}';
    case 'empty.storageProtectionTitle': return '데이터 보호 모드';
    case 'empty.noPapersTitle': return '바탕 화면에 종이 메모가 없습니다';
    case 'empty.storageProtectionBody': return '기존 데이터를 덮어쓰지 않았습니다. 먼저 백업 복원을 시도하세요.';
    case 'empty.noPapersBody': return '할 일 또는 노트 종이 메모를 만들어 시작하세요.';
    case 'empty.noteStart': return '클릭하여 기록 시작';
    case 'paper.note': return '노트';
    case 'paper.todo': return '할 일';
    case 'paper.todoCount': return '할 일 {count}개';
    case 'paper.unnamedNote': return '이름 없는 노트';
    case 'paper.unnamedTodo': return '이름 없는 할 일';
    case 'paper.notePaper': return '노트 종이';
    case 'paper.todoPaper': return '할 일 종이';
    case 'paper.visible': return '표시';
    case 'paper.hidden': return '숨김';
    case 'paper.topmost': return '항상 위';
    case 'paper.capsule': return '캡슐';
    case 'capsule.retractQueue': return '▾ 접기';
    case 'capsule.retractedCount': return '▸ {count}개';
    case 'placeholder.todoItem': return '할 일 항목';
    case 'placeholder.addTodo': return '할 일 추가 · 여러 줄 붙여넣기 가능';
    case 'placeholder.noteContent': return '무엇이든 적어 보세요…';
    case 'link.to': return '연결 대상';
    case 'link.none': return '없음';
    case 'link.invalid': return '유효하지 않음';
    case 'quick.file': return '▤ 파일';
    case 'quick.folder': return '▣ 폴더';
    case 'quick.unnamed': return '이름 없는 대상';
    case 'image.filterLabel': return '이미지';
    case 'image.alt': return '이미지';
    case 'image.missing': return '첨부 파일 없음';
    case 'markdown.sampleBold': return '**텍스트**';
    case 'markdown.sampleItalic': return '*텍스트*';
    case 'markdown.sampleStrike': return '~~텍스트~~';
    case 'markdown.sampleHeading': return '## 제목';
    case 'markdown.sampleQuote': return '> 인용';
    case 'markdown.sampleList': return '- 목록';
    case 'markdown.sampleInlineCode': return '인라인 코드';
    case 'markdown.sampleLink': return '[링크](https://)';
    case 'button.editShort': return '편';
    case 'button.browseShort': return '보';
    case 'footer.autosave':
      return '편집 내용은 먼저 메모리에 반영되고 약 1초 동안 입력이 없으면 저장됩니다. 계속 입력해도 약 10초마다 강제 저장하며 이전의 정상 상태를 보관합니다.';
    default: return '';
  }
}
