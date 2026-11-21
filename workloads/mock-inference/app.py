"""
OpenAI-compatible mock inference server.

Why this exists: it lets the platform layers be built and measured before any
GPU is available. It emits the same metric names vLLM does
(vllm:prompt_tokens_total, vllm:generation_tokens_total, vllm:time_to_first_token_seconds)
so swapping in real vLLM is a base-URL change, not a rewrite.

Token counts are a documented approximation (len // 4). That is stated in the
README rather than hidden.
"""
import asyncio
import os
import time
import uuid

from fastapi import FastAPI
from fastapi.responses import StreamingResponse
from prometheus_client import Counter, Histogram, make_asgi_app
from pydantic import BaseModel

app = FastAPI(title="mock-inference")
app.mount("/metrics", make_asgi_app())

TEAM = os.getenv("TEAM", "team-a")
MODEL = os.getenv("MODEL", "mock-0.5b")

PROMPT_TOKENS = Counter("vllm:prompt_tokens_total", "Prompt tokens processed", ["team", "model"])
GEN_TOKENS = Counter("vllm:generation_tokens_total", "Completion tokens generated", ["team", "model"])
TTFT = Histogram("vllm:time_to_first_token_seconds", "Time to first token", ["team", "model"])


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    model: str = MODEL
    messages: list[Message]
    stream: bool = True


def approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)


@app.post("/v1/chat/completions")
async def chat(req: ChatRequest):
    prompt = " ".join(m.content for m in req.messages)
    PROMPT_TOKENS.labels(TEAM, MODEL).inc(approx_tokens(prompt))
    completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"

    async def stream():
        words = (
            "This is a simulated streaming completion served by the platform, "
            "so that scheduling, quota and cost attribution can be exercised "
            "end to end without a GPU."
        ).split()
        started = time.perf_counter()
        first = True
        for word in words:
            if first:
                TTFT.labels(TEAM, MODEL).observe(time.perf_counter() - started)
                first = False
            GEN_TOKENS.labels(TEAM, MODEL).inc(1)
            chunk = (
                '{"id":"%s","object":"chat.completion.chunk",'
                '"choices":[{"delta":{"content":"%s "}}]}' % (completion_id, word)
            )
            yield f"data: {chunk}\n\n"
            await asyncio.sleep(0.04)
        yield "data: [DONE]\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": MODEL, "object": "model", "owned_by": "platform"}]}


@app.get("/healthz")
def healthz():
    return {"ok": True, "team": TEAM, "model": MODEL}
