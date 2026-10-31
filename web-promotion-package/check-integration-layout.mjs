import { access, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pages = [
  { file: "web-recovery/admin.html", requiredImports: ["./web-promotion-package/admin-promotions.js"] },
  { file: "web-recovery/cliente.html", requiredImports: ["./web-promotion-package/customer-promotion-utils.js"] },
];
const dependencyFiles = [
  "web-promotion-package/admin-promotions.js",
  "web-promotion-package/customer-promotion-utils.js",
];
let errors = [];

for (const page of pages) {
  const html = await readFile(resolve(repoRoot, page.file), "utf8");
  for (const dependency of page.requiredImports) {
    if (!html.includes(dependency)) continue;
    const target = resolve(repoRoot, "web-recovery", dependency.replace(/^\.\//, ""));
    try {
      await access(target, constants.R_OK);
      console.log("PASS: " + page.file + " -> " + dependency + " resolves in the staged web root");
    } catch {
      errors.push(page.file + " imports " + dependency + " but the staged path is missing: " + target);
    }
  }
}

for (const dependency of dependencyFiles) {
  try {
    await access(resolve(repoRoot, dependency), constants.R_OK);
  } catch {
    errors.push("Expected source dependency missing from repository: " + dependency);
  }
}

if (errors.length) {
  console.error("FAIL: packaging/layout gate found unresolved view dependencies:");
  for (const error of errors) console.error("- " + error);
  process.exitCode = 1;
} else {
  console.log("PASS: integration dependency layout is complete");
}
