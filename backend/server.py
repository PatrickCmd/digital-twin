from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, Field, field_validator
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import json
import time
import uuid
from datetime import datetime, timezone
import boto3
from botocore.exceptions import ClientError
from context import prompt
from rate_limit import client_ip, hash_ip, limiter_from_env

# Load environment variables
load_dotenv()

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

# Configure CORS
origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Initialize Bedrock client - see Q42 on https://edwarddonner.com/faq if the Region gives you problems
bedrock_client = boto3.client(
    service_name="bedrock-runtime",
    region_name=os.getenv("DEFAULT_AWS_REGION", "us-east-1")
)

# Bedrock model selection - see Q42 on https://edwarddonner.com/faq for more
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "global.amazon.nova-2-lite-v1:0")

# Memory storage configuration
USE_S3 = os.getenv("USE_S3", "false").lower() == "true"
S3_BUCKET = os.getenv("S3_BUCKET", "")
MEMORY_DIR = os.getenv("MEMORY_DIR", "../memory")

# Limits
MAX_MESSAGE_CHARS = int(os.getenv("MAX_MESSAGE_CHARS", "2000"))
# Stored messages per session (user + assistant). Beyond this the client must start a new chat.
MAX_SESSION_MESSAGES = int(os.getenv("MAX_SESSION_MESSAGES", "60"))
# How much history the model sees. Bedrock requires strictly alternating roles,
# so this is kept even so that the slice starts on a user turn.
HISTORY_WINDOW = 50

INFERENCE_CONFIG = {
    "maxTokens": 1200,
    "temperature": 0.4,
    "topP": 0.9,
}

rate_limiter = limiter_from_env()

# Initialize S3 client if needed
if USE_S3:
    s3_client = boto3.client("s3")


def log_event(event: str, **fields) -> None:
    """One structured JSON line per event, for CloudWatch Logs Insights."""
    record = {"event": event, "ts": datetime.now(timezone.utc).isoformat(), **fields}
    print(json.dumps(record, default=str))


# Request/Response models
class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=MAX_MESSAGE_CHARS)
    session_id: Optional[str] = None

    @field_validator("session_id")
    @classmethod
    def session_id_must_be_uuid(cls, value: Optional[str]) -> Optional[str]:
        if value in (None, ""):
            return None
        try:
            return str(uuid.UUID(value))
        except ValueError as exc:
            raise ValueError("session_id must be a UUID") from exc

    @field_validator("message")
    @classmethod
    def message_must_not_be_blank(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("message must not be blank")
        return value


class ChatResponse(BaseModel):
    response: str
    session_id: str


class Message(BaseModel):
    role: str
    content: str
    timestamp: str


class FeedbackRequest(BaseModel):
    session_id: str
    message_index: int = Field(ge=0, le=10000)
    rating: str = Field(pattern="^(up|down)$")
    comment: Optional[str] = Field(default=None, max_length=500)
    assistant_preview: Optional[str] = Field(default=None, max_length=300)

    @field_validator("session_id")
    @classmethod
    def feedback_session_id_must_be_uuid(cls, value: str) -> str:
        try:
            return str(uuid.UUID(value))
        except ValueError as exc:
            raise ValueError("session_id must be a UUID") from exc


# Error handling: every error body is {"error": <code>, "detail": <human text>}
def api_error(status_code: int, code: str, detail: str, headers: Optional[Dict[str, str]] = None) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"error": code, "detail": detail}, headers=headers)


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    body = exc.detail if isinstance(exc.detail, dict) else {"error": "error", "detail": str(exc.detail)}
    return JSONResponse(status_code=exc.status_code, content=body, headers=exc.headers)


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(_: Request, exc: RequestValidationError):
    code, detail = "invalid_request", "The request was not valid."
    for err in exc.errors():
        loc = err.get("loc", ())
        if "message" in loc and err.get("type") == "string_too_long":
            code = "message_too_long"
            detail = f"Messages are limited to {MAX_MESSAGE_CHARS} characters."
            break
        if "session_id" in loc:
            code, detail = "invalid_session", "The session id is not valid. Start a new chat."
            break
    return JSONResponse(status_code=422, content={"error": code, "detail": detail})


def enforce_rate_limit(request: Request) -> str:
    """Dependency: per-client rate limit. Returns the hashed client key for logging."""
    key = hash_ip(client_ip(request.scope))
    decision = rate_limiter.check(key)
    if not decision.allowed:
        log_event("rate_limited", client=key, retry_after=decision.retry_after, path=request.url.path)
        raise api_error(
            429,
            "rate_limited",
            "You have sent a lot of messages in a short time. Please wait a few minutes and try again.",
            headers={"Retry-After": str(max(decision.retry_after, 1))},
        )
    return key


# Memory management functions
def get_memory_path(session_id: str) -> str:
    return f"{session_id}.json"


def load_conversation(session_id: str) -> List[Dict]:
    """Load conversation history from storage"""
    if USE_S3:
        try:
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=get_memory_path(session_id))
            return json.loads(response["Body"].read().decode("utf-8"))
        except ClientError as e:
            if e.response["Error"]["Code"] == "NoSuchKey":
                return []
            raise
    else:
        # Local file storage
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return json.load(f)
        return []


def save_conversation(session_id: str, messages: List[Dict]):
    """Save conversation history to storage"""
    if USE_S3:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=get_memory_path(session_id),
            Body=json.dumps(messages, indent=2),
            ContentType="application/json",
        )
    else:
        # Local file storage
        os.makedirs(MEMORY_DIR, exist_ok=True)
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        with open(file_path, "w") as f:
            json.dump(messages, f, indent=2)


def store_record(prefix: str, record: Dict) -> str:
    """Write a small JSON record under <prefix>/<date>/<uuid>.json (S3 or local). Returns the key."""
    key = f"{prefix}/{datetime.now(timezone.utc).strftime('%Y-%m-%d')}/{uuid.uuid4()}.json"
    body = json.dumps(record, indent=2, default=str)
    if USE_S3:
        s3_client.put_object(Bucket=S3_BUCKET, Key=key, Body=body, ContentType="application/json")
    else:
        file_path = os.path.join(MEMORY_DIR, key)
        os.makedirs(os.path.dirname(file_path), exist_ok=True)
        with open(file_path, "w") as f:
            f.write(body)
    return key


def ensure_session_has_room(conversation: List[Dict]) -> None:
    if len(conversation) >= MAX_SESSION_MESSAGES:
        raise api_error(
            409,
            "session_full",
            "This conversation has reached its length limit. Please start a new chat.",
        )


def build_messages(conversation: List[Dict], user_message: str) -> List[Dict]:
    """Conversation history plus the new user turn, in Converse API format."""
    messages = []
    for msg in conversation[-HISTORY_WINDOW:]:
        messages.append({"role": msg["role"], "content": [{"text": msg["content"]}]})
    messages.append({"role": "user", "content": [{"text": user_message}]})
    return messages


def call_bedrock(conversation: List[Dict], user_message: str, stats: Optional[Dict] = None) -> str:
    """Call AWS Bedrock with conversation history"""
    messages = build_messages(conversation, user_message)

    try:
        # Call Bedrock using the converse API
        response = bedrock_client.converse(
            modelId=BEDROCK_MODEL_ID,
            system=[{"text": prompt()}],
            messages=messages,
            inferenceConfig=INFERENCE_CONFIG,
        )
        if stats is not None and "usage" in response:
            stats["usage"] = response["usage"]

        # Extract the response text
        return response["output"]["message"]["content"][0]["text"]

    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'ValidationException':
            # Handle message format issues
            print(f"Bedrock validation error: {e}")
            raise api_error(400, "bedrock_validation", "Invalid message format for Bedrock")
        elif error_code == 'AccessDeniedException':
            print(f"Bedrock access denied: {e}")
            raise api_error(403, "bedrock_access_denied", "Access denied to Bedrock model")
        else:
            print(f"Bedrock error: {e}")
            raise api_error(500, "bedrock_error", f"Bedrock error: {error_code}")


def stream_bedrock(conversation: List[Dict], user_message: str, stats: Optional[Dict] = None):
    """Stream response from AWS Bedrock using converse_stream API"""
    messages = build_messages(conversation, user_message)

    response = bedrock_client.converse_stream(
        modelId=BEDROCK_MODEL_ID,
        system=[{"text": prompt()}],
        messages=messages,
        inferenceConfig=INFERENCE_CONFIG,
    )

    stream = response.get("stream")
    if stream:
        for event in stream:
            if "contentBlockDelta" in event:
                text = event["contentBlockDelta"]["delta"]["text"]
                yield text
            elif "metadata" in event and stats is not None:
                stats["usage"] = event["metadata"].get("usage")


@app.get("/")
async def root():
    return {
        "message": "AI Digital Twin API (Powered by AWS Bedrock)",
        "memory_enabled": True,
        "storage": "S3" if USE_S3 else "local",
        "ai_model": BEDROCK_MODEL_ID
    }


@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "use_s3": USE_S3,
        "bedrock_model": BEDROCK_MODEL_ID
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest, client: str = Depends(enforce_rate_limit)):
    try:
        # Generate session ID if not provided
        session_id = request.session_id or str(uuid.uuid4())

        # Load conversation history
        conversation = load_conversation(session_id)
        ensure_session_has_room(conversation)

        # Call Bedrock for response
        started = time.perf_counter()
        stats: Dict = {}
        assistant_response = call_bedrock(conversation, request.message, stats)

        # Update conversation history
        conversation.append(
            {"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()}
        )
        conversation.append(
            {
                "role": "assistant",
                "content": assistant_response,
                "timestamp": datetime.now().isoformat(),
            }
        )

        # Save conversation
        save_conversation(session_id, conversation)
        log_event(
            "chat",
            session_id=session_id,
            client=client,
            stream=False,
            message_chars=len(request.message),
            response_chars=len(assistant_response),
            latency_ms=round((time.perf_counter() - started) * 1000),
            model=BEDROCK_MODEL_ID,
            usage=stats.get("usage"),
        )

        return ChatResponse(response=assistant_response, session_id=session_id)

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in chat endpoint: {str(e)}")
        raise api_error(500, "server_error", "Something went wrong. Please try again.")


@app.post("/chat/stream")
async def chat_stream(request: ChatRequest, client: str = Depends(enforce_rate_limit)):
    """Streaming chat endpoint using Server-Sent Events"""
    try:
        session_id = request.session_id or str(uuid.uuid4())
        conversation = load_conversation(session_id)
        ensure_session_has_room(conversation)

        def event_stream():
            full_response = []
            started = time.perf_counter()
            stats: Dict = {}

            # Send session_id as the first event
            yield f"data: {json.dumps({'type': 'session', 'session_id': session_id})}\n\n"

            try:
                for text_chunk in stream_bedrock(conversation, request.message, stats):
                    full_response.append(text_chunk)
                    yield f"data: {json.dumps({'type': 'chunk', 'content': text_chunk})}\n\n"

                # Save conversation after streaming completes
                assistant_response = "".join(full_response)
                conversation.append(
                    {"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()}
                )
                conversation.append(
                    {"role": "assistant", "content": assistant_response, "timestamp": datetime.now().isoformat()}
                )
                save_conversation(session_id, conversation)
                log_event(
                    "chat",
                    session_id=session_id,
                    client=client,
                    stream=True,
                    message_chars=len(request.message),
                    response_chars=len(assistant_response),
                    latency_ms=round((time.perf_counter() - started) * 1000),
                    model=BEDROCK_MODEL_ID,
                    usage=stats.get("usage"),
                )

                yield f"data: {json.dumps({'type': 'done'})}\n\n"

            except ClientError as e:
                error_code = e.response['Error']['Code']
                print(f"Bedrock streaming error: {e}")
                yield f"data: {json.dumps({'type': 'error', 'message': f'Bedrock error: {error_code}'})}\n\n"
            except Exception as e:  # noqa: BLE001 - never leave the stream hanging
                print(f"Streaming error: {e}")
                yield f"data: {json.dumps({'type': 'error', 'message': 'Something went wrong. Please try again.'})}\n\n"

        return StreamingResponse(event_stream(), media_type="text/event-stream")

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in chat stream endpoint: {str(e)}")
        raise api_error(500, "server_error", "Something went wrong. Please try again.")


@app.post("/feedback", status_code=201)
async def feedback(request: FeedbackRequest, client: str = Depends(enforce_rate_limit)):
    """Thumbs up/down on an answer. Stored as JSON next to the conversation memory."""
    try:
        record = {
            **request.model_dump(),
            "client": client,
            "received_at": datetime.now(timezone.utc).isoformat(),
        }
        key = store_record("feedback", record)
        log_event("feedback", session_id=request.session_id, rating=request.rating, client=client, key=key)
        return {"status": "ok"}
    except HTTPException:
        raise
    except Exception as e:
        print(f"Error in feedback endpoint: {str(e)}")
        raise api_error(500, "server_error", "Could not save feedback.")


@app.get("/conversation/{session_id}")
async def get_conversation(session_id: str):
    """Retrieve conversation history (not exposed through API Gateway)."""
    try:
        conversation = load_conversation(session_id)
        return {"session_id": session_id, "messages": conversation}
    except Exception as e:
        raise api_error(500, "server_error", str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
