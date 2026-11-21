# hello-node: a Node CLI with shipcrate

```sh
node bin/hello-node.js Ada      # 👋 Hello, Ada!  (+ the update notice)
npm test                        # its tests
npm run build                   # dist/hello-node: one file, for the release archive
```

shipcrate-specific code: [`bin/hello-node.js`](bin/hello-node.js) (lines marked `shipcrate`). [`build.js`](build.js)
bundles it with `updater/update-check.js` into one file, so the release archive and `upgrade` work without npm.
People who installed with npm are told to run `npm install -g hello-node@latest` instead.
