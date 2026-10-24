#!/usr/bin/env node
// Builds the PasteNext disk image with a drag-and-drop guide background.
//
// The .DS_Store is written with the same `ds-store` helper that appdmg uses,
// which is the format Finder actually reads: a `vSrn` record, a `bwsp` window
// record (with the background alias in `icvp`) and one `Iloc` record per item.
//
// Usage:
//   node scripts/dmg/build.mjs --app <app> --background <png> --out <dmg>
//        [--title <name>] [--width N] [--height N]
//        [--app-x N] [--app-y N] [--apps-x N] [--apps-y N]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import DSStore from 'ds-store';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
    const out = {};
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (!a.startsWith('--')) continue;
        const key = a.slice(2);
        const next = argv[i + 1];
        if (next === undefined || next.startsWith('--')) {
            out[key] = true;
        } else {
            out[key] = next;
            i++;
        }
    }
    return out;
}

const args = parseArgs(process.argv.slice(2));
for (const required of ['app', 'background', 'out']) {
    if (!args[required]) {
        console.error('usage: build.mjs --app <app> --background <png> --out <dmg> [--title <name>]');
        process.exit(1);
    }
}

const appPath = path.resolve(args.app);
const background = path.resolve(args.background);
const outPath = path.resolve(args.out);
const title = args.title || path.basename(appPath).replace(/\.app$/, '');

// The artwork is authored for the visible content area of the window.
const WIDTH = Number(args.width || 640);
const HEIGHT = Number(args.height || 330);
const APP_X = Number(args['app-x'] ?? 124);
const APP_Y = Number(args['app-y'] ?? 100);
const APPS_X = Number(args['apps-x'] ?? 515);
const APPS_Y = Number(args['apps-y'] ?? 100);

function run(cmd, cmdArgs) {
    return execFileSync(cmd, cmdArgs, {stdio: ['ignore', 'pipe', 'pipe']});
}

// ---- staging -------------------------------------------------------------

const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'pastenext-dmg-'));
const staging = path.join(stage, 'stage');
fs.mkdirSync(path.join(staging, '.background'), {recursive: true});

fs.cpSync(appPath, path.join(staging, path.basename(appPath)), {recursive: true});
fs.copyFileSync(background, path.join(staging, '.background', path.basename(background)));
fs.symlinkSync('/Applications', path.join(staging, 'Applications'));

console.log(`staging ${staging}`);

// ---- disk image ----------------------------------------------------------

const rawImage = path.join(stage, 'image.dmg');
run('hdiutil', ['create', '-srcfolder', staging, '-ov', '-format', 'UDRW', '-volname', title, rawImage]);

// ---- .DS_Store -----------------------------------------------------------

const mounted = path.join(stage, 'mnt');
fs.mkdirSync(mounted, {recursive: true});
run('hdiutil', ['attach', rawImage, '-mountpoint', mounted, '-nobrowse', '-readwrite', '-quiet']);

const ds = new DSStore();
ds.vSrn(1);
ds.setIconSize(96);
// The background image lives in .background/ and is referenced by an alias.
ds.setBackgroundPath(path.join(mounted, '.background', path.basename(background)));
// The window is the artwork plus Finder's title bar (ds-store adds the 22pt).
ds.setWindowSize(WIDTH, HEIGHT);
ds.setWindowPos(100, 100);
// Iloc coordinates are the icon centres, measured from the window's
// bottom-left. The window is taller than the artwork because Finder adds a
// title bar and a path bar above the content area, so the artwork's
// coordinates have to be shifted up by that chrome.
// The window is the artwork plus Finder's title bar, and the artwork is
// painted into the content area below it. Iloc is measured from the window's
// bottom-left edge, so an artwork coordinate converts with:
//     windowY = artworkHeight - artworkY
const TITLE_BAR = 22;
const toWindow = (artY) => HEIGHT - artY;
ds.setIconPos(path.basename(appPath), APP_X, toWindow(APP_Y));
ds.setIconPos('Applications', APPS_X, toWindow(APPS_Y));

await new Promise((resolve, reject) => {
    ds.write(path.join(mounted, '.DS_Store'), (err) => (err ? reject(err) : resolve()));
});
console.log('ds_store written');

run('hdiutil', ['detach', mounted, '-quiet']);

// ---- final read-only image ----------------------------------------------

fs.rmSync(outPath, {force: true});
run('hdiutil', ['convert', rawImage, '-format', 'UDZO', '-o', outPath]);
fs.rmSync(stage, {recursive: true, force: true});

console.log(`dmg: ${outPath}`);
