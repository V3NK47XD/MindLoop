# MindLoop - System Architecture, Feature Inventory & Agent Guidelines

## 1. Project Overview & Gist
MindLoop is a cross-platform flashcard study system designed for automated AI generation, seamless PC-to-Mobile local synchronization, interactive study review with KaTeX math rendering, and rotational hashtag notification reminders.

### Core Stack:
- **Backend (`backend/`):**
  - **Framework:** FastAPI (Python 3.10+)
  - **AI Model:** Google GenAI Multimodal (`gemma-4-31b-it`) via Gemini API.
  - **ZIP Packaging:** Flashcards are packaged as standalone ZIP files containing `metadata.json` and an `assets/` directory (for images/attachments). Content hashes are computed from normalized questions and contents to ensure deduplication.
  - **Networking & Sync:** Real-time long-polling endpoints and a background Heartbeat Pruning daemon thread.
- **Frontend (`frontend/`):**
  - **Framework:** Vite + React 19.
  - **Design System:** Neobrutalist Warm/Graphite Notebook theme with responsive glassmorphic panels and custom scrollbars.
  - **Views:** Sync Center, PC Manage View, Connected Phone Manage View, and Notion/Obsidian/AppFlowy-style Workspace Editor.
  - **Editor Capabilities:** Dual/Split Live Canvas, Floating Slash Commands (`/`), Markdown + KaTeX rendering, Callout Alerts (`> [!NOTE]`), Document Statistics, and Attachment Asset Managers.
- **Mobile App (`mobile/`):**
  - **Framework:** Flutter (Dart).
  - **Local Database:** SQLite (`sqflite`) storing flashcards and UTC notification history logs (`notifications_history`).
  - **State Persistence:** `SharedPreferences` storing persistent Flashcard View Counter maps (`card_view_counts`), rotational hashtag checklist arrays (`shuffled_hashtags`, `completed_hashtags`), and notification frequency settings.
  - **Navigation:** 3-Tab Bottom Navigation Bar (Review History Logs, Sync & Library List, Settings).
  - **Background Notifications:** `flutter_local_notifications` with exact alarm capabilities (`zonedSchedule`), executing UTC-aligned notification scheduling routines.

---

## 2. Feature Inventory & Implementation Breakdown

### A. Multimodal PDF Flashcard Generation (`backend/app/services/generator.py`)
- **How it works:** Accepts uploaded PDF files, posts them to Google GenAI Files API (`uploaded_file`), and passes both the file handle and prompt to `gemma-4-31b-it`.
- **JSON Parsing:** Uses robust regex fallback parsing (`extract_json_from_response`) to extract structured flashcards containing `question`, `answer` (with Markdown & KaTeX equations), `tags` (strictly 1 tag per card), and reference line info.

### B. Flashcard ZIP Packaging & Local Asset Management (`backend/app/main.py` & `mobile/lib/services/storage_service.dart`)
- **Storage Format:** Flashcards are stored as `.zip` archives under `backend/storage/cards/`.
- **`metadata.json`:** Includes `id` (hash), `question`, `answer`, `tags`, `source_pdf`, `pdf_page`, `created_at`, `attachments`.
- **`assets/` Folder:** Images attached manually or extracted are saved inside the ZIP. Relative image markdown syntax `![alt](assets/filename.png)` is used across all clients.

### C. Real-Time Pairing & Keep-Alive Sync Protocol (`backend/app/routers/pairing.py` & `sync.py`)
- **Device Sessions:** Connected devices send heartbeat pings to `/api/pairing/heartbeat/{device_id}` every 4 seconds.
- **Daemon Thread:** A background Thread checks active devices every 3 seconds. Devices silent for > 8 seconds are automatically pruned, instantly notifying long-polling web clients.
- **Sync Cycle:** Phone requests sync, receiving missing PC flashcards while sending phone library manifests.

### D. Persistent Flashcard View Counter (`mobile/lib/views/card_view.dart` & `home_view.dart`)
- **Key-Value Tracking:** In Flutter, a JSON string map (`Map<String, int>`) is stored under `SharedPreferences` key `'card_view_counts'`.
- **Card Reveal Increment:** When the user taps to flip/reveal the back of a card in `CardView`, `_incrementViewCount` increments the card's view count and saves to storage.
- **List Badges:** `home_view.dart` renders an amber eye badge (`👁️ 15`) next to tag badges for cards with `views > 0`.
- **Deletion Pruning:** `StorageService.deleteCard` automatically removes the card's ID from the view counter map.

### E. Rotational Hashtag Notifications & UTC History (`mobile/lib/services/notification_service.dart`)
- **Active Tag Lock:** The notification engine locks scheduling to the active tag group (first uncompleted tag in the shuffled rotation).
- **View-Based Progression:** A tag group is considered completed ONLY when all cards under that tag have been revealed (`view_count > 0`), or when the user manually checks it complete in Settings.
- **Priority Queue:** Schedules up to 48 upcoming alarms over 7 days, placing **unviewed cards first**.
- **UTC Timezone Standard:** All notification logs in SQLite (`notifications_history`) use UTC ISO8601 strings (`.toUtc().toIso8601String()`) to guarantee accurate string comparisons when querying past review logs.

### F. Notion / Obsidian / AppFlowy Style Workspace Editor (`frontend/src/components/MarkdownEditor.jsx`)
- **Split Live Canvas:** Edit mode, Split side-by-side mode, Live preview mode.
- **Slash Commands (`/`):** Floating block menu for Headings, Bullet/Numbered/Task Lists, Quotes, Callouts (`> [!NOTE]`), Math Blocks (`$$`), Tables, Dividers, Code Blocks.
- **KaTeX Math & Callouts:** Live rendering of KaTeX math formulas and colored callout banners.
- **Statistics Bar:** Real-time words, characters, lines, and estimated read time.

---

## 3. Developer & AI Agent Extension Guidelines

When adding or modifying features across MindLoop, follow these rules:

### A. Backend (`backend/app/`)
1. **API Contract Integrity:** Maintain existing JSON response formats for `/api/cards`, `/api/pairing`, and `/api/sync`.
2. **Asset Path Resolution:** Always ensure image attachments inside ZIP files are named with clean basenames under `assets/`.
3. **Threading Safety:** Do not block main FastAPI event loops; run heavy I/O or GenAI network requests in async functions or worker threads.

### B. Frontend (`frontend/src/`)
1. **Neobrutalist Styling & Glassmorphic Rules:** Use design tokens from `index.css` (`var(--cyan)`, `var(--panel-bg)`, `var(--border-color)`, `box-shadow: 4px 4px 0px var(--shadow-color)`).
2. **Editor Consistency:** When adding new block types to `MarkdownEditor.jsx`, update both `SLASH_COMMANDS` array, formatting toolbar buttons, and `renderMarkdownHTML` parser.

### C. Mobile App (`mobile/lib/`)
1. **UTC Standard for SQLite:** Always store and query timestamps in SQLite as UTC strings (`.toUtc().toIso8601String()`).
2. **Async Context Guarding:** Ensure `if (mounted)` checks are performed before calling `setState` or navigating across async gaps.
3. **No UI Thread Blocking:** Perform database and `SharedPreferences` operations asynchronously to keep animations and card flipping smooth at 60fps.
