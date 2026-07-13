import { test, expect } from '@playwright/test';

test.describe('Common Layout', () => {
  test.use({ locale: 'ja-JP' });

  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
  });

  test('should render sidebar with correct width and background color', async ({ page }) => {
    const sidebar = page.locator('aside.sidebar');
    await expect(sidebar).toBeVisible();

    const box = await sidebar.boundingBox();
    expect(box?.width).toBe(196);

    const backgroundColor = await sidebar.evaluate((el) => {
      return window.getComputedStyle(el).backgroundColor;
    });
    expect(backgroundColor).toBe('rgb(13, 47, 138)'); // rgb for #0d2f8a
  });

  test('should render sidebar navigation with 8 items and icons', async ({ page }) => {
    const navItems = page.locator('aside.sidebar nav a');
    await expect(navItems).toHaveCount(8);

    const expectedItems = [
      'ダッシュボード',
      'サイト一覧',
      'ヒートマップ',
      'ファネル',
      'リテンション',
      'パフォーマンス',
      'アラート',
      'AIレコメンデーション'
    ];

    for (let i = 0; i < expectedItems.length; i++) {
      const item = navItems.nth(i);
      await expect(item).toContainText(expectedItems[i]);
      const icon = item.locator('svg');
      await expect(icon).toBeVisible();
    }
  });

  test('should render header with correct height, white background, search box and user menu', async ({ page }) => {
    const header = page.locator('header.header');
    await expect(header).toBeVisible();

    const box = await header.boundingBox();
    expect(box?.height).toBe(54);

    const backgroundColor = await header.evaluate((el) => {
      return window.getComputedStyle(el).backgroundColor;
    });
    expect(backgroundColor).toBe('rgb(255, 255, 255)');

    const searchBox = header.locator('.search-box');
    await expect(searchBox).toBeVisible();
    await expect(searchBox.locator('input')).toBeVisible();

    const userMenu = header.locator('.user-menu');
    await expect(userMenu).toBeVisible();
  });

  test('should highlight active nav item', async ({ page }) => {
    const activeItem = page.locator('aside.sidebar nav a.active');
    await expect(activeItem).toBeVisible();
    await expect(activeItem).toContainText('ダッシュボード');
    await expect(activeItem).toHaveClass(/active/);
  });

  test('should allow toggling and switching language', async ({ page }) => {
    const langBtn = page.locator('.language-btn');
    await expect(langBtn).toBeVisible();
    await expect(langBtn).toContainText('日本語');

    // Click language button to show dropdown
    await langBtn.click();
    const dropdown = page.locator('.language-dropdown');
    await expect(dropdown).toBeVisible();

    // Click English option
    const enOption = dropdown.locator('button', { hasText: 'English' });
    await enOption.click();

    // Verification: active language button updates and text changes
    await expect(langBtn).toContainText('English');

    // Sidebar items should update to English
    const navItems = page.locator('aside.sidebar nav a');
    await expect(navItems.nth(0)).toContainText('Dashboard');
    await expect(navItems.nth(1)).toContainText('Sites');
  });

  test('should allow toggling user settings dropdown', async ({ page }) => {
    const userMenu = page.locator('.user-menu');
    await expect(userMenu).toBeVisible();

    // Dropdown should not be visible initially
    const dropdown = userMenu.locator('.user-dropdown');
    await expect(dropdown).not.toBeVisible();

    // Click user menu to open
    await userMenu.click();
    await expect(dropdown).toBeVisible();

    // Click again to close
    await page.click('body');
    await expect(dropdown).not.toBeVisible();
  });
});
