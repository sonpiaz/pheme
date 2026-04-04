# Contributing to Pheme

Thanks for your interest in contributing! Here's how to get started.

## Development Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/sonpiaz/pheme.git
   cd pheme
   ```

2. **Install XcodeGen** (if not already installed)
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project**
   ```bash
   make generate
   ```

4. **Open in Xcode**
   ```bash
   open Pheme.xcodeproj
   ```

5. **Set your OpenAI API key** in the app's Settings after first launch.

## Making Changes

1. Fork the repo and create a feature branch:
   ```bash
   git checkout -b feat/your-feature
   ```

2. Make your changes and ensure the project builds:
   ```bash
   make build
   ```

3. Commit with a descriptive message:
   ```bash
   git commit -m "feat: add your feature description"
   ```

4. Push and open a Pull Request.

## Commit Convention

We use conventional commits:

- `feat:` — new feature
- `fix:` — bug fix
- `chore:` — maintenance, refactoring
- `docs:` — documentation changes

## Code Style

- Follow existing Swift conventions in the codebase
- Use SwiftUI for all UI code
- Keep views small and composable
- No external dependencies — Apple frameworks only

## Reporting Issues

Open an issue with:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs from `~/Library/Logs/Pheme/`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
