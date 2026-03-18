# dart-lsp
Dart/Flutter language server for Claude Code, providing code intelligence features like go-to-definition, find references, hover information, and error checking.

## Supported Extensions
`.dart`

## Installation
The Dart language server is included with the Dart SDK. Ensure you have Dart or Flutter installed:

### Dart SDK
```bash
# macOS (Homebrew)
brew tap dart-lang/dart
brew install dart
# Windows (Chocolatey)
choco install dart-sdk
# Linux (apt)
sudo apt-get install dart
```

### Flutter SDK (includes Dart)
```bash
# macOS (Homebrew)
brew install flutter
# Or download from https://flutter.dev/docs/get-started/install
```

## Verification
Verify the language server is available:
```bash
dart language-server --help
```

## Custom Dart Binary (Version Managers)

If you use a version manager like [puro](https://puro.dev/) or [fvm](https://github.com/leoafarias/fvm),
set the `DART_EXECUTABLE` environment variable in your Claude Code settings (`~/.claude/settings.json`):

```json
{
  "env": {
    "DART_EXECUTABLE": "puro dart"
  }
}
```

Users with a standard Dart/Flutter installation don't need to change anything —
the plugin falls back to `dart` from `PATH`.

**Windows:** Requires `sh` to be available (e.g. via Git Bash or WSL).

## More Information
- [Dart SDK](https://dart.dev/get-dart)
- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Dart Language Server Protocol](https://github.com/dart-lang/sdk/tree/main/pkg/analysis_server)