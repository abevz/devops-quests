// Keep the raw probe output available; render known condition messages in the reading language.
export function diagnosticMessages(detail, messages = {}) {
  return detail.split("\n").flatMap((line) => {
    const match = line.match(/\[DQ:([a-z0-9_]+)\]/);
    return match && Object.hasOwn(messages, match[1]) ? [messages[match[1]]] : [];
  });
}
