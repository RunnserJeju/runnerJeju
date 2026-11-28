"""변경 확인 응답(ETag) — 앱이 가진 본문과 같으면 본문 없이 304만 보낸다.

본문 해시로 판단하므로 항상 정확하다. 서버 조회는 그대로 하고, 전송과 앱의 파싱만 줄인다.
"""

import hashlib

CACHE_HEADERS = [(b"cache-control", b"private, no-cache"), (b"vary", b"Authorization")]


def _matches(header: bytes, etag: bytes) -> bool:
    return any(part.strip().removeprefix(b"W/") == etag for part in header.split(b","))


class ETagMiddleware:
    """paths의 GET 200 응답에만 붙는다. 응답을 다 모은 뒤 해시를 낸다(스트리밍 응답엔 쓰지 않는다)."""

    def __init__(self, app, paths: frozenset[str]):
        self.app = app
        self.paths = paths

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] != "GET" or scope["path"] not in self.paths:
            await self.app(scope, receive, send)
            return

        start = None
        chunks: list[bytes] = []

        async def buffered(message):
            nonlocal start
            if message["type"] == "http.response.start":
                start = message
                return
            if message["type"] != "http.response.body":
                await send(message)
                return
            chunks.append(message.get("body", b""))
            if message.get("more_body"):
                return
            await self._finish(scope, start, b"".join(chunks), send)

        await self.app(scope, receive, buffered)

    async def _finish(self, scope, start, body: bytes, send):
        if start["status"] != 200:
            await send(start)
            await send({"type": "http.response.body", "body": body})
            return

        etag = b'"' + hashlib.sha1(body).hexdigest().encode() + b'"'
        asked = dict(scope["headers"]).get(b"if-none-match")
        extra = [(b"etag", etag), *CACHE_HEADERS]

        if asked is not None and _matches(asked, etag):
            await send({"type": "http.response.start", "status": 304, "headers": extra})
            await send({"type": "http.response.body", "body": b""})
            return

        await send({**start, "headers": [*start["headers"], *extra]})
        await send({"type": "http.response.body", "body": body})
