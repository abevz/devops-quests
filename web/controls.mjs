export function keySequence(key, ctrl = false, alt = false, applicationCursor = false) {
  const keys = {
    Tab: "\t",
    Esc: "\x1b",
    Left: "\x1b[D",
    Right: "\x1b[C",
    Up: "\x1b[A",
    Down: "\x1b[B",
    Enter: "\r",
    Insert: "\x1b[2~",
    Delete: "\x1b[3~",
    Home: "\x1b[H",
    End: "\x1b[F",
    Backspace: "\x7f",
  };
  let text = keys[key] ?? key;
  if (applicationCursor) {
    const arrows = { Up: "A", Down: "B", Right: "C", Left: "D", Home: "H", End: "F" };
    if (arrows[key]) text = "\x1bO" + arrows[key];
  }
  if (ctrl && text.length === 1) text = String.fromCharCode(text.toUpperCase().charCodeAt(0) & 31);
  return (alt ? "\x1b" : "") + text;
}
