# hackmode documentation

`hackmode` installs a **mode** into one repository: a reversible bundle of Claude Code configuration that changes how Claude thinks, what it knows about the project's current situation, what it delegates, and what it is allowed to do. Today there is one mode, a 48-hour NASA Space Apps hackathon co-pilot. These docs explain how it works, why it's built this way, and how to build more modes.

| Doc | Read it to… |
|---|---|
| [architecture.md](architecture.md) | understand what a mode is, its six layers, and what happens at runtime (session start → prompt → tool call) |
| [code-structure.md](code-structure.md) | find your way around files, functions, data formats and tests |
| [design-decisions.md](design-decisions.md) | see how it was built: what was verified about Claude Code, the trade-offs, and the bugs testing caught |
| [creating-a-mode.md](creating-a-mode.md) | build another mode (client work, learning, incident response, …) |
| [roadmap.md](roadmap.md) | see known limitations, multi-mode support, and whether to port to Python |

Documented version: hackmode 1.0.0 (commit `0b7b0e6`), tested with Claude Code 2.1.322 on Linux.
