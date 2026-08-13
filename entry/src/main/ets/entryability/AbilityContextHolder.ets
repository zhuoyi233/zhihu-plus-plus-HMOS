import { common } from '@kit.AbilityKit';

let currentAbilityContext: common.UIAbilityContext | undefined = undefined;

export function setAbilityContext(context: common.UIAbilityContext): void {
  currentAbilityContext = context;
}

export function getAbilityContext(): common.UIAbilityContext | undefined {
  return currentAbilityContext;
}

export function clearAbilityContext(): void {
  currentAbilityContext = undefined;
}
