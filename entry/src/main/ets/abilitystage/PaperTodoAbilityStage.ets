import { AbilityStage, Want } from '@kit.AbilityKit';

export default class PaperTodoAbilityStage extends AbilityStage {
  onAcceptWant(want: Want): string {
    if (want.abilityName === 'PaperAbility' && want.parameters) {
      const rawId: Object | undefined = want.parameters.paperId;
      if (rawId !== undefined && rawId !== null) {
        return 'PaperTodo_' + String(rawId);
      }
    }
    return 'PaperTodo_Entry';
  }
}
