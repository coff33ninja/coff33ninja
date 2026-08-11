import { mkdtemp, writeFile, mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { exec } from "node:child_process";
import { promisify } from "node:util";

const execAsync = promisify(exec);
const CORE_PACKAGE_NAME = "@stats-organization/github-readme-stats-core";

const owner = process.env.GITHUB_REPOSITORY_OWNER || "coff33ninja";
const token = process.env.GITHUB_TOKEN || "";
const count = 10;

const headers = {
  "User-Agent": "readme-bot",
  Accept: "application/vnd.github+json",
  "X-GitHub-Api-Version": "2022-11-28",
};
if (token) headers.Authorization = `Bearer ${token}`;

const repos = await fetch(
  `https://api.github.com/users/${owner}/repos?per_page=100&sort=pushed&direction=desc`,
  { headers },
).then((r) => r.json());

const excludeName = (process.env.GITHUB_REPOSITORY || "").split("/")[1];
const filtered = repos.filter(
  (r) => !r.fork && !r.archived && !r.disabled && r.name !== excludeName,
);
const top = filtered.slice(0, count);

const installDir = await mkdtemp(path.join(os.tmpdir(), "grs-core-"));
await writeFile(
  path.join(installDir, "package.json"),
  JSON.stringify({ private: true, type: "module" }),
  "utf8",
);
await execAsync(
  `${process.platform === "win32" ? "npm.cmd" : "npm"} install --no-save --ignore-scripts --no-package-lock ${CORE_PACKAGE_NAME}@v2`,
  { cwd: installDir, env: process.env },
);

const installRequire = createRequire(path.join(installDir, "package.json"));
const core = await import(
  pathToFileURL(installRequire.resolve(CORE_PACKAGE_NAME)).href
);

await mkdir("dist", { recursive: true });
for (const repo of top) {
  const result = await core.pin({
    username: owner,
    repo: repo.name,
    theme: "github_dark",
    hide_border: "true",
  });
  const svg = result?.content;
  if (!svg) {
    console.error(`empty pin card for ${repo.name}`);
    continue;
  }
  await writeFile(`dist/pin-${repo.name}.svg`, svg, "utf8");
  console.log(`wrote dist/pin-${repo.name}.svg`);
}
console.log(`wrote ${top.length} pin cards`);
