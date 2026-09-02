# 3.3.3 root causes

1. The hidden `EntryAbility` owned the HOME skill even though Settings lived in `ManagerAbility`; taskbar/launcher activation therefore targeted the wrong singleton mission.
2. The capsule host used a fixed 200vp master-row width and retained full member rows at opacity zero when retracted, so the native host remained much larger than the visible UI.
3. Native capsule window styling could stop after an unsupported window call before transparency was applied; transparency also needed to be reasserted after ArkUI content loading.
4. Cross-window drag association remains unreliable on the current HarmonyOS PC device path, so the drag affordance is hidden rather than advertised as usable.
