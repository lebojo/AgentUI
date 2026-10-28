fetch("https://api.github.com/repos/lebojo/AgentUI/releases/latest")
  .then((response) => (response.ok ? response.json() : null))
  .then((release) => {
    if (!release || !release.tag_name) return;
    const tag = release.tag_name.replace(/^v/, "");
    document.querySelectorAll("[data-version]").forEach((el) => {
      el.textContent = `v${tag}`;
    });
  })
  .catch(() => {});
