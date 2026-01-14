# OpenWork

An open-source macOS application for agentic AI task automation. OpenWork enables Large Language Models to autonomously execute multi-step tasks with full file system access and code execution in an isolated Linux virtual machine.

## Overview

OpenWork bridges the gap between conversational AI and practical task automation. It allows LLMs to autonomously plan and execute complex workflows - reading files, writing code, running commands, and iterating on results - all within a secure, sandboxed environment.

The application provides a native macOS interface for agentic AI, making autonomous task execution accessible to users who prefer graphical interfaces while maintaining the power and flexibility of command-line tools.

## Features

**Autonomous Agent Loop**
- Multi-turn task execution with configurable limits
- Intelligent doom loop detection to prevent infinite cycles
- Real-time logging of agent actions and tool results

**Isolated Code Execution**
- Linux VM powered by Apple's Virtualization.framework
- Alpine Linux guest with minimal attack surface
- VirtioFS for secure, high-performance file sharing
- NAT networking for controlled internet access

**Multi-Provider Support**
- Works with Ollama, LM Studio, OpenAI, Anthropic, and any OpenAI-compatible API
- Easy provider switching without code changes
- Connection testing and validation

**Comprehensive Tool System**
- File operations: read, write, edit
- Search: glob patterns, grep with regex
- Code execution: bash commands in isolated VM
- Directory listing with hidden file support

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon or Intel Mac with virtualization support
- Xcode 16+
- Docker (for building the VM root filesystem)
- qemu-img (`brew install qemu`)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/openwork.git
cd openwork
```

### 2. Build the Linux VM Image

The agent executes code inside an isolated Linux VM. Build the root filesystem:

```bash
cd OpenWork/Scripts
chmod +x build-rootfs.sh
./build-rootfs.sh
```

This creates `rootfs.img` and `initrd.img` in `OpenWork/Resources/linux/`.

### 3. Open in Xcode

```bash
open OpenWork/OpenWork.xcodeproj
```

### 4. Build and Run

Select the OpenWork scheme and press Cmd+R to build and run.

## Configuration

### LLM Providers

Configure your preferred LLM provider in Settings > Providers:

| Provider | Base URL | Notes |
|----------|----------|-------|
| Ollama | `http://localhost:11434` | Local, no API key needed |
| LM Studio | `http://localhost:1234/v1` | Local, OpenAI-compatible |
| OpenAI | `https://api.openai.com/v1` | Requires API key |
| Anthropic | `https://api.anthropic.com/v1` | Requires API key |

For local providers (Ollama, LM Studio), ensure the service is running before starting a task.

### Folder Access

OpenWork uses macOS security-scoped bookmarks to access folders. When you select a working directory:

1. A system permission dialog appears
2. Grant access to the folder
3. The folder is mounted into the VM at `/workspace`
4. Access persists across app restarts

## Architecture

```
OpenWork/
├── Agent/          # Autonomous execution loop
│   └── AgentLoop   # Turn-based LLM interaction with tool calls
├── Provider/       # LLM API integration
│   ├── ProviderManager     # Provider lifecycle
│   └── OpenAIStreamingClient  # API communication
├── Tools/          # Agent capabilities
│   ├── Tool        # Protocol and result types
│   └── ToolRegistry        # Built-in tool implementations
├── VM/             # Virtualization
│   └── VMManager   # VZVirtualMachine lifecycle
└── Views/          # SwiftUI interface
    ├── ChatView    # Conversational interface
    ├── TasksView   # Autonomous task execution
    └── SettingsView    # Configuration
```

## Security Model

OpenWork implements defense in depth:

1. **macOS App Sandbox**: The app runs in a restricted sandbox with explicit entitlements
2. **User-Granted Access**: File access requires explicit user permission via system dialogs
3. **VM Isolation**: Code execution happens inside an isolated Linux VM, not on the host
4. **VirtioFS Boundaries**: Only user-selected directories are shared with the VM
5. **NAT Networking**: VM network traffic is isolated from the host network stack

The agent cannot:
- Access files outside user-granted directories
- Execute code directly on the host system
- Modify system files or preferences
- Access other applications' data

## Development Status

OpenWork is under active development. Current status:

- [x] Core agent loop with tool calling
- [x] Multi-provider LLM support
- [x] Basic tool set (read, write, edit, bash, glob, grep, ls)
- [x] Linux VM integration
- [x] Doom loop detection
- [x] Real-time logging
- [ ] Snapshot/restore for VM state
- [ ] MCP (Model Context Protocol) server support
- [ ] Permission system with approval workflows
- [ ] File diff visualization

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes with clear commit messages
4. Submit a pull request

## License

MIT License

Copyright (c) 2026 OpenWork Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
