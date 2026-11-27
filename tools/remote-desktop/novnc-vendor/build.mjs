import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const esbuild = require("esbuild");

const patchTopLevelAwaitPlugin = {
  name: "patch-novnc-tla",
  setup(build) {
    build.onLoad({ filter: /core[\\/]util[\\/]browser\.js$/ }, async (args) => {
      let src = await fs.promises.readFile(args.path, "utf8");
      src = src.replace(
        "supportsWebCodecsH264Decode = await _checkWebCodecsH264DecodeSupport();",
        "supportsWebCodecsH264Decode = false; _checkWebCodecsH264DecodeSupport().then((v) => { supportsWebCodecsH264Decode = !!v; }).catch(() => {});"
      );
      return { contents: src, loader: "js" };
    });
  },
};

await esbuild.build({
  entryPoints: ["entry.js"],
  bundle: true,
  minify: true,
  format: "iife",
  target: "es2020",
  outfile: "../web/novnc-rfb.js",
  plugins: [patchTopLevelAwaitPlugin],
});

fs.copyFileSync(
  path.resolve("node_modules/@novnc/novnc/LICENSE.txt"),
  path.resolve("../web/LICENSE-noVNC.txt")
);
console.log("Bundled classic IIFE web/novnc-rfb.js cleanly");
