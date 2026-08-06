# Tether for cmux

## Purpose

Tether is a first-class SSH server dashboard and connection manager built into
our cmux fork. It makes finding and opening an SSH server as fast as opening a
local workspace while leaving terminal emulation and SSH protocol behavior to
the mature tools that already own them.

The product boundary is deliberate:

- cmux owns terminal rendering, PTYs, windows, panes, workspaces, restoration,
  reconnection, and its existing `cmux ssh` workflow.
- OpenSSH owns configuration evaluation, authentication, agents, private-key
  formats, certificates, jump hosts, forwarding, and known-host verification.
- Tether owns server discovery, search, organization, safe config editing, key
  inventory, connection entry points, and portable backup and restore.

The source of truth remains ordinary files. Tether must remain useful even if
the app disappears: `~/.ssh` still works with `/usr/bin/ssh`, and presentation
metadata remains readable JSON.

## Product principles

1. A visible server connects in one click. Reaching a server from the normal
   workspace view takes at most two clicks.
2. Keyboard use is faster: open Quick Connect, type, press Return.
3. Tether never implements SSH transport, decrypts private keys, or maintains a
   competing known-host trust store.
4. Tether never silently rewrites hand-maintained SSH configuration.
5. Every non-trivial write is previewable, validated, atomic, and recoverable.
6. Backup has no proprietary database dependency. A backup is a documented set
   of files plus a versioned manifest.
7. The downstream patch stays narrow. New behavior lives in isolated packages;
   existing cmux files receive small composition, registration, and dispatch
   hooks.
8. Defaults should fit ordinary OpenSSH users. Advanced configuration remains
   editable as OpenSSH text instead of becoming hundreds of form controls.

## Success criteria

The MVP is successful when a user with an existing `~/.ssh/config` can:

- open the Servers sidebar and see every literal host alias, including aliases
  discovered through `Include` files;
- find a server by alias, resolved hostname, user, tag, or note;
- connect through cmux's existing SSH path in no more than two clicks;
- use Quick Connect entirely from the keyboard;
- add a server to a Tether-managed config fragment without damaging existing
  configuration;
- inspect which identity OpenSSH resolves for a server and see its public
  fingerprint;
- create a configuration-only backup and restore it with a conflict preview;
- continue using all existing cmux workspace and terminal features unchanged.

The MVP does not require cloud sync, private-key parsing, password storage, a
new SSH implementation, background health polling, or a GUI for every
`ssh_config` directive.

## User experience

### Sidebar

The left sidebar gains two first-class modes:

- **Workspaces** keeps the existing cmux workspace sidebar.
- **Servers** shows the Tether server catalog.

The switch belongs at the top of the existing sidebar and remembers the last
selection. When Servers is already selected, clicking a server connects in one
click. From Workspaces, switching to Servers and clicking a server takes two.

The server sidebar contains:

1. a search field focused by the Servers shortcut;
2. favorites;
3. recent servers;
4. optional tag groups;
5. all matching servers;
6. a compact add button and an overflow menu for import, settings, and backup.

A server row prioritizes recognition:

```text
prod-web                              production
deploy@web-01.example.com
```

Port is shown only when it differs from 22. Proxy/jump-host and missing-key
states use restrained icons with useful tooltips. Rows must not become dense
configuration summaries.

Clicking a normal row connects immediately. Servers explicitly marked
`confirmBeforeConnect` show one confirmation sheet. Production tags alone do
not force confirmation.

### Quick Connect

Quick Connect is a native command-palette-style surface with a configurable
shortcut registered through cmux's existing shortcut system.

Flow:

1. invoke Quick Connect;
2. type any combination of alias, hostname, user, tag, or note;
3. press Return to connect in the foreground;
4. use a documented modifier with Return to open without changing focus.

Results update as the user types. Exact alias prefixes rank first, followed by
alias substrings, tags, hostname, user, and notes. Matching uses a small,
deterministic token scorer rather than a new fuzzy-search dependency.

### Server editor

The common form exposes:

- alias;
- hostname;
- user;
- port;
- identity file;
- tags;
- favorite and optional confirmation behavior.

An Advanced disclosure contains common OpenSSH options such as `ProxyJump`,
agent forwarding, keepalive values, and forwards. A text editor exposes the
managed host block for the long tail. Tether does not attempt to model every
OpenSSH directive.

Entries discovered outside the managed fragment are read-only by default.
Their inspector offers:

- open the source file at the relevant block;
- duplicate into the managed fragment under a new alias;
- move into the managed fragment with an explicit diff and confirmation.

Tether must never create a duplicate alias to override a hand-written block
silently because OpenSSH's first-value-wins behavior makes that unsafe.

### Key inventory

The key screen inventories identity files referenced by effective server
configurations. It shows:

- path and key type;
- public fingerprint obtained through `ssh-keygen`;
- existence and permission diagnostics;
- servers that reference the identity;
- whether the identity appears loaded in `ssh-agent` when that can be determined
  without prompting for secrets.

Initial actions are:

- generate a key through `/usr/bin/ssh-keygen`;
- attach an existing key to a managed server;
- load a key through `ssh-add`;
- copy the public key;
- reveal the key in Finder;
- inspect references before rename or deletion.

Tether does not parse, decrypt, reserialize, or store private-key contents in
application state.

## Data ownership

### SSH configuration

Tether reads the user's normal OpenSSH configuration starting at:

```text
~/.ssh/config
```

Alias discovery follows `Include` directives and collects literal names from
`Host` declarations. Wildcard and negated patterns affect OpenSSH resolution but
do not become server rows. Multiple literal names in one `Host` declaration
become separate selectable aliases.

Discovery is intentionally narrower than configuration evaluation. For every
displayed or selected alias, Tether asks the installed OpenSSH client for the
effective configuration:

```bash
/usr/bin/ssh -G <alias>
```

Tether uses resolved values for display and diagnostics. It passes the original
alias unchanged to cmux when connecting so OpenSSH evaluates the real config
again at connection time.

Tether-owned entries live in:

```text
~/.ssh/config.d/tether.conf
```

If necessary, onboarding offers to add one include directive to the main file:

```sshconfig
Include ~/.ssh/config.d/*
```

The placement is previewed because directive ordering matters. The app owns
only `tether.conf`; unrelated files remain untouched unless the user explicitly
chooses a source-aware move operation.

### Presentation metadata

SSH connection details are never duplicated into an application database.
Tether stores only presentation data keyed by alias:

```text
~/.config/cmux/tether.json
```

Version 1 contains:

```json
{
  "version": 1,
  "servers": {
    "prod-web": {
      "tags": ["production", "web"],
      "favorite": true,
      "note": "primary public web server",
      "color": "red",
      "confirmBeforeConnect": false
    }
  }
}
```

Last-used history may live in the same file, but it must be bounded and easy to
discard. Metadata for a temporarily missing alias remains dormant rather than
being deleted automatically.

### Known hosts

OpenSSH remains the only trust authority. Tether may provide a read-only viewer
and an explicit removal action later, but it does not create or synchronize a
second known-host database and never auto-resolves a changed fingerprint.

## Architecture

New code follows cmux's package architecture and strict dependency direction.
The initial package split should remain small and whole-domain:

```text
Packages/macOS/
├── CmuxSSHConfig/
│   ├── models and protocol seams
│   ├── alias discovery
│   ├── effective-config command runner
│   ├── managed config repository
│   ├── metadata repository
│   ├── file watching
│   └── identity inspection
├── CmuxSSHServers/
│   ├── @MainActor @Observable catalog model
│   ├── search and ranking
│   ├── selection and editor state
│   ├── connection coordinator
│   └── backup/restore coordination
└── CmuxSSHServersUI/
    ├── server sidebar
    ├── Quick Connect
    ├── server editor and inspector
    ├── key inventory
    └── backup and restore views
```

If backup encryption grows into an independently reusable capability, extract
it later as one cohesive service package. Do not pre-split every model into a
micro-package.

Layering rules:

- filesystem access and `Process` execution live in actors behind injected
  protocols;
- repositories accept root URLs, `FileManager`-like seams, command runners,
  and clocks through initializers;
- the domain model is `@MainActor @Observable` and consumes service streams;
- SwiftUI/AppKit views depend on the domain package and never execute processes
  or touch SSH files directly;
- the executable target is the composition root and contains only narrow cmux
  registration and forwarding hooks;
- no runtime singleton or global mutable test override is introduced;
- new public APIs carry DocC comments and explicit `Sendable` behavior.

### Connection integration

All connection entry points share one action:

```text
Servers row ───────┐
Quick Connect ─────┼── SSHServerConnectionCoordinator.connect(alias:)
context menu ──────┤
CLI/socket later ──┘
```

The coordinator invokes cmux's existing SSH launch path with the original alias
and optional focus behavior. It does not reconstruct `user@hostname`, append an
identity argument inferred from display data, or bypass the effective OpenSSH
configuration.

The same action records recency only after cmux accepts the launch request. A
failed launch presents the existing cmux SSH error surface and does not count as
a successful recent connection.

### Upstream patch discipline

Most code lives in the new packages. Existing cmux files receive the smallest
possible hooks for:

- package composition;
- sidebar-mode registration and persistence;
- command-palette and shortcut registration;
- shared SSH action dispatch;
- settings and localization;
- test-target wiring.

Where cmux lacks a clean seam, prefer adding a generic registration or action
API that could be contributed upstream. Keep generic cmux enhancements in
separate commits from Tether-specific product behavior.

Maintain remotes as:

```text
origin    git@github.com:lolwierd/cmux.git
upstream  git@github.com:manaflow-ai/cmux.git
```

Pull upstream frequently in small increments. Do not rewrite upstream code for
style or move unrelated files. Our commits should remain focused enough to
rebase, inspect, or temporarily drop independently.

## Safe write behavior

Managed configuration and metadata writes follow this sequence:

1. load the current file and retain its bytes and permissions;
2. construct the proposed contents in memory;
3. show a semantic preview for user-initiated connection changes;
4. write a sibling temporary file;
5. apply safe permissions;
6. validate affected aliases through the installed OpenSSH client;
7. atomically replace the managed file;
8. retain one recoverable previous version;
9. publish a repository change event to refresh the catalog.

Validation failures leave the original file intact and surface OpenSSH's actual
diagnostic output with secrets redacted where necessary.

File watching follows the complete include graph. Rebuilds are debounced with a
cancellable injected clock and coalesced by the repository actor. The UI never
polls the filesystem once per render.

## Backup and restore

### Configuration-only backup

The first backup milestone exports a normal directory or archive containing:

- SSH config and followed include files;
- Tether metadata;
- public keys referenced by discovered identities when available;
- optionally `known_hosts`, clearly identified as security-sensitive host
  metadata;
- a versioned manifest with original paths, modes, hashes, aliases, and omitted
  private identities.

It never contains private keys and can be inspected without cmux.

### Full encrypted backup

A later MVP-hardening milestone adds a full backup containing referenced private
identities. Full backup is always encrypted with authenticated encryption and a
user-supplied recovery password. Tether never emits a plaintext archive of
private keys, even temporarily in a user-visible location.

The exact container implementation requires a focused security design before
coding. Prefer a well-established platform facility or maintained library over
inventing a cryptographic file format. The manifest is inside the encrypted
container; a minimal non-secret envelope may expose only format version and KDF
parameters when required.

### Restore

Restore always presents a plan before writing. Conflict behavior is explicit:

- identical config or identity: keep existing;
- new alias or identity: import;
- same alias with different configuration: show a diff and ask;
- same identity path with a different public fingerprint: never overwrite
  silently;
- known-host fingerprint conflict: never merge automatically;
- metadata conflict: preview alias-level merge choices.

Restore uses staging, validates the resulting SSH configuration, preserves file
modes, and can roll back the complete operation if any required write fails.

## Security requirements

- Never log private-key bytes, passphrases, passwords, agent responses, or full
  command environments.
- Use argument arrays rather than shell command strings.
- Treat aliases beginning with `-`, embedded control characters, unexpected
  paths, and symlink traversal as untrusted input.
- Resolve and validate managed paths before writing. Never recursively delete a
  broad or unresolved path.
- Preserve restrictive key permissions and diagnose overly permissive files.
- Never upload private material, config, or hostnames for analytics.
- Never auto-accept changed host keys.
- Never infer successful authentication from TCP reachability.
- Keep all private-key passphrase interaction inside OpenSSH, `ssh-keygen`, or
  `ssh-add`.

## Delivery plan

### Milestone 0: fork baseline and architecture spike

- Keep `origin` on `lolwierd/cmux` and `upstream` on `manaflow-ai/cmux`.
- Run repository setup and establish a tagged development build.
- Record the clean upstream build and focused test baseline.
- Confirm the smallest existing sidebar registration and SSH-launch seams.
- Finalize package dependency edges and add package test targets.
- Add an architecture note for any necessary change to existing cmux APIs.

Exit gate: the fork builds unchanged, the new empty packages compile in the app
and unit-test schemes, and no existing behavior changes.

### Milestone 1: read-only server catalog

- Discover literal aliases from `~/.ssh/config` and recursive includes.
- Detect include cycles and inaccessible files without hanging or discarding
  already valid entries.
- Resolve selected aliases using `/usr/bin/ssh -G`.
- Watch the include graph and publish catalog updates.
- Load and save versioned presentation metadata.
- Implement deterministic search and ranking.
- Add the native Servers sidebar with favorites, recents, tags, empty states,
  and diagnostics.

Exit gate: the user's existing SSH configuration appears correctly and updates
after an external edit without restarting cmux. No SSH file is modified.

### Milestone 2: shared connect action and Quick Connect

- Connect a server row through cmux's existing SSH workflow.
- Add Quick Connect with full keyboard navigation.
- Register configurable shortcuts through cmux's shortcut system.
- Add foreground/background focus behavior.
- Record bounded recency after accepted launches.
- Add context-menu and command-palette entry points through the same action.

Exit gate: a visible server connects in one click, any server is reachable from
the normal workspace sidebar in two clicks, and keyboard connect is shortcut,
query, Return. The original alias reaches the existing cmux SSH launcher
unchanged.

### Milestone 3: managed configuration

- Onboard `~/.ssh/config.d/tether.conf` and preview include placement.
- Add common server creation and editing forms.
- Add raw managed-block editing for advanced directives.
- Validate with OpenSSH and replace files atomically.
- Surface source locations for externally managed aliases.
- Implement duplicate, source-aware move, and safe delete flows.

Exit gate: create, edit, and delete round-trip through `ssh -G`; a failed edit
leaves the previous config byte-for-byte intact; hand-maintained blocks are not
rewritten implicitly.

### Milestone 4: identity inventory

- Resolve all effective `IdentityFile` values per alias.
- Read public fingerprints through `ssh-keygen`.
- Diagnose missing files and unsafe permissions.
- Show reverse references from an identity to servers.
- Generate, attach, load, copy-public-key, and reveal identities through system
  tools and shared actions.
- Block rename/delete operations that would leave unresolved references unless
  the user explicitly updates those references in the same transaction.

Exit gate: common key operations work without Tether reading private-key
contents or storing passphrases.

### Milestone 5: backup and restore

- Define and document manifest version 1.
- Implement configuration-only export and restore preview.
- Add hash, mode, path, alias, and identity completeness checks.
- Add transactional restore with conflict handling and rollback.
- Complete a security design review for the encrypted container.
- Implement full encrypted backup and restore after the design is approved.

Exit gate: a clean macOS account can restore the backup, validate every imported
alias with `ssh -G`, and connect. Conflicting identities and known hosts are
never overwritten silently. No plaintext full-key backup is produced.

### Milestone 6: hardening and release readiness

- Accessibility labels, keyboard traversal, VoiceOver, reduced motion, and
  high-contrast verification.
- Large-catalog performance tests with at least 5,000 aliases.
- Localization audit for every user-facing string.
- Migration and downgrade behavior for metadata and backup manifests.
- Upstream rebase drill and documentation of recurring conflict points.
- Crash recovery during config write and restore.
- Privacy review proving that analytics contain no hostnames, usernames, paths,
  commands, aliases, fingerprints, or key information.

Exit gate: the focused unit, integration, CLI, and UI suites pass; a tagged
dogfood build is verified against real SSH config; backup recovery is tested on
a clean account; the downstream patch remains reviewable against upstream.

## Testing strategy

### Package unit tests with Swift Testing

Alias discovery fixtures cover:

- comments, blank lines, whitespace, and `key=value` syntax;
- multiple aliases in one `Host` line;
- wildcard and negated patterns;
- quoted and relative `Include` paths;
- globbed includes;
- nested includes and include cycles;
- unreadable and missing include files;
- duplicate aliases and source locations;
- configuration changes while watching.

Search tests cover normalization, token ordering, deterministic ties, alias
prefix priority, tags, hostname, user, notes, and catalogs large enough to catch
accidental quadratic behavior.

Repository tests use temporary directories, injected command runners, fixed
clocks, and fake event streams. They verify atomic replacement, permissions,
rollback, stale-write detection, and recovery without reading the user's home
directory.

Metadata tests cover versioned decoding, unknown fields, dormant aliases,
bounded recency, and forward-compatible migrations.

Backup tests cover manifest hashes, permissions, path traversal rejection,
missing referenced identities, conflict planning, transaction rollback, wrong
password behavior, tampering, and interrupted restore.

### OpenSSH integration tests

Tests create temporary config trees and compare displayed effective values with
the installed `/usr/bin/ssh -G`. These are behavioral integration tests, not a
second expected implementation of OpenSSH semantics.

Connection-launch tests use an injected launcher to assert that the original
alias and focus option reach cmux's shared SSH action. They explicitly reject
reconstruction as `user@resolved-host`.

Key tests generate disposable keys in a temporary directory through the system
`ssh-keygen`, assert fingerprints against `ssh-keygen` output, and never commit
generated key material.

### UI tests

XCUITest covers:

- Workspaces to Servers to connection in two clicks;
- one-click connection when Servers is already active;
- Quick Connect search, arrow navigation, Return, Escape, and focus restoration;
- no-result, malformed-config, missing-key, and inaccessible-file states;
- add/edit validation and diff preview;
- backup export, restore preview, conflict refusal, and cancellation;
- accessibility identifiers and keyboard-only navigation.

UI tests use a temporary SSH root and injected launcher. They never connect to
the user's real servers or modify the user's real `~/.ssh`.

### Build and CI gates

- Use a tagged cmux debug build; never run an untagged development app.
- Build the app and the `cmux-unit` scheme because a successful reload does not
  prove test targets compile.
- Run package tests directly for fast feedback.
- Wire any app-target tests into the Xcode project and run the repository's test
  wiring lint.
- Use two commits for regression fixes: failing behavioral test, then fix.
- Run localization, package grouping, lockfile policy, and relevant workflow
  guards before pushing.

## Post-MVP improvements

Prioritized candidates after the core workflow is proven:

1. tag editing and bulk organization directly from the sidebar;
2. connection presets that run a safe initial remote command;
3. server-specific workspace layouts and saved pane arrangements;
4. optional `mosh` launch using cmux's existing transport support;
5. clearer agent and certificate inventory;
6. `known_hosts` read-only inspection and explicit removal;
7. public-key installation helper using the normal SSH connection;
8. import/export of metadata separately from SSH material;
9. opt-in filesystem sync guidance or adapters without making cloud state the
   source of truth;
10. CLI and socket commands for listing, searching, and connecting to catalog
    servers;
11. Spotlight/App Intent integration for opening a server;
12. per-server environment-independent notes and runbooks;
13. duplicate-host and stale-alias diagnostics;
14. optional connection history with local-only retention controls;
15. configurable production confirmation policies by explicit alias or tag.

## Explicit non-goals

- Implementing SSH transport in Swift.
- Embedding or vendoring a competing SSH client library.
- Parsing or decrypting private keys.
- Storing SSH passwords or private keys in Tether metadata.
- Replacing `ssh-agent` or Keychain integration.
- Maintaining an independent known-host trust database.
- Auto-accepting host-key changes.
- Automatically syncing private keys through CloudKit or ordinary cloud files.
- Treating TCP reachability as server health or authentication readiness.
- Implementing SFTP, port-forwarding dashboards, team sharing, or mobile support
  in the MVP.
- Rebuilding cmux terminal, pane, workspace, or restoration behavior.

## Open decisions before implementation

These require short design spikes rather than assumptions:

1. whether Servers is implemented through a generalized sidebar-provider action
   model or as a dedicated native sidebar mode;
2. the final conflict-minimizing hook into cmux's existing SSH launcher;
3. the default configurable shortcut after auditing current cmux bindings;
4. safe `Include` placement when an existing config starts with specific rules
   or already uses a config directory;
5. whether metadata recency belongs in `tether.json` or a separate disposable
   state file so backup remains clean;
6. the established encrypted-container implementation for full backup;
7. whether `known_hosts` is included by default in configuration-only backup;
8. the exact behavior for aliases repeated across multiple source files.

Each decision must be recorded with its constraint, chosen option, rejected
alternatives, and consequences before the corresponding milestone is merged.
