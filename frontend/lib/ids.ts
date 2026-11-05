// Small impure helpers kept out of components so the React Compiler's purity
// lint rule does not flag them inside event handlers.
export function createId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function now(): Date {
  return new Date();
}
