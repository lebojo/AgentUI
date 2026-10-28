(() => {
  const bay = document.querySelector(".bay");
  const announce = document.querySelector("[data-announce]");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
  const slotLists = () => [...bay.querySelectorAll(".slots")];
  const bayName = (list) => list.closest(".rack").dataset.bay;
  const stripName = (strip) => strip.querySelector(".f-call b").textContent;

  function say(text) {
    announce.textContent = text;
  }

  function flip(strips, mutate) {
    const before = new Map(strips.map((s) => [s, s.getBoundingClientRect()]));
    mutate();
    if (reduceMotion.matches) return;
    for (const [strip, rect] of before) {
      const after = strip.getBoundingClientRect();
      const dx = rect.left - after.left;
      const dy = rect.top - after.top;
      if (!dx && !dy) continue;
      strip.animate(
        [{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }],
        { duration: 450, easing: "cubic-bezier(0.16, 1, 0.3, 1)" }
      );
    }
  }

  const allStrips = () => [...bay.querySelectorAll(".strip")];

  let drag = null;

  function onPointerDown(event) {
    const strip = event.target.closest(".strip");
    if (!strip || event.button !== 0) return;
    event.preventDefault();
    const rect = strip.getBoundingClientRect();
    drag = {
      strip,
      startX: event.clientX,
      startY: event.clientY,
      offsetX: event.clientX - rect.left,
      offsetY: event.clientY - rect.top,
      width: rect.width,
      ghost: null,
      origin: strip.parentElement,
      active: false,
    };
    strip.setPointerCapture(event.pointerId);
  }

  function startDrag() {
    const { strip, width } = drag;
    const ghost = document.createElement("li");
    ghost.className = "strip-ghost";
    ghost.setAttribute("aria-hidden", "true");
    strip.after(ghost);
    drag.ghost = ghost;
    strip.style.width = `${width}px`;
    strip.classList.add("is-dragging");
    drag.active = true;
  }

  function targetFor(x, y) {
    let best = null;
    for (const list of slotLists()) {
      const r = list.getBoundingClientRect();
      const dist = y < r.top ? r.top - y : y > r.bottom ? y - r.bottom : 0;
      if (x >= r.left - 40 && x <= r.right + 40 && (!best || dist < best.dist)) {
        best = { list, dist };
      }
    }
    return best && best.dist < 60 ? best.list : null;
  }

  function onPointerMove(event) {
    if (!drag) return;
    if (!drag.active) {
      if (Math.hypot(event.clientX - drag.startX, event.clientY - drag.startY) < 5) return;
      startDrag();
    }
    const { strip, ghost } = drag;
    strip.style.left = `${event.clientX - drag.offsetX}px`;
    strip.style.top = `${event.clientY - drag.offsetY}px`;

    const list = targetFor(event.clientX, event.clientY);
    slotLists().forEach((l) => l.classList.toggle("is-target", l === list));
    if (!list) return;
    const siblings = [...list.querySelectorAll(".strip:not(.is-dragging)")];
    const next = siblings.find((s) => {
      const r = s.getBoundingClientRect();
      return event.clientY < r.top + r.height / 2;
    });
    const others = allStrips().filter((s) => s !== strip);
    if (next && next.previousElementSibling !== ghost) {
      flip(others, () => list.insertBefore(ghost, next));
    } else if (!next && list.lastElementChild !== ghost) {
      flip(others, () => list.appendChild(ghost));
    }
  }

  function onPointerUp() {
    if (!drag) return;
    const { strip, ghost, origin, active } = drag;
    drag = null;
    slotLists().forEach((l) => l.classList.remove("is-target"));
    if (!active) return;
    const from = strip.getBoundingClientRect();
    ghost.replaceWith(strip);
    strip.classList.remove("is-dragging");
    strip.style.cssText = "";
    const to = strip.getBoundingClientRect();
    if (!reduceMotion.matches) {
      strip.animate(
        [{ transform: `translate(${from.left - to.left}px, ${from.top - to.top}px) rotate(-1.2deg)` }, { transform: "none" }],
        { duration: 500, easing: "cubic-bezier(0.16, 1, 0.3, 1)" }
      );
    }
    if (strip.parentElement !== origin) {
      say(`${stripName(strip)} moved to ${bayName(strip.parentElement)}. No files moved.`);
    }
  }

  function onKeyDown(event) {
    const strip = event.target.closest(".strip");
    if (!strip || !event.altKey || !["ArrowUp", "ArrowDown"].includes(event.key)) return;
    event.preventDefault();
    const lists = slotLists();
    const list = strip.parentElement;
    const up = event.key === "ArrowUp";
    const sibling = up ? strip.previousElementSibling : strip.nextElementSibling;
    flip(allStrips(), () => {
      if (sibling) {
        up ? sibling.before(strip) : sibling.after(strip);
      } else {
        const target = lists[lists.indexOf(list) + (up ? -1 : 1)];
        if (!target) return;
        up ? target.appendChild(strip) : target.prepend(strip);
      }
    });
    strip.focus();
    say(`${stripName(strip)} is in ${bayName(strip.parentElement)}, position ${[...strip.parentElement.children].indexOf(strip) + 1}.`);
  }

  bay.addEventListener("pointerdown", onPointerDown);
  bay.addEventListener("pointermove", onPointerMove);
  bay.addEventListener("pointerup", onPointerUp);
  bay.addEventListener("pointercancel", onPointerUp);
  bay.addEventListener("keydown", onKeyDown);

  const queue = [
    { name: "Perf", agent: "claude", label: "Claude", project: "storefront", branch: "perf/images", use: ["5H 44%", "WK 19%"] },
    { name: "Lint", agent: "codex", label: "Codex", project: "website", branch: "chore/lint", use: ["5H 13%", "WK 31%"] },
    { name: "Spike", agent: "claude", label: "Claude", project: "swiftterm", branch: "spike/sixel", use: ["5H 47%", "WK 20%"] },
  ];
  let printed = 0;
  const printer = bay.querySelector("[data-print]");

  printer.addEventListener("click", () => {
    const item = queue[printed % queue.length];
    printed += 1;
    const strip = document.createElement("li");
    strip.className = "strip is-printed";
    strip.dataset.agent = item.agent;
    strip.tabIndex = 0;
    strip.dataset.printed = "";
    strip.innerHTML = `
      <span class="f-call"><b></b><small></small></span>
      <span class="f-route"><span class="f-proj"></span><span class="f-branch"></span></span>
      <span class="f-state"><i class="dot on"></i>Running</span>
      <span class="f-use"><small></small></span>`;
    strip.querySelector(".f-call b").textContent = item.name;
    strip.querySelector(".f-call small").textContent = item.label;
    strip.querySelector(".f-proj").textContent = item.project;
    strip.querySelector(".f-branch").textContent = item.branch;
    strip.querySelector(".f-use").prepend(item.use[0]);
    strip.querySelector(".f-use small").textContent = item.use[1];

    const target = slotLists()[0];
    const extra = bay.querySelectorAll("[data-printed]");
    flip(allStrips(), () => {
      if (extra.length >= 2) extra[0].remove();
      target.prepend(strip);
    });
    strip.addEventListener("animationend", () => strip.classList.remove("is-printed"), { once: true });
    say(`New worktree ${item.branch} with a ${item.label} terminal, filed in ${bayName(target)}.`);
  });

  fetch("https://api.github.com/repos/lebojo/AgentUI/releases/latest")
    .then((response) => (response.ok ? response.json() : null))
    .then((release) => {
      if (!release || !release.tag_name) return;
      const tag = release.tag_name.replace(/^v/, "");
      document.querySelectorAll("[data-version]").forEach((el) => {
        el.textContent = el.textContent.startsWith("v") ? `v${tag}` : tag;
      });
    })
    .catch(() => {});
})();
