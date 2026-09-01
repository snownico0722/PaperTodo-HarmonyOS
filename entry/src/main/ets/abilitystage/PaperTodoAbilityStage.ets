import { AbilityStage, Want } from '@kit.AbilityKit';

export default class PaperTodoAbilityStage extends AbilityStage {
  onAcceptWant(want: Want): string {
    if ((want.abilityName === 'PaperAbility' || want.abilityName === 'EdgeCapsuleAbility') && want.parameters) {
      const rawId: Object | undefined = want.parameters.paperId;
      if (rawId !== undefined && rawId !== null) {
        return (want.abilityName === 'EdgeCapsuleAbility' ? 'PaperTodo_Edge_' : 'PaperTodo_Paper_') + String(rawId);
      }
    }
    return 'PaperTodo_Entry';
  }
}
