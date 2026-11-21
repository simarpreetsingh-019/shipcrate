"use strict";
const test = require("node:test");
const assert = require("node:assert");
const { main } = require("../bin/hello-node.js");

test("greets", async () => {
  const lines = []; const log = console.log; console.log = (s) => lines.push(s);
  try { await main(["Ada"]); } finally { console.log = log; }
  assert.match(lines[0], /Hello, Ada!/);
});
