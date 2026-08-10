export function isApiAvailable(currentApiLevel: number, requiredApiLevel: number): boolean {
  return currentApiLevel >= requiredApiLevel;
}
