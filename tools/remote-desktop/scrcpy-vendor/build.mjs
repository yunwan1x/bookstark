import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const esbuild = require("esbuild");

await esbuild.build({
  entryPoints: ["entry.js"],
  bundle: true,
  minify: true,
  format: "iife",
  target: "es2022",
  outfile: "../web/android-scrcpy.js",
});
console.log("Bundled classic IIFE web/android-scrcpy.js cleanly");
