import { readFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";

const pages = ["cliente.html", "admin.html", "pos.html"];
for (const page of pages) {
  const url = new URL("../web-recovery/" + page, import.meta.url);
  const html = await readFile(url, "utf8");
  const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
  let match;
  let count = 0;
  while ((match = scriptPattern.exec(html))) {
    const attrs = match[1] || "";
    if (/\bsrc\s*=/.test(attrs) || !match[2].trim()) continue;
    count++;
    try {
      execFileSync(process.execPath, ["--check", "--input-type=module"], {
        input: match[2],
        encoding: "utf8",
        stdio: ["pipe", "pipe", "pipe"]
      });
    } catch (error) {
      const stderr = error.stderr || error.message || String(error);
      throw new Error("JavaScript syntax error in " + page + " inline script #" + count + ":\n" + stderr);
    }
  }
  if (count === 0) throw new Error("No inline scripts found in " + page);
  console.log("PASS: " + page + " (" + count + " inline scripts parsed)");
}
