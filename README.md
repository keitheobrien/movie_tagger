# Movie Tagger

A native macOS application that automatically tags MP4 video files with rich movie metadata from [The Movie Database (TMDb)](https://www.themoviedb.org/). It updates MP4 metadata without re-encoding or quality loss, safely replaces the original file when the update is complete, and optionally renames it using a customizable pattern.

## Features

- **TMDb Integration** — Search TMDb by title, browse results with poster thumbnails, and pull comprehensive metadata including cast, crew, genres, content ratings, and more.
- **Safe, Lossless Metadata Writing** — Edits a same-volume temporary copy and atomically replaces the original only after the write succeeds. APFS uses a fast copy-on-write clone when available; other volumes need space for a full copy. Original audio and video streams and unrelated metadata tags are preserved.
- **Smart File Renaming** — Rename files using token-based patterns like `{title} ({year})` with live preview and automatic collision resolution.
- **Poster Embedding** — Downloads and embeds cover art directly into the file so media players display it automatically.
- **Drag & Drop** — Drop an MP4 file onto the window or use the file picker. The app detects resolution (SD/720p/1080p/4K) and duration automatically.
- **Secure API Key Storage** — Your TMDb API key is stored in macOS Keychain. Existing encrypted-file credentials migrate automatically and are removed only after Keychain accepts them.
- **No External Dependencies** — Built entirely with native Apple frameworks. No CocoaPods, SPM packages, or third-party libraries.

## Screenshots

<!-- Add screenshots here -->
<!-- ![File Selection](screenshots/file-selection.png) -->
<!-- ![Search Results](screenshots/search-results.png) -->
<!-- ![Review & Edit](screenshots/review-edit.png) -->

## Requirements

- **macOS 13.0** (Ventura) or later
- **Xcode 15.0+** (to build from source)
- A free **TMDb API key** ([get one here](https://www.themoviedb.org/settings/api))

## Installation

### Build from Source

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/movie-tagger.git
   cd movie-tagger
   ```

2. **Open in Xcode:**
   ```bash
   open MovieTagger.xcodeproj
   ```

3. **Build and run:**
   - Select the **MovieTagger** scheme and your Mac as the destination.
   - Press **Cmd + R** to build and run.

   Or build from the command line:
   ```bash
   xcodebuild build -scheme MovieTagger -configuration Release
   ```

4. **Install** (optional):
   - Locate `MovieTagger.app` in the Xcode build products directory.
   - Drag it to your **Applications** folder.

### Pre-built Release

Prefer not to build it yourself? Download the ready-to-run app. Requires **macOS 13.0 or later**.

1. Download [**MovieTagger-1.5.zip**](https://github.com/keitheobrien/movie_tagger/releases/download/v1.5/MovieTagger-1.5.zip) from the [v1.5 release page](https://github.com/keitheobrien/movie_tagger/releases/tag/v1.5) — or grab [the latest release](https://github.com/keitheobrien/movie_tagger/releases/latest) to always get the newest version. From 1.2 onward the app keeps itself up to date automatically.
2. Double-click the downloaded `.zip` to unzip it. This produces `MovieTagger.app`.
3. Drag `MovieTagger.app` into your **Applications** folder.
4. Double-click **MovieTagger** to open it. The build is signed with a Developer ID and notarized by Apple, so it launches right away with no security warnings.

Then follow the [Setup](#setup) section to add your TMDb API key.

## Setup

1. **Get a TMDb API key:**
   - Create a free account at [themoviedb.org](https://www.themoviedb.org/).
   - Go to **Settings > API** and request an API key (choose "Developer" for personal use).

2. **Enter your API key:**
   - Launch Movie Tagger.
   - Open **Settings** (Cmd + ,).
   - Paste your API key and click **Save**.

3. **Configure defaults** (optional):
   - **Language/Region** — Controls the language of metadata results (default: `en-US`).
   - **Naming Pattern** — Set your preferred filename template using tokens: `{title}`, `{year}`, `{tmdb_id}`, `{imdb_id}`.

## Usage

1. **Select a file** — Drag and drop an MP4 file onto the window, or click the file picker button.

2. **Search for the movie** — The app extracts a search query from the filename. Adjust the query if needed and browse results.

3. **Review & edit metadata** — After selecting a match, review the fetched metadata. You can edit the title, year, overview, tagline, cast, directors, screenwriters, producers, content rating, resolution, and studio. Change the poster if desired.

4. **Write & rename** — Click **Write Metadata** to start immediately. If renaming is enabled, the file is renamed according to your pattern. File selection stays locked until the operation finishes, and closing/reopening the window does not restart the write. The original video and audio are untouched.

## Metadata Written

Movie Tagger writes the following into the MP4 file:

| Atom | Field | Example |
|------|-------|---------|
| `©nam` | Title | The Shawshank Redemption |
| `©day` | Release Date | 1994-09-23 |
| `desc` | Short Description | (first 255 chars of overview) |
| `ldes` | Long Description | (full overview) |
| `©gen` | Genres | Drama, Crime |
| `©cmt` | Tagline | Fear can hold you prisoner... |
| `covr` | Cover Art | (poster JPEG data) |
| `stik` | Media Kind | Movie (9) |
| `hdvd` | HD Flag | 0=SD, 1=720p, 2=1080p, 3=4K |
| `iTunEXTC` | Content Rating | mpaa\|PG-13\|300\| |
| `iTunMOVI` | Extended Info | Cast, directors, screenwriters, producers, studio (XML plist) |

A custom `com.movietagger:tmdb_json` atom stores the complete TMDb response for future reference. Existing tags outside the fields managed by MovieTagger are retained, including existing artwork when no replacement poster is available. Editing the year updates both the filename and the embedded date; a changed year is written without an invented month/day.

Malformed atom layouts are rejected without changing the original. Standard and 64-bit atom headers are supported. Fragmented MP4s, non-iTunes handlers in `udta/meta`, movie indexes over 256 MB, and open-ended terminal atoms over 4 GB that would need to be resized are currently rejected safely. Ordinary MP4s with explicitly sized media atoms can exceed 4 GB.

## Project Structure

```
MovieTagger/
├── MovieTaggerApp.swift          # App entry point, AppState
├── ContentView.swift             # Root view / screen router
├── Models/
│   ├── MovieEditModel.swift      # Editable metadata view model
│   ├── MovieMetadata.swift       # Immutable write snapshot
│   └── TMDbModels.swift          # TMDb API response types
├── Services/
│   ├── TMDbClient.swift          # TMDb API client (Swift actor)
│   ├── KeychainHelper.swift      # Keychain storage + legacy migration
│   ├── MetadataWriter.swift      # Checked MP4 atom-level metadata writer
│   ├── AtomicFileUpdate.swift    # Same-volume staging + atomic replacement
│   ├── MetadataWriteCoordinator.swift # Single-operation ownership + rename
│   ├── UpdateChecker.swift       # Verified app updates
│   └── FilenameFormatter.swift   # Token-based filename generation
└── Views/
    ├── FileSelectionView.swift   # File picker + drag & drop
    ├── MovieSearchView.swift     # TMDb search results
    ├── ReviewEditView.swift      # Metadata review & editing
    ├── ProgressResultView.swift  # Write progress & results
    └── SettingsView.swift        # API key & preferences
```

## Technology

- **SwiftUI** — Declarative UI with custom FlowLayout for tag lists
- **Swift Concurrency** — async/await networking, actor-based API client
- **AVFoundation** — Video resolution and duration detection
- **Security / Keychain** — Credential storage; CryptoKit is used only to migrate legacy credentials
- **FileHandle** — Checked binary MP4 atom manipulation on a staged copy (no re-encoding)

## Development & Tests

The checked-in Xcode project includes a `MovieTaggerTests` target. Run:

```bash
xcodebuild test -project MovieTagger.xcodeproj -scheme MovieTagger \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Tests cover atom boundaries, extended headers, open-ended media, tag preservation, edited dates, failed staged writes, operation ownership, and credential migration. An AVFoundation integration test creates a real H.264 MP4 and verifies its encoded samples and duration remain unchanged after tagging. Tests use temporary files and in-memory credential stores; they do not access your API key or check for updates.

`project.yml` is the XcodeGen source. After adding source files or targets, regenerate the project with `xcodegen generate`. CI builds and runs the same test scheme on macOS.

## Attribution

This product uses the [TMDb API](https://www.themoviedb.org/documentation/api) but is not endorsed or certified by TMDb.

<img src="https://www.themoviedb.org/assets/2/v4/logos/v2/blue_short-8e7b30f73a4020692ccca9c88bafe5dcb6f8a62a4c6bc55cd9ba82bb2cd95f6c.svg" alt="TMDb Logo" width="120">

## License

<!-- Choose a license and add it here -->
<!-- This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details. -->

## Contributing

Contributions are welcome. Please open an issue to discuss proposed changes before submitting a pull request.
