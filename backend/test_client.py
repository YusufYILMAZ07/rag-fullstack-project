"""Yerel FastAPI backend'ini hızlıca test etmek için istemci betiği.

Beklenen akış:
    1. Aynı dizindeki test1.pdf dosyasını /api/v1/upload-pdf endpoint'ine yükle.
2. Yükleme yanıtını ekrana yazdır.
3. /api/v1/ask endpoint'ine RAG sorusunu gönder.
4. Modelin ürettiği nihai cevabı okunaklı biçimde göster.
"""

from __future__ import annotations

from pathlib import Path
import sys

import requests


BASE_URL = "http://localhost:8000"
PDF_PATH = Path(__file__).with_name("test1.pdf")
COURSE_NAME = "Ayrık Matematik"


def upload_pdf() -> dict:
    """PDF dosyasını backend'e yükler ve JSON yanıtını döndürür."""
    if not PDF_PATH.exists():
        raise FileNotFoundError(f"PDF bulunamadı: {PDF_PATH}")

    url = f"{BASE_URL}/api/v1/upload-pdf"

    with PDF_PATH.open("rb") as pdf_file:
        files = {"pdf": (PDF_PATH.name, pdf_file, "application/pdf")}
        data = {"course_name": COURSE_NAME}
        response = requests.post(url, files=files, data=data, timeout=60)

    response.raise_for_status()
    return response.json()


def ask_question() -> dict:
    """RAG endpoint'ine soru gönderir ve JSON yanıtını döndürür."""
    url = f"{BASE_URL}/api/v1/ask"
    payload = {
        "question": "Bu belgenin içeriğinde nelerden bahsediliyor?",
        "course_name": COURSE_NAME,
    }

    response = requests.post(url, json=payload, timeout=60)
    response.raise_for_status()
    return response.json()


def main() -> int:
    try:
        print("[1/2] PDF yükleniyor...")
        upload_result = upload_pdf()
        print("Yükleme başarılı:")
        print(upload_result)
        print()

        print("[2/2] RAG sorusu gönderiliyor...")
        ask_result = ask_question()

        answer = ask_result.get("answer", "Yanıt alanı bulunamadı.")
        print("Nihai RAG cevabı:")
        print("-" * 60)
        print(answer)
        print("-" * 60)
        return 0
    except requests.RequestException as exc:
        print(f"İstek hatası: {exc}", file=sys.stderr)
        return 1
    except FileNotFoundError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    except Exception as exc:
        print(f"Beklenmeyen hata: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())