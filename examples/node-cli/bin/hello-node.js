#!/usr/bin/env node
// hello-node: a tiny CLI that shows how shipcrate fits into a real Node program.
// The only shipcrate-specific lines are marked "shipcrate".
"use strict";
const update = require("../updater/update-check.js"); // shipcrate: the file `shipcrate init` put in updater/
const { version } = require("../package.json");

async function main(args) {
  const cmd = args[0];
  if (cmd === "--version" || cmd === "-V") return console.log(`hello-node ${version}`);
  if (cmd === "upgrade") return console.log(await update.upgrade(version, args.includes("--rollback"))); // shipcrate
  console.log(`👋 Hello, ${cmd || "world"}! (hello-node ${version})`);
  await update.notify(version); // shipcrate: daily notice / announcement, interactive use only
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { main };
