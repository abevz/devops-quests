export function storageGet(key, access = () => globalThis.localStorage) {
  try {
    return access().getItem(key);
  } catch {
    return null;
  }
}
export function storageSet(key, value, access = () => globalThis.localStorage) {
  try {
    access().setItem(key, value);
    return true;
  } catch {
    return false;
  }
}
export const sidebarKey = (base, user) => `dq-sidebar:${encodeURIComponent(base)}:${encodeURIComponent(user)}`;
export const readCollapsed = (key, access) => storageGet(key, access) === "1";
export const saveCollapsed = (key, value, access) => (storageSet(key, value ? "1" : "0", access) ? value : false);

const paths = {
  map: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  bay: "M3 4h18v16H3z M6 8l4 4-4 4 M13 16h5",
  guides: "M12 5C9 3 5 3 2 4v15c3-1 7-1 10 1 3-2 7-2 10-1V4c-3-1-7-1-10 1z M12 5v15",
  labs: "M9 3h6 M10 3v7l-6 9a1 1 0 0 0 1 2h14a1 1 0 0 0 1-2l-6-9V3 M8 14h8",
  interview: "M3 4h18v12H9l-6 5z M7 8h10 M7 12h7",
  profile: "M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0 M4 21v-2a8 8 0 0 1 16 0v2",
  scoring: "M4 20h17 M7 16V9 M12 16V4 M17 16v-5",
  theme: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20 M12 2v20",
  logout: "M10 3H4v18h6 M10 12h11 M16 7l5 5-5 5",
  collapse: "M3 4h18v16H3z M8 4v16 M17 9l-3 3 3 3",
};
export function installNavigationIcons(root = document) {
  for (const item of root.querySelectorAll("[data-nav-icon]")) {
    const svg = root.createElementNS("http://www.w3.org/2000/svg", "svg");
    for (const [key, value] of Object.entries({
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "1.7",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      "aria-hidden": "true",
      focusable: "false",
      class: "nav-icon",
    }))
      svg.setAttribute(key, value);
    const path = root.createElementNS(svg.namespaceURI, "path");
    path.setAttribute("d", paths[item.dataset.navIcon]);
    svg.append(path);
    item.prepend(svg);
  }
}
