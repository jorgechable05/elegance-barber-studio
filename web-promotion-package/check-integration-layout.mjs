import { access, readFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pages = [
  {
    file: "web-recovery/admin.html",
    imports: ["./web-promotion-package/admin-promotions.js"],
    requiredFiles: ["web-recovery/web-promotion-package/admin-promotions.js"],
  },
  {
    file: "web-recovery/cliente.html",
    imports: ["./web-promotion-package/customer-promotion-utils.js"],
    requiredFiles: ["web-recovery/web-promotion-package/customer-promotion-utils.js"],
  },
];
const errors = [];

for (const page of pages) {
  const html = await readFile(resolve(repoRoot, page.file), "utf8");
  for (let i = 0; i < page.imports.length; i++) {
    const importPath = page.imports[i];
    if (!html.includes(importPath)) {
      errors.push(page.file + " no contiene el import esperado " + importPath);
      continue;
    }
    const target = resolve(repoRoot, page.requiredFiles[i]);
    try {
      await access(target, constants.R_OK);
      console.log("PASS: " + page.file + " -> " + importPath + " resuelve en la raíz de staging");
    } catch {
      errors.push(page.file + " importa " + importPath + ", pero falta " + page.requiredFiles[i]);
    }
  }
}

for (const sourceFile of [
  "web-promotion-package/admin-promotions.js",
  "web-promotion-package/customer-promotion-utils.js",
]) {
  try {
    await access(resolve(repoRoot, sourceFile), constants.R_OK);
  } catch {
    errors.push("Falta fuente del paquete: " + sourceFile);
  }
}

if (errors.length) {
  console.error("FAIL: dependencias no empaquetadas para las vistas recuperadas:");
  for (const error of errors) console.error("- " + error);
  process.exitCode = 1;
} else {
  console.log("PASS: las dependencias de las vistas están incluidas en el staging");
}
