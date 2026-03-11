# spec.md — macOS MP4 Movie Metadata Tagger (TMDb)

## 1) Summary
Build a native macOS app that:
- Accepts a user-selected **.mp4** file as input.
- **Preserves existing audio/video streams (no transcoding / no re-encode).** Container remuxing is allowed if needed to write metadata.
- Prompts the user for a **movie name**, searches **The Movie Database (TMDb)**, fetches **movie metadata + poster**, lets the user **review/edit**, then **writes metadata into the MP4 file**.
- Renames the MP4 to **“Title - (Year).m4v”** by default, with a user-configurable naming pattern.

## 2) Goals (MVP)
1. Choose an MP4 file via file picker (drag/drop optional).
2. Ask user for movie name (prefill from filename if possible).
3. Search TMDb and allow user to select the correct movie.
4. Fetch:
   - Core movie details (title, release date/year, overview, runtime, genres, etc.)
   - Poster image (highest available resolution preferred)
5. Present a review/edit screen:
   - Editable fields (title, year, description, genres, etc.)
   - Poster preview (and option to choose among available posters)
6. Write metadata into MP4 with **passthrough export/remux** (no stream re-encode).
7. Rename output file:
   - Default: `Title - (Year).m4v`
   - Optional custom naming pattern with tokens and a live preview
8. Show progress + clear errors; never silently overwrite without consent.

## 3) Non-goals (for MVP)
- MKV/AVI support
- TV shows / episodic metadata (possible future)
- Batch processing (possible future)
- Downloading subtitles, chapters, or extras
- DRM / protected files

## 4) Target Platform / Tech
- macOS 13+ (Ventura) recommended (adjust as desired)
- Swift + SwiftUI
- AVFoundation for reading/writing metadata using **passthrough** export
- URLSession (async/await) for TMDb API calls
- Keychain for storing TMDb API credential

## 5) UX / Screens

### Screen A — “Select File”
- Button: “Choose MP4…”
- Drag & drop zone (optional)
- Show selected file name/path + basic media info (duration/resolution optional)
- Button: “Next”

### Screen B — “Find Movie”
- Input: Movie name (prefill from filename minus year/quality tags if detected)
- Search results list:
  - Poster thumbnail
  - Title
  - Year
  - Short overview
- Selecting a result loads details & moves forward

### Screen C — “Review & Edit”
Layout:
- Left: Poster preview, poster picker (dropdown/grid) if multiple posters
- Right: Editable fields (form):
  - Title (required)
  - Year (required if available; derived from release_date)
  - Overview/Description
  - Tagline (optional)
  - Genres (multi-select chips)
  - Runtime (minutes)
  - Original title, language (read-only or editable)
  - IDs (TMDb ID, IMDb ID if present) (read-only)
- File naming section:
  - Toggle: “Rename file on save” (default ON)
  - Naming pattern input + token helper + live preview
- Button: “Write Metadata” (primary)
- Button: “Cancel”

### Screen D — “Progress / Result”
- Progress bar (export/remux + writing)
- Result summary:
  - Output path
  - “Reveal in Finder” button
  - “Open file” button (optional)
- If user chose “Replace original”, show confirmation + backup option.

## 6) TMDb Integration

### Auth / Credentials
- Require a TMDb API key or token (user supplies in Settings on first run).
- Store securely in Keychain.
- Settings allow changing the key and preferred language/region.

### Endpoints (v3)
- Search movies by text query.
- Fetch movie details by ID.
- Fetch configuration to build poster URLs (secure_base_url + poster_sizes).
- Fetch movie images (posters) to allow user selection.

### Poster selection strategy
- Default: use movie’s primary `poster_path` (from details) at `original` size.
- If user opens poster picker, load `/movie/{id}/images` and show available posters (prefer language match).

### Rate limiting / resilience
- Handle HTTP errors (401, 404, 429, 5xx).
- Backoff on 429 (simple retry with exponential delay, max 3 attempts).
- Cache configuration response in memory (and optionally persisted for 24h).

## 7) Metadata to Write (MP4)

### Important: “No transcoding”
Implementation must not decode/re-encode audio/video. Use:
- AVAssetExportSession preset **Passthrough** (or equivalent) so output uses current encoded streams.
- Export to a new MP4 file, then optionally replace original.

### What “all metadata” means in this app
Write:
1) A **standardized, player-friendly subset** into common MP4/QuickTime/iTunes metadata fields (for Finder / Apple TV / Plex-style readers).
2) The **full raw TMDb JSON payload(s)** into a custom metadata item (namespaced) so nothing is lost, and future tooling can rehydrate it.

### Field mapping (subset)
Minimum set:
- Title
- Year (from release_date)
- Description/Overview
- Genres (comma-separated string)
- Runtime (minutes)
- TMDb ID
- IMDb ID (if available)
- Poster artwork (embedded)

Recommended additional:
- Tagline
- Original title
- Original language
- Release date (full date)
- Vote average / vote count (optional)
- Production companies (optional)

### Custom metadata payload
- Store JSON in a custom namespaced metadata item, e.g.:
  - key: `com.yourcompany.movietagger.tmdb`
  - value: JSON string (UTF-8)
- Payload should include:
  - movie details response JSON
  - selected poster file path + URL used
  - timestamp of fetch
  - language/region used

### Overwrite rules
- Default: overwrite the mapped fields (Title/Year/Description/Artwork/etc.)
- Preserve unrelated existing metadata items unless user chooses “Replace all metadata” (future option).

## 8) File Output & Rename

### Output strategy
- Export/remux to a temporary file in the same directory (or app temp dir), then move into place.
- Options:
  1) “Replace original file” (default ON) with optional “Keep backup” (default OFF)
  2) “Save as new file…” (choose destination) (optional for MVP, but recommended)

### Default file naming
- `"{title} ({year}).mp4"`

### Custom naming pattern
- User-provided pattern string with tokens:
  - `{title}` (sanitized)
  - `{year}`
  - `{tmdb_id}`
  - `{imdb_id}`
- Example: `"{title} ({year}) [{tmdb_id}].mp4"`
- Live preview + validation.
- Sanitization rules:
  - Remove/replace characters invalid on macOS paths: `/` and `:` (and generally strip control chars).
  - Trim whitespace and trailing dots.
- Collision handling:
  - If filename exists, append ` " (1)"`, ` " (2)"`, etc., unless user chooses overwrite.

## 9) Architecture / Modules

### Core modules
- `TMDbClient`
  - searchMovies(query, language, region)
  - fetchMovieDetails(id, language)
  - fetchConfig()
  - fetchMovieImages(id, language)
  - fetchImageBytes(url)
- `MovieMetadataMapper`
  - Converts TMDb models -> editable view model
  - Converts view model -> AVMetadataItem list + custom JSON payload
- `MetadataWriter`
  - readExistingMetadata(fileURL)
  - writeMetadataPassthrough(inputURL, outputURL, metadataItems)
- `FilenameFormatter`
  - format(pattern, movie)
  - sanitizeFilename(string)
  - resolveCollision(directoryURL, desiredName)
- `AppSettings`
  - TMDb credential (Keychain)
  - language/region
  - default naming pattern
  - default replace/backup toggles

### Data models (suggested)
- `TMDbMovieSearchResult`
- `TMDbMovieDetails`
- `TMDbConfig`
- `TMDbImagesResponse`
- `MovieEditModel` (the user-editable canonical model)

## 10) Key Flows

### Flow 1: Happy path
1. User selects MP4
2. User enters movie name
3. Select search result
4. App fetches details + posters
5. User edits fields and naming
6. App exports MP4 passthrough with new metadata
7. App renames/moves file; shows success

### Flow 2: Multiple matches / wrong movie
- User chooses a different result; model refreshes; edits preserved only if user opts “Keep my edits” (future). For MVP, reset to fetched values.

### Flow 3: Network failure
- Show error + retry; allow manual entry/edit without TMDb (optional future). For MVP: require TMDb fetch to proceed.

### Flow 4: Metadata write fails
- Show export error; keep original file untouched; provide logs + “Try again”.

## 11) Error Handling
- Invalid file type / cannot read: show blocking error.
- No TMDb credentials: route to Settings.
- 401/403 from TMDb: prompt to update key.
- 429: backoff + retry + user message.
- File write permissions: prompt user to choose output directory or disable replace.
- Export session cannot do passthrough for this asset: show clear “cannot write without re-encoding” error and abort.

## 12) Privacy & Compliance
- TMDb attribution must appear in an About/Credits section and use an approved TMDb logo.
- Do not upload the MP4 anywhere; all processing is local.
- Store only:
  - TMDb credential in Keychain
  - user preferences (pattern, language) in UserDefaults
  - optional recent files list (user can disable)

## 13) Acceptance Criteria (MVP)
- App can take an MP4 and output an MP4 where:
  - Audio/video streams are preserved without re-encoding (passthrough/remux).
  - Title/year/overview/genres and poster artwork are embedded and visible in common macOS metadata viewers where applicable.
  - Full TMDb JSON is embedded in a custom metadata field.
- User can review and edit metadata before writing.
- File is renamed according to default or user pattern with preview and collision handling.
- Clear error messages for TMDb auth failure, rate limiting, and export/writing failures.

## 14) Implementation Plan (Cursor-friendly)
1. Scaffold SwiftUI macOS app + navigation flow.
2. Implement `Settings` + Keychain storage for TMDb credential.
3. Implement `TMDbClient` with endpoints + models + tests (mock URLProtocol).
4. Build Search UI + selection.
5. Build Review/Edit UI (MovieEditModel).
6. Implement `MovieMetadataMapper` (subset fields + JSON payload).
7. Implement `MetadataWriter` using AVAssetExportSession passthrough export to temp file.
8. Implement renaming + collision resolution + safe replace/backup logic.
9. End-to-end manual test with multiple MP4 samples; add regression tests for mapper and filename formatter.
10. Add About/Credits with TMDb logo + required attribution text.

## 15) Open Questions (answer anytime; defaults noted)
1. Distribution: Mac App Store (sandbox constraints) or direct download? (Default: direct/notarized)
2. Should “Replace original” be default ON or OFF? (Default: ON with confirmation + optional backup)
3. Do you want batch mode (multiple MP4s)? (Default: single file MVP)
4. Which players must metadata be optimized for (Finder/Apple TV/Plex/Infuse)? (Default: Finder + Apple ecosystem first)
5. Should the app allow manual metadata entry if TMDb is unreachable? (Default: no for MVP)