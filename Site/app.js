fetch("https://api.github.com/repos/lebojo/Heka/releases/latest")
  .then((response) => (response.ok ? response.json() : null))
  .then((release) => {
    if (!release || !release.tag_name) return;
    const tag = release.tag_name.replace(/^v/, "");
    document.querySelectorAll("[data-version]").forEach((el) => {
      el.textContent = `v${tag}`;
    });
    const archive = (release.assets || []).find((asset) => asset.name.endsWith(".zip"));
    if (!archive) return;
    document.querySelectorAll("[data-download]").forEach((el) => {
      el.href = archive.browser_download_url;
    });
    document.querySelectorAll("[data-download-name]").forEach((el) => {
      el.textContent = archive.name;
    });
  })
  .catch(() => {});
