import { test, expect } from '@playwright/test';

test('should navigate to the home page and see the heading', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('h1')).toContainText('web-insight-api');
});
