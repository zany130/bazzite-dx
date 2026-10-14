// Run with Node 24 and RENOVATE_ROOT pointing to renovate@44.155.8's package.
// Uses Renovate's actual extractor, attachment mapper, and replacement code.
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(process.env.RENOVATE_ROOT);
const require = createRequire(pathToFileURL(`${root}/package.json`));
const load = (path) => import(pathToFileURL(`${root}/dist/${path}.js`));
const { init } = await load('logger/index');
await init();
const { extractPackageFile } = await load('modules/manager/custom/regex/index');
const { GithubReleaseAttachmentsDatasource } = await load('modules/datasource/github-release-attachments/index');
const { doAutoReplace } = await load('workers/repository/update/branch/auto-replace');
const { GlobalConfig } = await load('config/global');
const temp = mkdtempSync(`${tmpdir()}/refind-renovate-`);
GlobalConfig.set({ localDir: temp });
process.on('exit', () => rmSync(temp, { recursive: true, force: true }));
const config = require('json5').parse(readFileSync(new URL('../.github/renovate.json5', import.meta.url), 'utf8'));
const text = readFileSync(new URL('../build_files/build.sh', import.meta.url), 'utf8');
const file = 'build_files/build.sh';
const all = config.customManagers.flatMap((m) => extractPackageFile(text, file, m)?.deps ?? []);
assert.equal(all.filter((d) => d.depName === 'jlobue10/rEFInd_GUI').length, 1);
for (const name of ['zany130/cockpit-probe', 'zany130/cockpit-diagnostics', 'realmcuser/cockpit-nspawn']) {
  assert.equal(all.filter((d) => d.depName === name).length, 1);
}
const manager = config.customManagers.find((m) => m.datasourceTemplate === 'github-release-attachments');
const oldHash = 'c4d20874c8a43e2c9ce50641cfce031f1b7fa72e37902ad37bbf544f1cb428dd';
const newHash = '36841b85b1d250bf3e02bc8525234fce7e78346595ce5a78baa6260c4acbd208';
const current = extractPackageFile(text, file, manager).deps[0];
// Historical release fixture, independent of whichever version is now pinned.
const historical = text.replace(`REFIND_GUI_VERSION="${current.currentValue}"`, 'REFIND_GUI_VERSION="v3.4.6"')
  .replace(`REFIND_GUI_SHA256="${current.currentDigest}"`, `REFIND_GUI_SHA256="${oldHash}"`);
const asset = (v) => `rEFInd_GUI-${v.slice(1)}-1.fc44.x86_64.rpm`;
const release = (v) => ({ tag_name: v, html_url: `https://github.com/jlobue10/rEFInd_GUI/releases/tag/${v}`,
  assets: [{ name: `${asset(v)}.sha256`, size: 101,
    browser_download_url: `https://github.com/jlobue10/rEFInd_GUI/releases/download/${v}/${asset(v)}.sha256` }] });
const datasource = new GithubReleaseAttachmentsDatasource();
// Recorded release-sidecar shape; transport is mocked, mapping logic is real.
datasource.http = {
  async getJsonUnchecked(url) { return { body: release(url.split('/').at(-1)) }; },
  async getText(url) {
    const v = url.includes('/v3.4.6/') ? 'v3.4.6' : 'v3.4.7';
    return { body: `${v === 'v3.4.6' ? oldHash : newHash}  ${asset(v)}\n` };
  },
};
const dep = extractPackageFile(historical, file, manager).deps[0];
assert.equal(dep.currentValue, 'v3.4.6');
assert.equal(dep.currentDigest, oldHash);
const digest = await datasource.getDigest({ packageName: dep.depName, currentValue: dep.currentValue,
  currentDigest: dep.currentDigest }, 'v3.4.7');
assert.equal(digest, newHash);
const result = await doAutoReplace({ ...manager, ...dep, manager: 'regex', packageFile: file,
  depIndex: 0, newValue: 'v3.4.7', newDigest: digest }, historical, false);
assert.equal(result, historical.replace('REFIND_GUI_VERSION="v3.4.6"', 'REFIND_GUI_VERSION="v3.4.7"')
  .replace(`REFIND_GUI_SHA256="${oldHash}"`, `REFIND_GUI_SHA256="${newHash}"`));
assert.equal(extractPackageFile(result, file, manager).deps[0].currentDigest, newHash);
console.log('PASS: one rEFInd match, other dependencies retained, actual attachment mapping and version/digest replacement (v3.4.6 -> v3.4.7)');
