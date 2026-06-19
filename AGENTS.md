# kodAI

## Stack
- iOS: llama.cpp (C++ backend), GGUF/Qwen2.5
- Mac: Apple Foundation Models
- Swift, SwiftUI, shared Swift package for on-device folders

## Changelog + commit rule
Before committing any change, ask me for a short title describing what changed
(e.g. "fixed KV cache bug" or "added TouchBar strip UI"). Wait for my answer.

Then, using that title:
1. Use it as the git commit message.
2. Append one line to CHANGELOG.md at the project root:

  ## YYYY-MM-DD
  - <my title>

3. Push to the remote (git push) right after committing, every time.

Do this every time, even if I don't explicitly ask for a commit.
Never invent the title yourself — always ask me first.
