"""앱 크래시 덤프 해석. 원본은 Storage에 두고, 목록에서 읽을 요약만 여기서 뽑는다.

- android_native: tombstone protobuf(ApplicationExitInfo.getTraceInputStream, Android 12+).
  필드 번호는 AOSP system/core/debuggerd/proto/tombstone.proto를 따른다. 필요한 몇 개만
  읽으려고 protobuf 패키지 대신 와이어 포맷을 직접 푼다.
- android_anr: 전체 스레드 덤프 텍스트. "main" 스레드 블록만 뽑는다.
- ios_crash / ios_hang: MetricKit 진단 JSON(jsonRepresentation). 원인 스레드의 호출 스택.

해석 실패는 업로드를 막지 않는다 — 원본이 남아 있으니 나중에 다시 풀면 된다.
"""

import json
from dataclasses import dataclass

STACK_MAX_CHARS = 64 * 1024
SUMMARY_MAX_CHARS = 500
CULPRIT_MAX_CHARS = 200

# 죽은 자리로 치기엔 너무 흔한 시스템 라이브러리. 그 바깥의 첫 프레임을 원인으로 본다.
_ANDROID_SYSTEM_LIBS = ("libc.so", "libm.so", "linker64", "libbase.so", "libutils.so")
_IOS_SYSTEM_PREFIXES = ("libsystem_", "libdyld", "libc++")


@dataclass
class Digest:
    summary: str | None = None
    culprit: str | None = None
    stack: str | None = None


def digest(kind: str, dump: bytes) -> Digest:
    try:
        if kind == "android_native":
            return _tombstone(dump)
        if kind == "android_anr":
            return _anr(dump.decode("utf-8", "replace"))
        if kind in ("ios_crash", "ios_hang"):
            return _metrickit(json.loads(dump))
    except Exception:
        pass
    return Digest()


# --- protobuf 와이어 포맷 -----------------------------------------------------


def _varint(buf: bytes, pos: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, pos
        shift += 7


def _fields(buf: bytes):
    """(필드 번호, 값). 값은 varint면 int, 길이 구분이면 bytes. 고정 길이는 건너뛴다."""
    pos = 0
    while pos < len(buf):
        key, pos = _varint(buf, pos)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, pos = _varint(buf, pos)
            yield number, value
        elif wire == 2:
            length, pos = _varint(buf, pos)
            yield number, buf[pos : pos + length]
            pos += length
        elif wire == 1:
            pos += 8
        elif wire == 5:
            pos += 4
        else:
            raise ValueError(f"wire type {wire}")


def _text(value: bytes) -> str:
    return value.decode("utf-8", "replace")


# --- Android -----------------------------------------------------------------


def _tombstone(buf: bytes) -> Digest:
    tid = None
    signal = code = abort = None
    has_fault = False
    fault = 0
    threads: dict[int, bytes] = {}
    causes: list[str] = []

    for number, value in _fields(buf):
        if number == 6:  # tid
            tid = value
        elif number == 10:  # signal_info
            for n, v in _fields(value):
                if n == 2:
                    signal = _text(v)
                elif n == 4:
                    code = _text(v)
                elif n == 8:
                    has_fault = bool(v)
                elif n == 9:
                    fault = v
        elif number == 14:  # abort_message
            abort = _text(value)
        elif number == 15:  # causes
            for n, v in _fields(value):
                if n == 1:
                    causes.append(_text(v))
        elif number == 16:  # threads: map<uint32, Thread>
            key = thread = None
            for n, v in _fields(value):
                if n == 1:
                    key = v
                elif n == 2:
                    thread = v
            if key is not None and thread is not None:
                threads[key] = thread

    frames = _frames(threads.get(tid, b""))
    summary = " ".join(
        part
        for part in (
            signal,
            f"({code})" if code else None,
            f"fault addr 0x{fault:x}" if has_fault else None,
            f"— {abort}" if abort else (f"— {causes[0]}" if causes else None),
        )
        if part
    )
    culprit = next(
        (f for f, _ in frames if not f.endswith(_ANDROID_SYSTEM_LIBS)),
        frames[0][0] if frames else None,
    )
    stack = "\n".join(line for _, line in frames)
    return Digest(summary or None, culprit, stack or None)


def _frames(thread: bytes) -> list[tuple[str, str]]:
    """(라이브러리 파일명, 한 줄) 목록. 원인 스레드의 current_backtrace."""
    out = []
    for number, value in _fields(thread):
        if number != 4:  # current_backtrace
            continue
        rel_pc = offset = 0
        function = file_name = ""
        for n, v in _fields(value):
            if n == 1:
                rel_pc = v
            elif n == 4:
                function = _text(v)
            elif n == 5:
                offset = v
            elif n == 6:
                file_name = _text(v)
        lib = file_name.rsplit("/", 1)[-1]
        symbol = f" ({function}+{offset})" if function else ""
        out.append((lib, f"#{len(out):02d} pc {rel_pc:016x}  {file_name}{symbol}"))
    return out


def _anr(text: str) -> Digest:
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith('"main"')), None)
    if start is None:
        return Digest(stack=text[:STACK_MAX_CHARS])
    end = next((i for i in range(start + 1, len(lines)) if not lines[i].strip()), len(lines))
    block = lines[start:end]
    frame = next((line.strip() for line in block if line.strip().startswith(("at ", "native:"))), None)
    return Digest(culprit=frame, stack="\n".join(block))


# --- iOS ---------------------------------------------------------------------


def _metrickit(diagnostic: dict) -> Digest:
    meta = diagnostic.get("diagnosticMetaData") or {}
    tree = diagnostic.get("callStackTree") or {}
    stacks = tree.get("callStacks") or []
    stack = next((s for s in stacks if s.get("threadAttributed")), stacks[0] if stacks else None)

    frames: list[dict] = []
    roots = (stack or {}).get("callStackRootFrames") or []
    # 루트에서 subFrames를 따라 내려간다. 첫 줄이 죽은 자리다.
    frame = roots[0] if roots else None
    while frame is not None and len(frames) < 200:
        frames.append(frame)
        subs = frame.get("subFrames") or []
        frame = subs[0] if subs else None

    lines = [
        f"#{i:02d} {f.get('binaryName', '?')} +{f.get('offsetIntoBinaryTextSegment', '?')}"
        f" (0x{f.get('address', 0):x})"
        for i, f in enumerate(frames)
    ]
    culprit = next(
        (f.get("binaryName") for f in frames if not str(f.get("binaryName", "")).startswith(_IOS_SYSTEM_PREFIXES)),
        frames[0].get("binaryName") if frames else None,
    )
    parts = [
        f"{key}={meta[key]}"
        for key in ("exceptionType", "exceptionCode", "signal", "terminationReason", "hangDuration")
        if meta.get(key) not in (None, "")
    ]
    return Digest(" ".join(parts) or None, culprit, "\n".join(lines) or None)


def clip(value: str | None, limit: int) -> str | None:
    return None if value is None else value[:limit]
