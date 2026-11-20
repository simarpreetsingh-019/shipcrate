# Use shipcrate with AI agents

shipcrate works with any coding agent in three ways. Pick one, or use all three.

| | What it gives the agent | Works with |
|---|---|---|
| **MCP server** | Tools: set up, run the gate, preview a release, check status, verify downloads, read docs | Claude Code, Codex, Cursor, VS Code, Windsurf, Zed, any MCP client |
| **Skill** | Step-by-step instructions and rules, loaded when you ask about releases | Claude Code, Codex |
| **llms.txt / AGENTS.md** | One file any agent can read to learn shipcrate | Everything else |

Every option follows the same rules. The agent previews first, asks you before it pushes, publishes, yanks, changes
a rollout or sends an announcement, and never writes tokens into files.

## 1. Get shipcrate (once)

```sh
git clone https://github.com/simarpreetsingh-019/shipcrate ~/.shipcrate
```

The commands below assume this location. The MCP server needs Node 18 or newer.

## 2. Connect your agent

### Claude Code

```sh
claude mcp add shipcrate -- node ~/.shipcrate/mcp/server.js
```

### Codex

```sh
codex mcp add shipcrate -- node ~/.shipcrate/mcp/server.js
```

### Cursor

<a class="btn-install" href="cursor://anysphere.cursor-deeplink/mcp/install?name=shipcrate&config=eyJjb21tYW5kIjoic2giLCJhcmdzIjpbIi1jIiwibm9kZSBcIiRIT01FLy5zaGlwY3JhdGUvbWNwL3NlcnZlci5qc1wiIl19">Add to Cursor</a>

Or add this to `~/.cursor/mcp.json`:

```json
{ "mcpServers": { "shipcrate": { "command": "sh", "args": ["-c", "node \"$HOME/.shipcrate/mcp/server.js\""] } } }
```

### VS Code (Copilot agent mode)

<a class="btn-install" href="vscode:mcp/install?%7B%22name%22%3A%22shipcrate%22%2C%22command%22%3A%22sh%22%2C%22args%22%3A%5B%22-c%22%2C%22node%20%5C%22%24HOME/.shipcrate/mcp/server.js%5C%22%22%5D%7D">Add to VS Code</a>

```sh
code --add-mcp '{"name":"shipcrate","command":"sh","args":["-c","node \"$HOME/.shipcrate/mcp/server.js\""]}'
```

### Windsurf, Zed and other MCP clients

Use the same server entry: command `node`, argument `~/.shipcrate/mcp/server.js` written out as a full path,
with stdio transport.

## 3. Add the skill (Claude Code and Codex)

```sh
sh ~/.shipcrate/skills/install.sh
```

This copies the skill to `~/.claude/skills/shipcrate` and `~/.codex/skills/shipcrate`, asking before each copy.

## 4. Any other agent

Point it at [llms.txt](https://simarpreetsingh-019.github.io/shipcrate/llms.txt), or paste this:

```text
Read https://simarpreetsingh-019.github.io/shipcrate/llms.txt and set up releases for this project with shipcrate.
```

For Cursor rules, copy [.cursor/rules/shipcrate.mdc](https://github.com/simarpreetsingh-019/shipcrate/blob/main/.cursor/rules/shipcrate.mdc) into your project.

## Things to ask

- "Set up releases for this repo with shipcrate: Rust CLI for macOS, Linux and Windows, with a Homebrew tap."
- "Run the shipcrate gate and fix what fails."
- "Preview the 1.4.0 release notes."
- "Release 1.4.0 to 10% of users first."
- "1.4.0 is broken: yank it and send everyone back to 1.3.2."
- "Tell all users about Sunday's maintenance."

## MCP tools

| Tool | Does | Changes anything? |
|---|---|---|
| `shipcrate_docs` | Reads the docs (`llms`, `quickstart`, `integrating`, `platforms`, `security`, `agents`) | No |
| `shipcrate_init` | Adds the release tooling. A dry run by default | Only with `dry_run=false`; never overwrites |
| `shipcrate_check` | Runs the quality gate (`quick`, `push`, `release`) | No |
| `shipcrate_release_preview` | Guardrails, gate, build and notes, as a dry run | No |
| `shipcrate_status` | Settings plus the live manifest: version, rollout, yanked, announcement | No |
| `shipcrate_verify` | SHA-256 and GitHub attestation of a downloaded file | No |

Publishing isn't a tool on purpose. The agent runs `scripts/release.sh`, `yank.sh`, `rollout.sh` or
`announce.sh` in your terminal, where you see the command and approve it.
