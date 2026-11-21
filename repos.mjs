#!/usr/bin/env node
/**
 * Every repository of the Luna workspace at once: the submodules (luna-auth,
 * luna-dashboard, luna-pages, luna-files, luna-forms, luna-keys, luna-cli —
 * from .gitmodules) and this repository, which records which of their
 * commits go together.
 *
 *   node repos.mjs status                         git of each: branch, changes, ↑ to push ↓ to pull, version (gtr.json)
 *   node repos.mjs commit "message" [--push]      git add -A + commit in every changed submodule, then here
 *                                                 (the new submodule commits and this repository's own changes)
 *   node repos.mjs push                           git push (and tags) in every submodule, then here
 *   node repos.mjs pull                           git pull --ff-only here, then in every submodule (on its branch)
 *
 * Flags:
 *   --only a,b    only these submodules (luna-pages,luna-forms; "luna-" may be left out)
 *   --skip a,b    all but these
 *   --no-root     commit / push / pull the submodules only, not this repository
 *   --root-only   this repository only
 *
 * The order matters for push: the submodules go first, so the commits this
 * repository points at are on GitHub before it is. `commit` here takes every
 * change of this repository (git add -A), the submodules' new commits included;
 * keep what is not ready out of it (git stash, or commit the submodules with
 * --no-root and this repository by hand).
 *
 * A submodule folder without .git (cloned without --recurse-submodules) is
 * reported and skipped: git submodule update --init <folder>.
 *
 * No dependencies, Node 18+. Works in Windows (cmd/PowerShell) and in bash.
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const cmd = args[0];
const flag = (name) => args.includes(`--${name}`);
const value = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const list = (name) =>
  (value(name) || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => (s.startsWith('luna-') ? s : `luna-${s}`));

const color = (c, s) => (process.stdout.isTTY ? `\x1b[${c}m${s}\x1b[0m` : s);
const ok = (s) => color('32', s);
const warn = (s) => color('33', s);
const bad = (s) => color('31', s);
const bold = (s) => color('1', s);

/** Runs a command; `capture` returns its stdout instead of printing it. */
function run(dir, line, { capture = false, allowFail = false } = {}) {
  const r = spawnSync(line, { cwd: dir, shell: true, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (r.status !== 0 && !allowFail) {
    if (capture && r.stderr) process.stderr.write(r.stderr);
    throw new Error(`${line}: exit ${r.status}`);
  }
  return capture ? (r.stdout || '').trim() : r.status === 0;
}

/** The submodules in .gitmodules order (`git: false`: not checked out). */
function submodules() {
  if (flag('root-only')) return [];
  const only = list('only');
  const skip = list('skip');
  const file = join(ROOT, '.gitmodules');
  if (!existsSync(file)) return [];
  return [...readFileSync(file, 'utf8').matchAll(/^\s*path\s*=\s*(.+?)\s*$/gm)]
    .map((m) => m[1])
    .filter((d) => (!only.length || only.includes(d)) && !skip.includes(d))
    .map((d) => {
      const dir = join(ROOT, d);
      return { dir, folder: d, git: existsSync(join(dir, '.git')) };
    });
}

const withRoot = () => !flag('no-root') && !value('only') && !value('skip') ? true : flag('root-only') || (!flag('no-root') && !value('only') && !value('skip'));
const root = { dir: ROOT, folder: '(luna)', git: true };

const NO_GIT = (folder) => warn(`not checked out: git submodule update --init ${folder}`);

const changes = (dir) => run(dir, 'git status --porcelain', { capture: true }).split('\n').filter(Boolean);
const branch = (dir) => run(dir, 'git rev-parse --abbrev-ref HEAD', { capture: true });

function aheadBehind(dir) {
  const r = run(dir, 'git rev-list --left-right --count HEAD...@{upstream}', { capture: true, allowFail: true });
  const m = typeof r === 'string' && r.match(/^(\d+)\s+(\d+)$/);
  return m ? { ahead: +m[1], behind: +m[2] } : null;
}

/** `git push`; a branch with no upstream gets one (`-u origin <branch>`). */
function gitPush(dir) {
  return aheadBehind(dir) ? run(dir, 'git push --follow-tags', { allowFail: true }) : run(dir, 'git push -u origin HEAD --follow-tags', { allowFail: true });
}

/** The version in gtr.json (`project.version`), if any. */
function version(dir) {
  try {
    const j = JSON.parse(readFileSync(join(dir, 'gtr.json'), 'utf8'));
    return (j.project && j.project.version) || j.version || '';
  } catch {
    return '';
  }
}

function describe(r) {
  const ch = changes(r.dir);
  const ab = aheadBehind(r.dir);
  const b = branch(r.dir);
  const git = [
    ch.length ? warn(`${ch.length} changed`) : ok('clean'),
    b === 'HEAD' ? warn('detached HEAD') : '',
    ab ? (ab.ahead ? warn(`↑${ab.ahead}`) : '') + (ab.behind ? warn(` ↓${ab.behind}`) : '') : warn('no upstream'),
  ]
    .filter(Boolean)
    .join(' ');
  const v = version(r.dir);
  return `${bold(r.folder.padEnd(16))} [${b}] ${git}${v ? `  ${v}` : ''}`;
}

// ------------------------------------------------------------------ commands

function status() {
  for (const r of submodules()) console.log(r.git ? describe(r) : `${bold(r.folder.padEnd(16))} ${NO_GIT(r.folder)}`);
  if (!withRoot()) return;
  console.log(describe(root));
  // Submodules whose checked-out commit is not the one recorded here.
  const moved = run(ROOT, 'git submodule status', { capture: true, allowFail: true });
  const lines = typeof moved === 'string' ? moved.split('\n').filter((l) => l.startsWith('+')) : [];
  if (lines.length) console.log(warn(`  new submodule commits to record here: ${lines.map((l) => l.trim().split(/\s+/)[1]).join(', ')}`));
}

function commit() {
  const message = args[1] && !args[1].startsWith('--') ? args[1] : null;
  if (!message) throw new Error('A message is needed: node repos.mjs commit "text" [--push]');
  const pushed = [];
  for (const r of submodules()) {
    if (!r.git) {
      console.log(`${r.folder}: ${NO_GIT(r.folder)}`);
      continue;
    }
    if (!changes(r.dir).length) {
      console.log(`${r.folder}: ${ok('nothing to commit')}`);
      continue;
    }
    if (branch(r.dir) === 'HEAD') {
      console.log(`${r.folder}: ${bad('detached HEAD: check out a branch first (git switch master)')}`);
      continue;
    }
    console.log(bold(`\n== ${r.folder}`));
    run(r.dir, 'git add -A');
    run(r.dir, `git commit -m ${JSON.stringify(message)}`);
    if (flag('push')) {
      if (gitPush(r.dir)) pushed.push(r.folder);
      else console.log(bad('push failed'));
    }
  }
  if (!withRoot()) return;
  if (!changes(ROOT).length) return console.log(`${root.folder}: ${ok('nothing to commit')}`);
  console.log(bold(`\n== ${root.folder}`));
  run(ROOT, 'git add -A');
  run(ROOT, `git commit -m ${JSON.stringify(message)}`);
  if (flag('push') && !gitPush(ROOT)) console.log(bad('push failed'));
}

function push() {
  for (const r of submodules()) {
    if (!r.git) {
      console.log(`${r.folder}: ${NO_GIT(r.folder)}`);
      continue;
    }
    const ab = aheadBehind(r.dir);
    if (ab && !ab.ahead) {
      console.log(`${r.folder}: ${ok('nothing to push')}`);
      continue;
    }
    console.log(bold(`\n== ${r.folder}`));
    if (!gitPush(r.dir)) console.log(bad('push failed'));
  }
  if (!withRoot()) return;
  console.log(bold(`\n== ${root.folder}`));
  if (!gitPush(ROOT)) console.log(bad('push failed'));
}

function pull() {
  if (withRoot()) {
    console.log(bold(`== ${root.folder}`));
    if (!run(ROOT, 'git pull --ff-only', { allowFail: true })) console.log(bad('pull failed (diverged or local changes in the way)'));
  }
  for (const r of submodules()) {
    if (!r.git) {
      console.log(`${r.folder}: ${NO_GIT(r.folder)}`);
      continue;
    }
    if (branch(r.dir) === 'HEAD') {
      console.log(`${r.folder}: ${warn('detached HEAD: skipped (git switch master, then pull)')}`);
      continue;
    }
    console.log(bold(`\n== ${r.folder}`));
    if (!run(r.dir, 'git pull --ff-only', { allowFail: true })) console.log(bad('pull failed (diverged or local changes in the way)'));
  }
}

const commands = { status, commit, push, pull };
if (!commands[cmd]) {
  console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('*/')[0].replace(/^#!.*\n\/\*\*?/, '').replace(/^ \* ?/gm, ''));
  process.exit(cmd ? 1 : 0);
}
try {
  commands[cmd]();
} catch (e) {
  console.error(bad(e.message));
  process.exit(1);
}
