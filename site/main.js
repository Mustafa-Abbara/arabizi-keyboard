// Harfi's website: shared by the English page and the Arabic one. The words it writes (the copy button) come from the
// page's own data attributes, so each page keeps its language.

// The hero types the Arabizi, then shows the Arabic, for a few examples in turn: real typed messages with their checked
// Arabic from the training data (data/pairs/train-hand.jsonl: hw-7739, hw-13179, hw-16809, hw-7738). Without scripts
// (or with reduced motion) the first example stays as written in the page.
const examples = [
  ["Shu l wade3 aandak", "شو الوضع عندك"],
  ["Yalla shway w beb3at el list", "يلا شوي وببعت ال list"],
  ["Hala2 bokra mnshuf shu mnaamol", "هلق بكرا منشوف شو منعمل"],
  ["W ana ha e5od half day tuesday", "وأنا رح آخد half day tuesday"],
];
const typed = document.getElementById("typed"), arabic = document.getElementById("arabic");
const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const wait = ms => new Promise(done => setTimeout(done, ms));
async function play() {
  for (let i = 0; ; i = (i + 1) % examples.length) {
    const [latin, ar] = examples[i];
    arabic.classList.add("hidden");
    for (let n = 0; n <= latin.length; n++) { typed.textContent = latin.slice(0, n); await wait(55); }
    await wait(350);
    arabic.textContent = ar;
    arabic.classList.remove("hidden");
    await wait(2600);
  }
}
if (!still) play();

// Light or dark: the system's choice until the visitor presses the header button, then theirs (remembered in this
// browser, for both pages). The icon shows the theme now in use; without scripts the page follows the system.
const root = document.documentElement, themeButton = document.getElementById("theme");
const systemDark = window.matchMedia("(prefers-color-scheme: dark)");
const isDark = () => root.dataset.theme ? root.dataset.theme === "dark" : systemDark.matches;
function paintTheme() {
  root.classList.toggle("dark-now", isDark());
  themeButton.setAttribute("aria-pressed", String(isDark()));
}
themeButton.hidden = false;
paintTheme();
systemDark.addEventListener("change", paintTheme);
themeButton.addEventListener("click", () => {
  root.dataset.theme = isDark() ? "light" : "dark";
  try { localStorage.setItem("theme", root.dataset.theme); } catch {}
  paintTheme();
});

// Mac or Windows: the install steps and keys for one at a time, chosen from the visitor's system (Mac when it is
// neither), switched with the tabs or the hero's buttons. Without scripts both are shown, one after the other.
root.classList.add("js");
const tabs = document.querySelector(".tabs");
tabs.hidden = false;
function show(platform) {
  tabs.querySelectorAll("button").forEach(tab => tab.setAttribute("aria-selected", String(tab.dataset.platform === platform)));
  document.querySelectorAll(".platform").forEach(part => { part.hidden = part.dataset.platform !== platform; });
  document.querySelectorAll(".actions .button").forEach(button =>
    button.classList.toggle("secondary", button.dataset.platform !== platform));
}
const system = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || navigator.userAgent;
show(/win/i.test(system) ? "windows" : "mac");
tabs.addEventListener("click", event => { const tab = event.target.closest("button"); if (tab) show(tab.dataset.platform); });
document.querySelectorAll(".actions .button").forEach(button =>
  button.addEventListener("click", () => show(button.dataset.platform)));

// Copy buttons: the command in the same box. Their words: data-copied, data-failed, and the button's own text.
document.querySelectorAll(".cmd button").forEach(button => {
  const label = button.textContent;
  button.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(button.parentElement.querySelector("code").textContent); button.textContent = button.dataset.copied; }
    catch { button.textContent = button.dataset.failed; }
    setTimeout(() => { button.textContent = label; }, 1800);
  });
});
