// Use the actual sidebar rename dialog; no hidden filename input is required.
async function renameDraft(page, name) {
  const toggle = page.locator('#toolsDrawer');
  const wasOpen = await toggle.getAttribute('aria-expanded') === 'true';
  if (!wasOpen) await toggle.click();
  await page.locator('[data-tools-rename]').click();
  await page.locator('#bs-prompt-input').fill(name);
  await page.locator('#bs-prompt-ok').click();
  if (!wasOpen) {
    const close = page.locator('#toolsSidebarClose');
    if (await close.isVisible()) await close.click();
    else await toggle.click();
  }
}
module.exports = {renameDraft};
