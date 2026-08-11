import { GithubApiService } from "../trophy/src/Services/GithubApiService.ts";
import { Card } from "../trophy/src/card.ts";
import { COLORS } from "../trophy/src/theme.ts";

const username = Deno.args[0];
const outputPath = Deno.args[1] ?? "./dist/trophy.svg";
const themeName = Deno.args[2] ?? "onedark";

if (!username) {
  console.error(
    "Usage: deno run --allow-net --allow-env --allow-read --allow-write ./scripts/render_trophy.ts USERNAME [OUTPUT_PATH] [THEME]",
  );
  Deno.exit(1);
}

const svc = new GithubApiService();
const userInfoOrError = await svc.requestUserInfo(username);

if (
  !(userInfoOrError && (userInfoOrError as any).totalCommits !== undefined)
) {
  console.error(
    "Failed to fetch user info. Check GITHUB_TOKEN1/GITHUB_TOKEN2, username and rate limits.",
  );
  Deno.exit(2);
}

const userInfo = userInfoOrError as any;

const panelSize = 110;
const maxRow = 2;
const maxColumn = 4;
const marginWidth = 0;
const marginHeight = 0;
const noBackground = false;
const noFrame = true;

const card = new Card(
  [],
  [],
  maxColumn,
  maxRow,
  panelSize,
  marginWidth,
  marginHeight,
  noBackground,
  noFrame,
);
const theme = (COLORS as any)[themeName] ?? (COLORS as any).default;
const svg = card.render(userInfo, theme);

await Deno.writeTextFile(outputPath, svg);
console.log(`Wrote ${outputPath}`);
