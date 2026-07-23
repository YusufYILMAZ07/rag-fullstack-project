# rag_frontend

Flutter frontend for uploading PDF files and metadata to a backend endpoint.

## What this app does

- Selects a PDF file from device or browser.
- Sends multipart upload with:
  - `file`
  - `course_name`
  - `user_id`
  - `study_focus`
- Shows success and detailed error feedback in the UI.

## Prerequisites

- Flutter SDK (stable channel)
- A running backend endpoint compatible with multipart upload
- Backend route: `/api/v1/upload-pdf`

## Install and run

1. Install packages:

```bash
flutter pub get
```

2. Run app:

```bash
flutter run
```

3. Optional: force backend URL at launch:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1/upload-pdf
```

## Backend URL behavior

- Web, iOS, macOS, Linux, Windows default:
  - `http://localhost:8000/api/v1/upload-pdf`
- Android emulator default:
  - `http://10.0.2.2:8000/api/v1/upload-pdf`

If you enter only a host URL (for example `http://10.0.2.2:8000`), the app automatically appends `/api/v1/upload-pdf`.

For real devices, use your computer LAN IP (for example `http://192.168.1.20:8000/api/v1/upload-pdf`).

## Validation and quality gates

Run static analysis:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

## Troubleshooting

- Error: backend is unreachable
  - Verify backend process is running on port `8000`.
  - Verify route exists: `/api/v1/upload-pdf`.
  - From host machine, test quickly:

```bash
curl -v http://localhost:8000/api/v1/upload-pdf
```

- Android emulator cannot access localhost
  - Use `10.0.2.2` instead of `localhost`.

- Timeout during upload
  - Check backend logs.
  - Check file size and network latency.
  - Retry after confirming endpoint responds.
