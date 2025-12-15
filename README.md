# flowdocs

Semantic documentation search engine for software projects. Index your markdown documentation and search with keyword and semantic search.

A native Swift rewrite of the original TypeScript implementation.

## Features

- **Fast Full-Text Search** - SQLite FTS5-powered keyword search with BM25 ranking
- **Hybrid Search** - Combines keyword and vector search using Reciprocal Rank Fusion (RRF)
- **MCP Integration** - Model Context Protocol server for Claude and other AI assistants
- **Project-Based Indexing** - Indexes stored per-project in `.flowdocs/` directory
- **Secure by Design** - Path traversal protection, input sanitization, symlink validation
- **Single Binary** - No runtime dependencies, just one 1.8MB executable

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/afterxleep/flowdocs-swift.git
cd flowdocs-swift

# Build release binary
swift build -c release

# Copy to PATH (optional)
cp .build/release/flowdocs /usr/local/bin/
```

### Requirements

- macOS 13.0 or later
- Swift 6.0 or later (for building)

## Quick Start

```bash
# Initialize flowdocs in your project
flowdocs init

# Index your documentation
flowdocs add ./docs
flowdocs add README.md

# Search your documentation
flowdocs search "authentication"

# Get a specific document
flowdocs get docs/auth.md
```

## CLI Commands

| Command | Description |
|---------|-------------|
| `flowdocs init` | Initialize flowdocs in current directory |
| `flowdocs add <path>` | Add file or directory to index |
| `flowdocs search <query>` | Search documents |
| `flowdocs get <path>` | Retrieve document content |
| `flowdocs status` | Show index status |
| `flowdocs remove <path>` | Remove document from index |
| `flowdocs serve` | Start MCP server for Claude integration |

### Options

- `--limit <n>` - Limit search results (default: 10)
- `--help, -h` - Show help
- `--version` - Show version

## MCP Server Integration

flowdocs provides an MCP (Model Context Protocol) server for integration with Claude and other AI assistants.

### Available Tools

| Tool | Description |
|------|-------------|
| `init` | Initialize flowdocs in project directory |
| `add` | Index files or directories |
| `create` | Create and index a new document |
| `search` | Search documentation |
| `get` | Retrieve document content |
| `status` | Get index status |
| `remove` | Remove document from index |

### Claude Desktop Configuration

Add to your Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "flowdocs": {
      "command": "/path/to/flowdocs",
      "args": ["serve"],
      "cwd": "/your/project/directory"
    }
  }
}
```

## Development

```bash
# Run tests
swift test

# Build debug
swift build

# Build release
swift build -c release
```

## Architecture

```
Sources/flowdocs/
├── main.swift          # Entry point
├── CLI/
│   └── CLI.swift       # Argument Parser commands
├── Core/
│   ├── Models.swift    # Data types
│   ├── Store.swift     # SQLite + FTS5
│   ├── Search.swift    # Hybrid search + RRF
│   └── Project.swift   # Mode detection
└── MCP/
    └── MCPServer.swift # stdio JSON-RPC server
```

## Security

flowdocs includes several security measures:

- **Path Traversal Protection** - All file paths are validated to stay within the project directory
- **Symlink Validation** - Prevents TOCTOU attacks by verifying files are not symlinks
- **FTS5 Query Sanitization** - Removes special operators to prevent injection
- **Input Length Limits** - Query length capped at 10,000 characters
- **Type Validation** - All MCP tool arguments are validated before use

## Test Coverage

191 tests covering:
- Models (20 tests)
- Store/SQLite (27 tests)
- Search/FTS5 (33 tests)
- Project detection (52 tests)
- CLI commands (32 tests)
- MCP server (58 tests)

## License

MIT
