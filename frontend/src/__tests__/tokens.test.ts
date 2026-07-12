import fs from 'fs';
import path from 'path';

describe('デザイントークンCSSファイルのテスト', () => {
  const tokensPath = path.resolve(__dirname, '../styles/tokens.css');

  it('tokens.cssファイルが存在すること', () => {
    expect(fs.existsSync(tokensPath)).toBe(true);
  });

  it('主要なカラーコードが正しく定義されていること', () => {
    const content = fs.readFileSync(tokensPath, 'utf8');
    expect(content).toContain('--blue-dark:');
    expect(content).toContain('#0d2f8a');
    expect(content).toContain('--blue-primary:');
    expect(content).toContain('#1a4fdb');
    expect(content).toContain('--blue-light:');
    expect(content).toContain('#3b6ef8');
    expect(content).toContain('--gold:');
    expect(content).toContain('#f5a623');
    expect(content).toContain('--gold-light:');
    expect(content).toContain('#ffd07a');
  });

  it('モノクロ色やタイポグラフィ変数が定義されていること', () => {
    const content = fs.readFileSync(tokensPath, 'utf8');
    expect(content).toContain('--white:');
    expect(content).toContain('--bg-gray:');
    expect(content).toContain('--border:');
    expect(content).toContain('--text-xs:');
    expect(content).toContain('--text-stat:');
    expect(content).toContain('3.6rem');
  });

  it('角丸、シャドウ、トランジション変数が定義されていること', () => {
    const content = fs.readFileSync(tokensPath, 'utf8');
    expect(content).toContain('--radius-sm:');
    expect(content).toContain('6px');
    expect(content).toContain('--radius-full:');
    expect(content).toContain('9999px');
    expect(content).toContain('--shadow-card:');
    expect(content).toContain('--shadow-card-hover:');
    expect(content).toContain('--shadow-btn-primary:');
    expect(content).toContain('--transition-fast:');
    expect(content).toContain('--transition-slow:');
  });
});
