# OpenWork Testing Guide

## Manual Integration Tests

### Phase 0: VM Command Execution

#### Test 0.1: VM Boot and Console I/O
- [ ] Launch OpenWork
- [ ] Go to Settings → Virtual Machine
- [ ] Click "Start VM"
- [ ] Verify VM state changes: Stopped → Starting → Running
- [ ] Verify "Ready" indicator appears

#### Test 0.2: Command Execution in VM
- [ ] Create a new task: "Run `ls /` and show the output"
- [ ] Verify output shows Linux root filesystem (bin, etc, home, usr, var)
- [ ] Verify output does NOT show macOS paths (/Applications, /Users, /System)
- [ ] Create task: "Run `uname -a`"
- [ ] Verify output shows "Linux" not "Darwin"

#### Test 0.3: Shared Folder Access
- [ ] Create a project folder on your Mac (e.g., ~/TestProject)
- [ ] Add a test file: `echo "hello" > ~/TestProject/test.txt`
- [ ] In OpenWork, set working directory to ~/TestProject
- [ ] Create task: "Read the contents of test.txt"
- [ ] Verify agent can read the file via VirtioFS mount

#### Test 0.4: Command Timeout Handling
- [ ] Create task: "Run `sleep 300`" (5 minutes)
- [ ] Cancel the task after 10 seconds
- [ ] Verify task cancels cleanly without hanging

#### Test 0.5: VM Auto-Start
- [ ] Stop the VM manually
- [ ] Create a new task
- [ ] Verify VM auto-starts when task begins

#### Test 0.6: VM Idle Shutdown
- [ ] Start the VM
- [ ] Wait 5+ minutes without any tasks
- [ ] Verify VM stops automatically (check Settings → VM status)

---

### Phase 1: Core Features

#### Test 1.1: Parallel Task Execution
- [ ] Create 5 tasks rapidly in sequence:
  - "Count to 10 slowly"
  - "List files in /tmp"
  - "Show current date"
  - "Echo hello world"
  - "Show disk usage"
- [ ] Verify all 5 tasks run concurrently (check task list shows multiple "Running")
- [ ] Verify all complete successfully

#### Test 1.2: Task Queue and Priority
- [ ] Pause the task queue (if UI available)
- [ ] Add 3 tasks with different priorities
- [ ] Resume queue
- [ ] Verify high-priority tasks execute first

#### Test 1.3: Task Cancellation
- [ ] Start a long-running task
- [ ] Click cancel
- [ ] Verify task stops and shows "Cancelled" status
- [ ] Verify no zombie processes

#### Test 1.4: Approval Workflow
- [ ] Create task that requires file write: "Create a file called test.txt with 'hello'"
- [ ] Verify approval dialog appears
- [ ] Click "Approve"
- [ ] Verify file is created
- [ ] Repeat but click "Deny"
- [ ] Verify file is NOT created

#### Test 1.5: MCP Server Connection
- [ ] Go to Settings → MCP Servers
- [ ] Add Filesystem preset
- [ ] Click "Connect"
- [ ] Verify status shows "Connected"
- [ ] Create task: "Use the filesystem MCP to list files"
- [ ] Verify MCP tools are available to agent

#### Test 1.6: Session Persistence
- [ ] Create several tasks
- [ ] Quit OpenWork completely
- [ ] Relaunch OpenWork
- [ ] Verify task history is preserved

---

### Phase 2: Feature Parity

#### Test 2.1: Browser Automation
- [ ] Go to Settings → Advanced
- [ ] Start Playwright server (if manual start required)
- [ ] Create task: "Open a browser and go to example.com"
- [ ] Verify browser launches (headless or visible)
- [ ] Create task: "Take a screenshot of the current page"
- [ ] Verify screenshot is captured

#### Test 2.2: Keychain Storage
- [ ] Go to Settings → Providers
- [ ] Add OpenAI provider with API key
- [ ] Quit and relaunch OpenWork
- [ ] Verify API key is still present (loaded from Keychain)
- [ ] Open Keychain Access app
- [ ] Search for "openwork"
- [ ] Verify credentials are stored securely

#### Test 2.3: Provider - Ollama
- [ ] Ensure Ollama is running locally (`ollama serve`)
- [ ] Go to Settings → Providers
- [ ] Select Ollama provider
- [ ] Click "Test Connection"
- [ ] Verify "Connection successful"
- [ ] Create a simple task
- [ ] Verify response comes from Ollama

#### Test 2.4: Provider - OpenAI
- [ ] Add OpenAI provider with valid API key
- [ ] Set as active provider
- [ ] Click "Test Connection"
- [ ] Verify success
- [ ] Create task and verify GPT response

#### Test 2.5: Provider - Anthropic
- [ ] Add Anthropic provider with valid API key
- [ ] Set as active provider
- [ ] Click "Test Connection"
- [ ] Verify success (check for anthropic-version header)
- [ ] Create task and verify Claude response

#### Test 2.6: Provider - Google Gemini
- [ ] Add Gemini provider with valid API key
- [ ] Set as active provider
- [ ] Click "Test Connection"
- [ ] Verify success
- [ ] Create task and verify Gemini response

#### Test 2.7: Task History Search
- [ ] Create several tasks with different descriptions
- [ ] Go to task history view
- [ ] Search for a specific keyword
- [ ] Verify filtering works correctly

---

### Phase 3: Unique Features

#### Test 3.1: Skills System
- [ ] Go to Settings → Skills
- [ ] Browse available skills by category
- [ ] Activate "Document" skill
- [ ] Create task: "Create a markdown document about testing"
- [ ] Verify document skill tools are available
- [ ] Deactivate skill
- [ ] Verify tools are no longer available

#### Test 3.2: Google Drive Connector
- [ ] Go to Settings → Connectors
- [ ] Enter Google OAuth Client ID/Secret
- [ ] Click "Connect" for Google Drive
- [ ] Complete OAuth flow in browser
- [ ] Verify status shows "Connected"
- [ ] Create task: "List my Google Drive files"
- [ ] Verify Drive API is called and files are listed

#### Test 3.3: Notion Connector
- [ ] Go to Settings → Connectors
- [ ] Enter Notion OAuth credentials
- [ ] Click "Connect"
- [ ] Complete OAuth flow
- [ ] Verify connected status
- [ ] Create task: "Search my Notion for 'meeting notes'"
- [ ] Verify Notion search works

#### Test 3.4: VM Snapshot Creation
- [ ] Ensure VM is running
- [ ] Go to Snapshots view (or use keyboard shortcut)
- [ ] Create snapshot named "Clean State"
- [ ] Verify snapshot appears in list
- [ ] Check APFS snapshot was created: `tmutil listlocalsnapshots /`

#### Test 3.5: VM Snapshot Rollback
- [ ] Create a snapshot
- [ ] Run task: "Create file /tmp/testfile.txt"
- [ ] Verify file exists
- [ ] Click "Rollback" to previous snapshot
- [ ] Verify file no longer exists (state restored)

---

## Automated Test Checklist

Run with: `xcodebuild test -scheme OpenWork -destination 'platform=macOS'`

### Unit Tests by Component

| Component | Test File | Tests |
|-----------|-----------|-------|
| VMManager | VMManagerTests.swift | State transitions, path translation |
| TaskManager | TaskManagerTests.swift | Queue operations, parallel execution |
| ProviderManager | ProviderManagerTests.swift | CRUD, connection testing |
| MCPManager | MCPManagerTests.swift | Config management, tool registration |
| KeychainManager | KeychainManagerTests.swift | Save/load/delete operations |
| SkillRegistry | SkillRegistryTests.swift | Activation, tool registration |
| ConnectorRegistry | ConnectorRegistryTests.swift | OAuth flow, tool exposure |
| VMSnapshotManager | VMSnapshotManagerTests.swift | Snapshot CRUD, APFS integration |
| BrowserManager | BrowserManagerTests.swift | Server lifecycle, session management |

---

## Performance Tests

#### Memory Usage
- [ ] Launch OpenWork
- [ ] Note baseline memory in Activity Monitor
- [ ] Run 10 tasks in sequence
- [ ] Verify memory doesn't grow unbounded
- [ ] Expected: < 500MB for app, < 2GB for VM

#### Response Latency
- [ ] Time from task submit to first agent response
- [ ] Expected: < 2 seconds with local Ollama
- [ ] Expected: < 5 seconds with cloud providers

#### VM Boot Time
- [ ] Time from "Start VM" click to "Ready" state
- [ ] Expected: < 30 seconds

---

## Security Tests

#### Sandbox Isolation
- [ ] Create task: "Read /etc/passwd from the host Mac"
- [ ] Verify agent cannot access host filesystem outside shared folders
- [ ] Create task: "Run `curl` to exfiltrate data"
- [ ] Verify network access is appropriately restricted

#### Credential Protection
- [ ] Verify API keys are never logged to console
- [ ] Verify API keys are not stored in UserDefaults (check with `defaults read`)
- [ ] Verify Keychain items require user password/Touch ID

#### Path Traversal
- [ ] Create task trying to access `../../etc/passwd`
- [ ] Verify path traversal is blocked

---

## Error Handling Tests

#### Network Failures
- [ ] Disconnect from internet
- [ ] Try to use cloud provider
- [ ] Verify graceful error message (not crash)

#### Provider Unavailable
- [ ] Stop Ollama server
- [ ] Try to create task
- [ ] Verify helpful error message

#### MCP Server Crash
- [ ] Connect to MCP server
- [ ] Kill the MCP server process
- [ ] Verify OpenWork handles disconnection gracefully

#### VM Crash Recovery
- [ ] While VM is running, force-kill the VM process
- [ ] Verify OpenWork detects the crash
- [ ] Verify VM can be restarted

---

## Regression Test Checklist

Before each release, verify:

- [ ] All Phase 0 tests pass
- [ ] All Phase 1 tests pass
- [ ] All Phase 2 tests pass
- [ ] All Phase 3 tests pass
- [ ] All unit tests pass
- [ ] No memory leaks
- [ ] No console errors/warnings
- [ ] App signs and notarizes successfully
