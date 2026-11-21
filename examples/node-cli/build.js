// Bundles bin/hello-node.js + updater/update-check.js into one file, dist/hello-node, for release archives.
// (npm users don't need this: npm installs the package as is.)
"use strict";
const fs = require("node:fs");
const { version } = require("./package.json");
const updater = fs.readFileSync("updater/update-check.js", "utf8").replace(/^"use strict";\n/m, "");
const bin = fs.readFileSync("bin/hello-node.js", "utf8")
  .replace(/^#!.*\n/, "")
  .replace(/const update = require\("\.\.\/updater\/update-check\.js"\);[^\n]*/, `const update = (() => { const module = { exports: {} }; ${updater}\nreturn module.exports; })();`)
  .replace(/const \{ version \} = require\("\.\.\/package\.json"\);/, `const version = ${JSON.stringify(version)};`);
fs.mkdirSync("dist", { recursive: true });
fs.writeFileSync("dist/hello-node", "#!/usr/bin/env node\n" + bin, { mode: 0o755 });
console.log("✓ dist/hello-node");
