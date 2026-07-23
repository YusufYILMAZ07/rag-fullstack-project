import asyncio
import os
import shutil
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from langchain_core.documents import Document
from pydantic import BaseModel
from faster_whisper import WhisperModel
from langchain_community.document_loaders import PyPDFLoader
from langchain_community.vectorstores import Chroma
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_ollama import ChatOllama


# Uygulamanın temel ayarları: yerel çalışma klasörü, vektör veritabanı ve sabit kullanıcı.
BASE_DIR = Path(__file__).resolve().parent
CHROMA_DIR = BASE_DIR / "chroma_db"
DEFAULT_USER_ID = "test_user_1"
OLLAMA_MODEL = "llama3"
WHISPER_MODEL_NAME = "base"



def _create_embeddings() -> HuggingFaceEmbeddings:
	# Embedding modeli tek sefer oluşturulup cache'lenir; ilk çağrıda probe vektör ile doğrulanır.
	embeddings = HuggingFaceEmbeddings(
		model_name="sentence-transformers/all-MiniLM-L6-v2",
		model_kwargs={"device": "cpu"},
		encode_kwargs={"normalize_embeddings": True},
	)

	probe_vector = embeddings.embed_query("embedding doğrulama metni")
	if not probe_vector:
		raise RuntimeError("HuggingFaceEmbeddings boş vektör döndürdü.")
	if all(value == 0 for value in probe_vector):
		raise RuntimeError("HuggingFaceEmbeddings sıfır vektör döndürdü.")

	return embeddings


@lru_cache(maxsize=1)
def get_embeddings() -> HuggingFaceEmbeddings:
	return _create_embeddings()


# Whisper modeli uygulama ilk açılırken yüklenir; böylece her istekte tekrar yükleme yapılmaz.
WHISPER = WhisperModel(WHISPER_MODEL_NAME, device="cpu", compute_type="int8")


# Ollama ile çalışan yerel Llama 3 istemcisi.
LLM = ChatOllama(model=OLLAMA_MODEL, base_url="http://localhost:11434", temperature=0)


app = FastAPI(title="Eğitim Asistanı ve Odak Koçu API", version="1.0.0")

app.add_middleware(
	CORSMiddleware,
	allow_origins=["*"],
	allow_credentials=True,
	allow_methods=["*"],
	allow_headers=["*"],
)


class AskRequest(BaseModel):
	# Kullanıcı sorusu. RAG akışında bağlam ile birlikte Llama 3'e gönderilir.
	question: str

	# Hangi dersin belgeleriyle cevap üretileceğini belirler.
	course_name: str


def get_vectorstore() -> Chroma:
	# Chroma DB klasörü yoksa otomatik oluşturulur.
	CHROMA_DIR.mkdir(parents=True, exist_ok=True)
	return Chroma(
		collection_name="education_assistant",
		embedding_function=get_embeddings(),
		persist_directory=str(CHROMA_DIR),
	)


def build_metadata_filter(course_name: str) -> Dict[str, Any]:
	# Sorguları sadece sabit kullanıcı ve ilgili ders ile sınırlandırıyoruz.
	return {"$and": [{"user_id": DEFAULT_USER_ID}, {"course_name": course_name}]}


async def transcribe_audio_file(file_path: str) -> str:
	# faster-whisper senkron çalıştığı için ağır işi ayrı iş parçacığında çalıştırıyoruz.
	def _run_transcription() -> str:
		segments, _info = WHISPER.transcribe(file_path)
		return " ".join(segment.text.strip() for segment in segments if segment.text.strip())

	return await asyncio.to_thread(_run_transcription)


async def generate_llm_text(prompt: str) -> str:
	# Llama 3 çağrısını da event loop'u bloklamamak için thread'e alıyoruz.
	def _run() -> str:
		response = LLM.invoke(prompt)
		return response.content if hasattr(response, "content") else str(response)

	return await asyncio.to_thread(_run)


def safe_temp_file_path(original_name: Optional[str], suffix_fallback: str) -> str:
	# Yüklenen dosyanın uzantısını koruyup geçici bir dosya yolu oluşturuyoruz.
	suffix = Path(original_name).suffix if original_name else suffix_fallback
	with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
		return temp_file.name


def split_documents_to_chunks(documents: List[Any], chunk_size: int = 1000) -> List[Document]:
	# Ek bir text-splitter paketi eklememek için PDF sayfalarını basit ve kontrollü biçimde parçalıyoruz.
	chunks: List[Document] = []

	for document in documents:
		content = (document.page_content or "").strip()
		metadata = dict(document.metadata or {})

		if not content.strip():
			continue

		for start in range(0, len(content), chunk_size):
			end = start + chunk_size
			chunk_text = content[start:end].strip()
			if not chunk_text:
				continue

			chunk_metadata = dict(metadata)
			chunk_metadata["chunk_index"] = len(chunks)

			chunks.append(Document(page_content=chunk_text, metadata=chunk_metadata))

	return chunks


@app.get("/health")
async def health() -> Dict[str, str]:
	# Basit sağlık kontrolü endpoint'i.
	return {"status": "ok"}


@app.post("/api/v1/analyze-lecture")
async def analyze_lecture(file: UploadFile = File(...)) -> JSONResponse:
	# Ses dosyasını geçici dosyaya kaydediyoruz.
	temp_path = safe_temp_file_path(file.filename, ".audio")

	try:
		with open(temp_path, "wb") as buffer:
			shutil.copyfileobj(file.file, buffer)

		# Ses dosyasını yazıya çevir.
		transcript = await transcribe_audio_file(temp_path)

		if not transcript.strip():
			raise HTTPException(status_code=400, detail="Ses dosyasından metin üretilemedi.")

		# Transcript'i yerel Llama 3'e gönderip sınav odaklı özet çıkarıyoruz.
		prompt = (
			"Sen bir akademik asistansın. Aşağıdaki ders dökümünü analiz et. "
			"Sınavda çıkabilecek yerleri özetle.\n\n"
			f"Ders dökümü:\n{transcript}"
		)
		try:
			summary = await generate_llm_text(prompt)
		except Exception as exc:
			raise HTTPException(status_code=500, detail=f"Llama 3 analiz sırasında hata verdi: {exc}")

		return JSONResponse(
			content={
				"user_id": DEFAULT_USER_ID,
				"transcript": transcript,
				"summary": summary,
			}
		)
	except HTTPException:
		raise
	except Exception as exc:
		raise HTTPException(status_code=500, detail=f"Ders analizi sırasında beklenmeyen hata oluştu: {exc}")
	finally:
		# Geçici dosya her durumda temizlenir.
		try:
			os.remove(temp_path)
		except FileNotFoundError:
			pass


@app.post("/api/v1/upload-pdf")
async def upload_pdf(pdf: UploadFile = File(..., alias="pdf"), course_name: str = Form(...)) -> JSONResponse:
	# PDF'yi geçici dosyaya kaydedip PyPDFLoader ile okuyacağız.
	temp_path = safe_temp_file_path(pdf.filename, ".pdf")

	try:
		with open(temp_path, "wb") as buffer:
			shutil.copyfileobj(pdf.file, buffer)

		try:
			loader = PyPDFLoader(temp_path)
			documents = loader.load()
		except Exception as e:
			print(str(e))
			raise HTTPException(status_code=500, detail=str(e))

		# Parçaları 1000 karakterlik chunk'lara bölüp metadatalarını ekliyoruz.
		chunks = split_documents_to_chunks(documents, chunk_size=1000)
		if not chunks:
			message = "PDF içinden indekslenecek metin çıkarılamadı."
			print(message)
			raise HTTPException(status_code=400, detail=message)
		for chunk in chunks:
			chunk.metadata.update({"user_id": DEFAULT_USER_ID, "course_name": course_name})

		# Chroma DB'ye yerel embedding ile kayıt.
		try:
			get_embeddings()
			vectorstore = get_vectorstore()
			vectorstore.add_documents(chunks)
			vectorstore.persist()
		except Exception as e:
			print(str(e))
			raise HTTPException(status_code=500, detail=str(e))

		return JSONResponse(
			content={
				"message": "PDF başarıyla işlendi ve vektör veritabanına kaydedildi.",
				"user_id": DEFAULT_USER_ID,
				"course_name": course_name,
				"chunks_saved": len(chunks),
			}
		)
	except HTTPException as e:
		if e.status_code == 400:
			print(str(e.detail))
		raise HTTPException(status_code=e.status_code, detail=str(e.detail))
	except Exception as e:
		print(str(e))
		raise HTTPException(status_code=500, detail=str(e))
	finally:
		# Geçici PDF dosyasını temizliyoruz.
		try:
			os.remove(temp_path)
		except FileNotFoundError:
			pass


@app.post("/api/v1/ask")
async def ask(request: AskRequest) -> JSONResponse:
	try:
		vectorstore = get_vectorstore()
		metadata_filter = build_metadata_filter(request.course_name)

		# Sadece ilgili kullanıcı ve ders etiketli dokümanları çekiyoruz.
		retrieved_docs = vectorstore.similarity_search(
			request.question,
			k=4,
			filter=metadata_filter,
		)

		context_parts: List[str] = []
		for index, doc in enumerate(retrieved_docs, start=1):
			context_parts.append(f"[Kaynak {index}] {doc.page_content}")

		context_text = "\n\n".join(context_parts) if context_parts else "İlgili bağlam bulunamadı."

		# RAG prompt'u: önce ilgili bağlam, sonra kullanıcı sorusu.
		prompt = (
			"Sen bir eğitim asistanısın. Aşağıdaki bağlamı kullanarak kısa, net ve doğru cevap ver. "
			"Eğer bağlam yetersizse bunu açıkça söyle.\n\n"
			f"Bağlam:\n{context_text}\n\n"
			f"Soru: {request.question}"
		)
		try:
			answer = await generate_llm_text(prompt)
		except Exception as exc:
			raise HTTPException(status_code=500, detail=f"Llama 3 cevap üretirken hata verdi: {exc}")

		return JSONResponse(
			content={
				"user_id": DEFAULT_USER_ID,
				"course_name": request.course_name,
				"answer": answer,
				"retrieved_documents": len(retrieved_docs),
			}
		)
	except HTTPException:
		raise
	except Exception as exc:
		raise HTTPException(status_code=500, detail=f"Soru-cevap sırasında beklenmeyen hata oluştu: {exc}")


if __name__ == "__main__":
	# Doğrudan çalıştırma senaryosu için yerel sunucu başlatılır.
	import uvicorn

	uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
