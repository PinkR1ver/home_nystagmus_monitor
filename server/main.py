from __future__ import annotations

import http.client
import json
from contextlib import contextmanager
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import html
import math
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import traceback
import types
import zipfile
from statistics import median
from pathlib import Path
from threading import Lock
from typing import Any
from urllib.parse import quote, urlencode, urlparse

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
LEGACY_VOG_PROJECT_DIR = Path("/home/kk/Documents/proj/SwinUNet-VOG")
DISCOVERED_VOG_PROJECT_DIRS = [
    BASE_DIR.parent / "SwinUNet-VOG",
    BASE_DIR.parent / "SwinUNet-VOG-1",
]


def _resolve_runtime_path(env_name: str, default: Path) -> Path:
    raw = os.getenv(env_name, "").strip()
    path = Path(raw).expanduser() if raw else default
    if not path.is_absolute():
        path = BASE_DIR / path
    return path.resolve()


def _split_path_env(env_name: str) -> list[Path]:
    raw = os.getenv(env_name, "").strip()
    if not raw:
        return []
    out: list[Path] = []
    for chunk in raw.split(os.pathsep):
        value = chunk.strip()
        if not value:
            continue
        item = Path(value).expanduser()
        if not item.is_absolute():
            item = BASE_DIR / item
        out.append(item.resolve())
    return out


def _unique_paths(paths: list[Path]) -> list[Path]:
    seen: set[str] = set()
    out: list[Path] = []
    for path in paths:
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        out.append(path)
    return out


DATA_DIR = _resolve_runtime_path("HNM_DATA_DIR", BASE_DIR / "data")
DATA_FILE = DATA_DIR / "records.jsonl"
DB_FILE = DATA_DIR / "records.db"
UPLOAD_DIR = DATA_DIR / "uploads"
MODEL_DIR = _resolve_runtime_path("HNM_MODEL_DIR", BASE_DIR / "models")
WEB_DIR = _resolve_runtime_path("HNM_WEB_DIR", BASE_DIR / "web")
WEB_TEMPLATE_DIR = WEB_DIR / "templates"
REPORT_DIR = DATA_DIR / "reports"
EYE_VIDEO_DIR = DATA_DIR / "eye_videos"
EYE_CLIP_DIR = DATA_DIR / "eye_clips"
PACKAGE_DIR = DATA_DIR / "packages"
ARCHIVE_DIR = DATA_DIR / "archive"
ARCHIVE_RECORD_DIR = ARCHIVE_DIR / "records"
VOG_PROJECT_DIR = _resolve_runtime_path("HNM_VOG_DIR", BASE_DIR / "vendor" / "SwinUNet-VOG")
INPUT_MODE_SINGLE_EYE = "single_eye"
INPUT_MODE_FULL_FACE = "full_face"
DEFAULT_INPUT_MODE = INPUT_MODE_SINGLE_EYE


class RecordPayload(BaseModel):
    id: str
    accountId: str
    accountName: str
    patientId: str = ""
    startedAt: str
    durationSec: int
    analysisCompleted: bool = False
    suspectNystagmus: bool
    summary: str
    horizontalDirectionLabel: str
    verticalDirectionLabel: str
    dominantFrequencyHz: float
    spvDegPerSec: float
    uploaded: bool = False
    pitchSeries: list[float] = Field(default_factory=list)
    yawSeries: list[float] = Field(default_factory=list)
    timestampsMs: list[int] = Field(default_factory=list)


class UploadRequest(BaseModel):
    accountId: str
    records: list[RecordPayload]


class PackagePushRequest(BaseModel):
    targetUrl: str
    method: str = "POST"
    mode: str = "multipart"
    fileFieldName: str = "file"
    fileName: str | None = None
    metadataFieldName: str = "metadata"
    includeRecordMetadata: bool = True
    formFields: dict[str, str] = Field(default_factory=dict)
    headers: dict[str, str] = Field(default_factory=dict)
    timeoutSec: int = Field(default=30, ge=3, le=300)
    dryRun: bool = False


@dataclass
class StoredRecord:
    id: str
    accountId: str
    accountName: str
    patientId: str
    startedAt: str
    durationSec: int
    analysisCompleted: bool
    suspectNystagmus: bool
    summary: str
    horizontalDirectionLabel: str
    verticalDirectionLabel: str
    dominantFrequencyHz: float
    spvDegPerSec: float
    uploaded: bool
    videoFile: str | None
    reportFile: str | None
    eyeVideoFile: str | None
    eyeClipFile: str | None
    packageFile: str | None
    sourceVideoName: str | None
    inputMode: str
    pitchSeries: list[float]
    yawSeries: list[float]
    timestampsMs: list[int]
    receivedAt: str
    archived: bool = False
    archivedAt: str | None = None


class RecordStore:
    def __init__(self, db_path: Path):
        self.db_path = db_path
        self.lock = Lock()
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
        MODEL_DIR.mkdir(parents=True, exist_ok=True)
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        EYE_VIDEO_DIR.mkdir(parents=True, exist_ok=True)
        EYE_CLIP_DIR.mkdir(parents=True, exist_ok=True)
        PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
        ARCHIVE_RECORD_DIR.mkdir(parents=True, exist_ok=True)
        self._init_schema()
        self._migrate_from_jsonl_if_needed()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS records (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    account_name TEXT NOT NULL,
                    patient_id TEXT NOT NULL DEFAULT '',
                    started_at TEXT NOT NULL,
                    duration_sec INTEGER NOT NULL,
                    analysis_completed INTEGER NOT NULL,
                    suspect_nystagmus INTEGER NOT NULL,
                    summary TEXT NOT NULL,
                    horizontal_direction_label TEXT NOT NULL,
                    vertical_direction_label TEXT NOT NULL,
                    dominant_frequency_hz REAL NOT NULL,
                    spv_deg_per_sec REAL NOT NULL,
                    uploaded INTEGER NOT NULL,
                    video_file TEXT,
                    report_file TEXT,
                    eye_video_file TEXT,
                    eye_clip_file TEXT,
                    package_file TEXT,
                    source_video_name TEXT,
                    input_mode TEXT NOT NULL DEFAULT 'single_eye',
                    pitch_series_json TEXT NOT NULL,
                    yaw_series_json TEXT NOT NULL,
                    timestamps_ms_json TEXT NOT NULL,
                    received_at TEXT NOT NULL
                )
                """
            )
            self._ensure_column(conn, "records", "patient_id", "TEXT NOT NULL DEFAULT ''")
            self._ensure_column(conn, "records", "report_file", "TEXT")
            self._ensure_column(conn, "records", "eye_video_file", "TEXT")
            self._ensure_column(conn, "records", "eye_clip_file", "TEXT")
            self._ensure_column(conn, "records", "package_file", "TEXT")
            self._ensure_column(conn, "records", "source_video_name", "TEXT")
            self._ensure_column(conn, "records", "input_mode", f"TEXT NOT NULL DEFAULT '{DEFAULT_INPUT_MODE}'")
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_records_account_received "
                "ON records(account_id, received_at DESC)"
            )
            conn.execute(
                "CREATE INDEX IF NOT EXISTS idx_records_received "
                "ON records(received_at DESC)"
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS archived_records (
                    id TEXT PRIMARY KEY,
                    archived_at TEXT NOT NULL
                )
                """
            )
            conn.commit()

    def _ensure_column(self, conn: sqlite3.Connection, table: str, column: str, ddl: str) -> None:
        rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
        existing = {str(row["name"]) for row in rows}
        if column not in existing:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")

    def _migrate_from_jsonl_if_needed(self) -> None:
        if not DATA_FILE.exists():
            return
        if self.count_records() > 0:
            return
        try:
            with DATA_FILE.open("r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    raw = json.loads(line)
                    item = StoredRecord(
                        id=str(raw.get("id", "")),
                        accountId=str(raw.get("accountId", "")),
                        accountName=str(raw.get("accountName", "")),
                        patientId=str(raw.get("patientId", "")),
                        startedAt=str(raw.get("startedAt", "")),
                        durationSec=int(raw.get("durationSec", 0)),
                        analysisCompleted=bool(raw.get("analysisCompleted", False)),
                        suspectNystagmus=bool(raw.get("suspectNystagmus", False)),
                        summary=str(raw.get("summary", "")),
                        horizontalDirectionLabel=str(raw.get("horizontalDirectionLabel", "")),
                        verticalDirectionLabel=str(raw.get("verticalDirectionLabel", "")),
                        dominantFrequencyHz=float(raw.get("dominantFrequencyHz", 0.0)),
                        spvDegPerSec=float(raw.get("spvDegPerSec", 0.0)),
                        uploaded=bool(raw.get("uploaded", False)),
                        videoFile=raw.get("videoFile") or raw.get("videoPath"),
                        reportFile=raw.get("reportFile"),
                        eyeVideoFile=raw.get("eyeVideoFile"),
                        eyeClipFile=raw.get("eyeClipFile"),
                        packageFile=raw.get("packageFile"),
                        sourceVideoName=raw.get("sourceVideoName"),
                        inputMode=_normalize_input_mode(raw.get("inputMode")),
                        pitchSeries=raw.get("pitchSeries", []) or [],
                        yawSeries=raw.get("yawSeries", []) or [],
                        timestampsMs=raw.get("timestampsMs", []) or [],
                        receivedAt=str(raw.get("receivedAt", datetime.now(timezone.utc).isoformat())),
                    )
                    if item.id and item.accountId:
                        self._upsert_record(item)
        except Exception:
            # 保持服务可用，迁移失败不影响启动
            pass

    def _upsert_record(self, item: StoredRecord) -> None:
        with self._connect() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO records (
                    id, account_id, account_name, started_at, duration_sec,
                    analysis_completed, suspect_nystagmus, summary,
                    horizontal_direction_label, vertical_direction_label,
                    dominant_frequency_hz, spv_deg_per_sec, uploaded, video_file,
                    patient_id, report_file, eye_video_file, eye_clip_file, package_file,
                    source_video_name, input_mode,
                    pitch_series_json, yaw_series_json, timestamps_ms_json, received_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    item.id,
                    item.accountId,
                    item.accountName,
                    item.startedAt,
                    item.durationSec,
                    1 if item.analysisCompleted else 0,
                    1 if item.suspectNystagmus else 0,
                    item.summary,
                    item.horizontalDirectionLabel,
                    item.verticalDirectionLabel,
                    item.dominantFrequencyHz,
                    item.spvDegPerSec,
                    1 if item.uploaded else 0,
                    item.videoFile,
                    item.patientId,
                    item.reportFile,
                    item.eyeVideoFile,
                    item.eyeClipFile,
                    item.packageFile,
                    item.sourceVideoName,
                    _normalize_input_mode(item.inputMode),
                    json.dumps(item.pitchSeries, ensure_ascii=False),
                    json.dumps(item.yawSeries, ensure_ascii=False),
                    json.dumps(item.timestampsMs, ensure_ascii=False),
                    item.receivedAt,
                ),
            )
            # 若同 id 被重新写入，解除归档标记
            conn.execute("DELETE FROM archived_records WHERE id = ?", (item.id,))
            conn.commit()

    def _row_to_record(self, row: sqlite3.Row) -> StoredRecord:
        keys = set(row.keys())
        return StoredRecord(
            id=str(row["id"]),
            accountId=str(row["account_id"]),
            accountName=str(row["account_name"]),
            patientId=str(row["patient_id"]) if "patient_id" in keys else "",
            startedAt=str(row["started_at"]),
            durationSec=int(row["duration_sec"]),
            analysisCompleted=bool(row["analysis_completed"]),
            suspectNystagmus=bool(row["suspect_nystagmus"]),
            summary=str(row["summary"]),
            horizontalDirectionLabel=str(row["horizontal_direction_label"]),
            verticalDirectionLabel=str(row["vertical_direction_label"]),
            dominantFrequencyHz=float(row["dominant_frequency_hz"]),
            spvDegPerSec=float(row["spv_deg_per_sec"]),
            uploaded=bool(row["uploaded"]),
            videoFile=row["video_file"],
            reportFile=row["report_file"] if "report_file" in keys else None,
            eyeVideoFile=row["eye_video_file"] if "eye_video_file" in keys else None,
            eyeClipFile=row["eye_clip_file"] if "eye_clip_file" in keys else None,
            packageFile=row["package_file"] if "package_file" in keys else None,
            sourceVideoName=row["source_video_name"] if "source_video_name" in keys else None,
            inputMode=_normalize_input_mode(row["input_mode"]) if "input_mode" in keys else DEFAULT_INPUT_MODE,
            pitchSeries=json.loads(row["pitch_series_json"] or "[]"),
            yawSeries=json.loads(row["yaw_series_json"] or "[]"),
            timestampsMs=json.loads(row["timestamps_ms_json"] or "[]"),
            receivedAt=str(row["received_at"]),
            archived=bool(row["archived"]) if "archived" in keys else False,
            archivedAt=str(row["archived_at"]) if "archived_at" in keys and row["archived_at"] else None,
        )

    def upsert_many(self, records: list[RecordPayload]) -> tuple[list[str], list[dict[str, Any]]]:
        uploaded_ids: list[str] = []
        analyzed_rows: list[dict[str, Any]] = []
        if not records:
            return uploaded_ids, analyzed_rows
        now = datetime.now(timezone.utc).isoformat()
        for rec in records:
            if not rec.id.strip():
                continue
            analysis = analyze_record(rec.pitchSeries, rec.yawSeries, rec.timestampsMs)
            existing = self.get_record(rec.id)
            stored = StoredRecord(
                id=rec.id,
                accountId=rec.accountId,
                accountName=rec.accountName,
                patientId=getattr(rec, "patientId", "") or str((existing or {}).get("patientId", "")),
                startedAt=rec.startedAt,
                durationSec=rec.durationSec,
                analysisCompleted=True,
                suspectNystagmus=analysis["suspectNystagmus"],
                summary=analysis["summary"],
                horizontalDirectionLabel=analysis["horizontalDirectionLabel"],
                verticalDirectionLabel=analysis["verticalDirectionLabel"],
                dominantFrequencyHz=analysis["dominantFrequencyHz"],
                spvDegPerSec=analysis["spvDegPerSec"],
                uploaded=True,
                videoFile=(existing or {}).get("videoFile"),
                reportFile=(existing or {}).get("reportFile"),
                eyeVideoFile=(existing or {}).get("eyeVideoFile"),
                eyeClipFile=(existing or {}).get("eyeClipFile"),
                packageFile=(existing or {}).get("packageFile"),
                sourceVideoName=(existing or {}).get("sourceVideoName"),
                inputMode=str((existing or {}).get("inputMode") or DEFAULT_INPUT_MODE),
                pitchSeries=rec.pitchSeries,
                yawSeries=rec.yawSeries,
                timestampsMs=rec.timestampsMs,
                receivedAt=now,
            )
            self._upsert_record(stored)
            uploaded_ids.append(stored.id)
            analyzed_rows.append(
                {
                    "id": stored.id,
                    "analysisCompleted": True,
                    "suspectNystagmus": stored.suspectNystagmus,
                    "summary": stored.summary,
                    "horizontalDirectionLabel": stored.horizontalDirectionLabel,
                    "verticalDirectionLabel": stored.verticalDirectionLabel,
                    "dominantFrequencyHz": stored.dominantFrequencyHz,
                    "spvDegPerSec": stored.spvDegPerSec,
                }
            )
        return uploaded_ids, analyzed_rows

    def list_records(
        self,
        account_id: str | None = None,
        limit: int = 100,
        include_archived: bool = False
    ) -> list[dict[str, Any]]:
        with self._connect() as conn:
            if account_id:
                if include_archived:
                    cur = conn.execute(
                        """
                        SELECT r.*, (a.id IS NOT NULL) AS archived, a.archived_at
                        FROM records r
                        LEFT JOIN archived_records a ON a.id = r.id
                        WHERE account_id = ?
                        ORDER BY r.received_at DESC
                        LIMIT ?
                        """,
                        (account_id, limit),
                    )
                else:
                    cur = conn.execute(
                        """
                        SELECT r.* FROM records r
                        LEFT JOIN archived_records a ON a.id = r.id
                        WHERE r.account_id = ? AND a.id IS NULL
                        ORDER BY r.received_at DESC
                        LIMIT ?
                        """,
                        (account_id, limit),
                    )
            else:
                if include_archived:
                    cur = conn.execute(
                        """
                        SELECT r.*, (a.id IS NOT NULL) AS archived, a.archived_at
                        FROM records r
                        LEFT JOIN archived_records a ON a.id = r.id
                        ORDER BY r.received_at DESC
                        LIMIT ?
                        """,
                        (limit,),
                    )
                else:
                    cur = conn.execute(
                        """
                        SELECT r.* FROM records r
                        LEFT JOIN archived_records a ON a.id = r.id
                        WHERE a.id IS NULL
                        ORDER BY r.received_at DESC
                        LIMIT ?
                        """,
                        (limit,),
                    )
            rows = cur.fetchall()
        return [asdict(self._row_to_record(row)) for row in rows]

    def upsert_one(self, item: StoredRecord) -> None:
        with self.lock:
            self._upsert_record(item)

    def count_records(self) -> int:
        with self._connect() as conn:
            cur = conn.execute(
                """
                SELECT COUNT(1) AS cnt
                FROM records r
                LEFT JOIN archived_records a ON a.id = r.id
                WHERE a.id IS NULL
                """
            )
            row = cur.fetchone()
            return int(row["cnt"]) if row is not None else 0

    def count_by_account(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            cur = conn.execute(
                """
                SELECT r.account_id, COUNT(1) AS cnt
                FROM records r
                LEFT JOIN archived_records a ON a.id = r.id
                WHERE a.id IS NULL
                GROUP BY r.account_id
                ORDER BY cnt DESC
                """
            )
            rows = cur.fetchall()
        return [{"accountId": str(r["account_id"]), "count": int(r["cnt"])} for r in rows]

    def get_record(self, record_id: str) -> dict[str, Any] | None:
        with self._connect() as conn:
            cur = conn.execute("SELECT * FROM records WHERE id = ?", (record_id,))
            row = cur.fetchone()
        if row is None:
            return None
        return asdict(self._row_to_record(row))

    def _record_archive_dir(self, record_id: str) -> Path:
        return ARCHIVE_RECORD_DIR / _safe_slug(record_id, default="record")

    def _archive_path_for_field(self, record_id: str, field_name: str, source_path: Path) -> Path:
        subdir_map = {
            "videoFile": "uploads",
            "reportFile": "reports",
            "eyeVideoFile": "eye_videos",
            "eyeClipFile": "eye_clips",
            "packageFile": "packages",
        }
        subdir = subdir_map.get(field_name, "misc")
        return self._record_archive_dir(record_id) / subdir / source_path.name

    def _archive_file_path(self, record_id: str, field_name: str, raw_path: str | None) -> str | None:
        if not raw_path:
            return None
        src = Path(raw_path)
        if not src.exists() or not src.is_file():
            return None
        if ARCHIVE_RECORD_DIR in src.parents:
            return str(src)
        dst = self._archive_path_for_field(record_id, field_name, src)
        dst.parent.mkdir(parents=True, exist_ok=True)
        os.replace(src, dst)
        return str(dst)

    def archive_record(self, record_id: str) -> bool:
        with self.lock:
            with self._connect() as conn:
                cur0 = conn.execute("SELECT * FROM records WHERE id = ?", (record_id,))
                row = cur0.fetchone()
                if row is None:
                    return False
                stored = self._row_to_record(row)
                stored.videoFile = self._archive_file_path(stored.id, "videoFile", stored.videoFile)
                stored.reportFile = self._archive_file_path(stored.id, "reportFile", stored.reportFile)
                stored.eyeVideoFile = self._archive_file_path(stored.id, "eyeVideoFile", stored.eyeVideoFile)
                stored.eyeClipFile = self._archive_file_path(stored.id, "eyeClipFile", stored.eyeClipFile)
                stored.packageFile = self._archive_file_path(stored.id, "packageFile", stored.packageFile)
                conn.execute(
                    """
                    UPDATE records
                    SET video_file = ?, report_file = ?, eye_video_file = ?, eye_clip_file = ?, package_file = ?,
                        source_video_name = ?, input_mode = ?
                    WHERE id = ?
                    """,
                    (
                        stored.videoFile,
                        stored.reportFile,
                        stored.eyeVideoFile,
                        stored.eyeClipFile,
                        stored.packageFile,
                        stored.sourceVideoName,
                        _normalize_input_mode(stored.inputMode),
                        stored.id,
                    ),
                )
                conn.execute(
                    "INSERT OR REPLACE INTO archived_records(id, archived_at) VALUES(?, ?)",
                    (record_id, datetime.now(timezone.utc).isoformat())
                )
                conn.commit()
        return True


store = RecordStore(DB_FILE)
app = FastAPI(title="Home Nystagmus Monitor Server", version="1.0.0")
app.mount("/dashboard-assets", StaticFiles(directory=str(WEB_DIR / "assets")), name="dashboard-assets")

_VOG_RUNTIME: dict[str, Any] | None = None
_VOG_INIT_ERROR: str | None = None


def _load_template(name: str) -> str:
    return (WEB_TEMPLATE_DIR / name).read_text(encoding="utf-8")


def _render_template(name: str, values: dict[str, str]) -> str:
    text = _load_template(name)
    for key, value in values.items():
        text = text.replace(f"__{key}__", value)
    return text


def _install_streamlit_stub_if_needed() -> None:
    """
    服务端不需要 Streamlit UI。
    vertiwisdom.py 在模块顶层 import streamlit，这里注入一个最小 stub，避免 UI 运行时警告。
    """
    if os.getenv("HNM_USE_REAL_STREAMLIT", "").lower() in {"1", "true", "yes"}:
        return
    if "streamlit" in sys.modules:
        return

    st = types.ModuleType("streamlit")
    st.session_state = {}

    def _noop(*args, **kwargs):
        return None

    def _cache_resource(func=None, **kwargs):
        if func is None:
            def _decorator(f):
                return f
            return _decorator
        return func

    class _DummyContext:
        def __enter__(self):
            return None

        def __exit__(self, exc_type, exc, tb):
            return False

    st.cache_resource = _cache_resource
    st.spinner = lambda *args, **kwargs: _DummyContext()
    st.columns = lambda *args, **kwargs: (None, None)
    st.container = lambda *args, **kwargs: None
    st.empty = lambda *args, **kwargs: None
    st.set_page_config = _noop
    st.markdown = _noop
    st.error = _noop
    st.button = lambda *args, **kwargs: False
    st.file_uploader = lambda *args, **kwargs: None
    st.image = _noop
    sys.modules["streamlit"] = st


def _finite_pairs(values: list[float], timestamps_ms: list[int]) -> tuple[list[float], list[int]]:
    if not values:
        return [], []
    if len(timestamps_ms) != len(values):
        timestamps_ms = list(range(len(values)))
    out_v: list[float] = []
    out_t: list[int] = []
    for v, t in zip(values, timestamps_ms):
        if isinstance(v, (int, float)) and math.isfinite(v):
            out_v.append(float(v))
            out_t.append(int(t))
    return out_v, out_t


def _axis_metrics(values: list[float], timestamps_ms: list[int], positive_label: str, negative_label: str) -> dict[str, Any]:
    clean_v, clean_t = _finite_pairs(values, timestamps_ms)
    if len(clean_v) < 6:
        return {"freq": 0.0, "spv": 0.0, "amp": 0.0, "direction": "-"}

    dts = []
    for i in range(1, len(clean_t)):
        dt = max(1, clean_t[i] - clean_t[i - 1]) / 1000.0
        dts.append(dt)
    dt_sec = median(dts) if dts else 1.0 / 30.0
    duration_sec = max(1e-3, (clean_t[-1] - clean_t[0]) / 1000.0)

    vels = []
    for i in range(1, len(clean_v)):
        vels.append((clean_v[i] - clean_v[i - 1]) / dt_sec)
    if not vels:
        return {"freq": 0.0, "spv": 0.0, "amp": 0.0, "direction": "-"}

    amp = max(clean_v) - min(clean_v)
    spv = sum(abs(v) for v in vels) / len(vels)
    turn_count = 0
    for i in range(1, len(vels)):
        if vels[i - 1] == 0:
            continue
        if (vels[i - 1] > 0 and vels[i] < 0) or (vels[i - 1] < 0 and vels[i] > 0):
            turn_count += 1
    freq = (turn_count / 2.0) / duration_sec

    velocity_gate = max(5.0, spv * 0.6)
    pos = sum(1 for v in vels if v > velocity_gate)
    neg = sum(1 for v in vels if v < -velocity_gate)
    if pos == 0 and neg == 0:
        direction = "-"
    else:
        direction = positive_label if pos >= neg else negative_label
    return {"freq": freq, "spv": spv, "amp": amp, "direction": direction}


def analyze_record(pitch: list[float], yaw: list[float], timestamps_ms: list[int]) -> dict[str, Any]:
    h = _axis_metrics(yaw, timestamps_ms, positive_label="右", negative_label="左")
    v = _axis_metrics(pitch, timestamps_ms, positive_label="上", negative_label="下")
    dominant_freq = max(h["freq"], v["freq"])
    max_spv = max(h["spv"], v["spv"])
    has_nystagmus = (
        dominant_freq >= 0.3
        and dominant_freq <= 8.0
        and max_spv >= 6.0
        and max(h["amp"], v["amp"]) >= 1.5
    )
    summary = "疑似眼震（服务端分析）" if has_nystagmus else "未见明显眼震（服务端分析）"
    return {
        "analysisCompleted": True,
        "suspectNystagmus": has_nystagmus,
        "summary": summary,
        "horizontalDirectionLabel": h["direction"],
        "verticalDirectionLabel": v["direction"],
        "dominantFrequencyHz": round(dominant_freq, 4),
        "spvDegPerSec": round(max_spv, 4),
    }


def _first_existing(paths: list[Path]) -> Path | None:
    for p in paths:
        if p.exists():
            return p
    return None


def _candidate_vog_module_dirs() -> list[Path]:
    candidates = [BASE_DIR]
    candidates.extend(_split_path_env("HNM_VOG_MODULE_PATHS"))
    candidates.append(VOG_PROJECT_DIR)
    candidates.extend(DISCOVERED_VOG_PROJECT_DIRS)
    if LEGACY_VOG_PROJECT_DIR.exists():
        candidates.append(LEGACY_VOG_PROJECT_DIR)
    return _unique_paths(candidates)


def _candidate_checkpoint_paths() -> list[Path]:
    env_ckpt = os.getenv("VOG_CHECKPOINT_PATH", "").strip()
    env_ckpt_path = Path(env_ckpt).expanduser().resolve() if env_ckpt else None
    candidates = [
        env_ckpt_path if env_ckpt_path else Path("/nonexistent"),
        MODEL_DIR / "checkpoint_best.pth",
        MODEL_DIR / "checkpoint_latest.pth",
        MODEL_DIR / "checkpoints_best.pth",
        VOG_PROJECT_DIR / "checkpoints/gaze/checkpoint_best.pth",
        VOG_PROJECT_DIR / "checkpoints/gaze/checkpoint_latest.pth",
        VOG_PROJECT_DIR / "checkpoints/checkpoint_best.pth",
        VOG_PROJECT_DIR / "checkpoints/checkpoint_latest.pth",
    ]
    for project_dir in DISCOVERED_VOG_PROJECT_DIRS:
        candidates.extend(
            [
                project_dir / "checkpoints/gaze/checkpoint_best.pth",
                project_dir / "checkpoints/gaze/checkpoint_latest.pth",
                project_dir / "checkpoints/checkpoint_best.pth",
                project_dir / "checkpoints/checkpoint_latest.pth",
            ]
        )
    return _unique_paths(candidates)


def _get_vog_runtime() -> tuple[dict[str, Any] | None, str | None]:
    global _VOG_RUNTIME, _VOG_INIT_ERROR
    if _VOG_RUNTIME is not None:
        return _VOG_RUNTIME, None
    if _VOG_INIT_ERROR is not None:
        return None, _VOG_INIT_ERROR
    try:
        module_dirs = _candidate_vog_module_dirs()
        for module_dir in reversed(module_dirs):
            module_str = str(module_dir)
            if module_str not in sys.path:
                sys.path.insert(0, module_str)
        _install_streamlit_stub_if_needed()
        import torch  # type: ignore
        try:
            import vertiwisdom as vw  # type: ignore
        except ModuleNotFoundError as exc:
            raise RuntimeError(
                "未找到 vertiwisdom.py。"
                f"已搜索目录: {[str(p) for p in module_dirs]}。"
                "请将算法工程放到 HNM_VOG_DIR 指向的目录，"
                "或将包含 vertiwisdom.py 的目录加入 HNM_VOG_MODULE_PATHS。"
            ) from exc
        _patch_vertiwisdom_font_support(vw)
        mp_obj = getattr(vw, "mp", None)
        if mp_obj is None or not hasattr(mp_obj, "solutions"):
            raise RuntimeError(
                "当前 mediapipe 缺少 legacy solutions API。"
                "请安装兼容版本（例如 mediapipe==0.10.14）后重启服务。"
            )

        ckpt_candidates = _candidate_checkpoint_paths()
        ckpt = _first_existing(ckpt_candidates)
        if ckpt is None:
            raise RuntimeError(
                "未找到 checkpoint。"
                f"已搜索: {[str(p) for p in ckpt_candidates]}。"
                "请将模型放到 HNM_MODEL_DIR，或设置环境变量 VOG_CHECKPOINT_PATH。"
            )
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        model = vw.load_gaze_model(str(ckpt), device)
        _VOG_RUNTIME = {
            "vw": vw,
            "device": device,
            "model": model,
            "checkpoint": str(ckpt),
            "moduleDirs": [str(p) for p in module_dirs],
            "dataDir": str(DATA_DIR),
            "modelDir": str(MODEL_DIR),
            "vogDir": str(VOG_PROJECT_DIR),
        }
        print(f"[HNM] VertiWisdom runtime ready. checkpoint={ckpt} device={device}")
        return _VOG_RUNTIME, None
    except Exception as exc:
        _VOG_INIT_ERROR = f"{exc}"
        print("[HNM] VertiWisdom runtime init failed:")
        print(traceback.format_exc())
        return None, _VOG_INIT_ERROR


def _patch_vertiwisdom_font_support(vw: Any) -> None:
    if getattr(vw, "_HNM_FONT_PATCHED", False):
        return

    try:
        vw.plt.rcParams["font.sans-serif"] = [
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            "Arial Unicode MS",
            "SimHei",
            "Microsoft YaHei",
            "DejaVu Sans",
        ]
        vw.plt.rcParams["axes.unicode_minus"] = False
    except Exception:
        pass

    original_register = getattr(vw, "register_chinese_font", None)

    def _portable_register() -> bool:
        if getattr(vw, "CHINESE_FONT_REGISTERED", False):
            return True
        try:
            from reportlab.pdfbase import pdfmetrics
            from reportlab.pdfbase.cidfonts import UnicodeCIDFont

            font_name = "STSong-Light"
            pdfmetrics.registerFont(UnicodeCIDFont(font_name))
            vw.CHINESE_FONT_NAME = font_name
            vw.CHINESE_FONT_REGISTERED = True
            return True
        except Exception:
            pass
        if callable(original_register):
            try:
                return bool(original_register())
            except Exception:
                return False
        return False

    vw.register_chinese_font = _portable_register
    vw._HNM_FONT_PATCHED = True


def _safe_slug(value: str, default: str = "na", max_len: int = 64) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    cleaned = cleaned.strip("-._")
    if not cleaned:
        cleaned = default
    return cleaned[:max_len]


def _normalize_input_mode(value: str | None) -> str:
    mode = (value or DEFAULT_INPUT_MODE).strip().lower().replace("-", "_")
    if mode in {"full_face", "face_mesh", "fullface"}:
        return INPUT_MODE_FULL_FACE
    return INPUT_MODE_SINGLE_EYE


def _get_single_eye_normalizer_class(vw: Any) -> Any:
    cached = getattr(vw, "_HNM_SINGLE_EYE_NORMALIZER", None)
    if cached is not None:
        return cached

    import cv2  # type: ignore
    import numpy as np  # type: ignore

    class SingleEyeNormalizer:
        def __init__(
            self,
            eye: str = "left",
            target_size: tuple[int, int] = (36, 60),
            padding: float = 0.0,
            enhance_gamma: float = 1.0,
            enhance_clahe_clip: float = 1.2,
        ):
            self.eye = eye.lower()
            self.target_size = target_size
            self.padding = max(0.0, min(float(padding), 0.25))
            self.enhance_gamma = enhance_gamma
            self.clahe = cv2.createCLAHE(clipLimit=enhance_clahe_clip, tileGridSize=(4, 4))
            self.prev_center: tuple[float, float] | None = None
            self.prev_bounds: tuple[float, float] | None = None
            self.preprocessor = vw.EyeImagePreprocessor(
                target_size=target_size,
                normalize_illumination=False,
                normalize_contrast=False,
                normalize_color=False,
                gamma_correction=False,
                adaptive_hist_eq=False,
                use_geometric_normalization=False,
            )

        def _estimate_geometry(self, frame_bgr: Any) -> tuple[float, float, float, float]:
            h, w = frame_bgr.shape[:2]
            gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
            gray = cv2.GaussianBlur(gray, (9, 9), 0)

            search_x0 = int(w * 0.08)
            search_x1 = max(search_x0 + 1, int(w * 0.92))
            search_y0 = int(h * 0.10)
            search_y1 = max(search_y0 + 1, int(h * 0.90))
            roi = gray[search_y0:search_y1, search_x0:search_x1]

            threshold = float(np.percentile(roi, 12))
            dark_mask = (roi <= threshold).astype(np.uint8)
            kernel = np.ones((5, 5), dtype=np.uint8)
            dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_OPEN, kernel)
            dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_CLOSE, kernel)

            ys, xs = np.where(dark_mask > 0)
            if len(xs) == 0:
                center_x = w * 0.5
                center_y = h * 0.38
                radius = max(12.0, min(w, h) * 0.08)
            else:
                darkness = np.maximum(threshold - roi[ys, xs], 1.0).astype(np.float32)
                cx_local = float(np.average(xs, weights=darkness))
                cy_local = float(np.average(ys, weights=darkness))
                center_x = search_x0 + cx_local
                center_y = search_y0 + cy_local
                area = max(float(len(xs)), 16.0)
                radius = float(np.sqrt(area / np.pi))
                radius = max(12.0, min(radius * 1.35, min(w, h) * 0.18))

            strip_half_width = max(16, int(radius * 2.5))
            x0 = max(0, int(center_x) - strip_half_width)
            x1 = min(w, int(center_x) + strip_half_width)
            strip = gray[:, x0:x1]
            profile = strip.mean(axis=1).astype(np.float32)
            profile = cv2.GaussianBlur(profile.reshape(-1, 1), (1, 31), 0).reshape(-1)
            grad = np.gradient(profile)

            upper_search_start = max(0, int(center_y - radius * 3.0))
            upper_search_end = max(upper_search_start + 1, int(center_y - radius * 0.4))
            lower_search_start = min(h - 1, int(center_y + radius * 0.4))
            lower_search_end = min(h, int(center_y + radius * 3.2))

            if upper_search_end > upper_search_start:
                upper_rel = int(np.argmin(grad[upper_search_start:upper_search_end]))
                upper_y = float(upper_search_start + upper_rel)
            else:
                upper_y = center_y - radius * 1.6

            if lower_search_end > lower_search_start:
                lower_rel = int(np.argmax(grad[lower_search_start:lower_search_end]))
                lower_y = float(lower_search_start + lower_rel)
            else:
                lower_y = center_y + radius * 1.6

            if lower_y <= upper_y:
                upper_y = center_y - radius * 1.6
                lower_y = center_y + radius * 1.6

            if self.prev_center is not None:
                alpha = 0.65
                center_x = alpha * self.prev_center[0] + (1.0 - alpha) * center_x
                center_y = alpha * self.prev_center[1] + (1.0 - alpha) * center_y
            if self.prev_bounds is not None:
                alpha = 0.65
                upper_y = alpha * self.prev_bounds[0] + (1.0 - alpha) * upper_y
                lower_y = alpha * self.prev_bounds[1] + (1.0 - alpha) * lower_y

            self.prev_center = (center_x, center_y)
            self.prev_bounds = (upper_y, lower_y)
            return center_x, center_y, upper_y, lower_y

        def _crop_single_eye(self, frame_bgr: Any) -> Any:
            if frame_bgr is None or getattr(frame_bgr, "size", 0) == 0:
                return None
            h, w = frame_bgr.shape[:2]
            if h < 4 or w < 4:
                return None

            center_x, center_y, upper_y, lower_y = self._estimate_geometry(frame_bgr)

            target_h, target_w = self.target_size
            target_ratio = float(target_w) / float(target_h)
            current_ratio = float(w) / float(h)

            if current_ratio > target_ratio:
                crop_h = h
                crop_w = max(1, int(round(crop_h * target_ratio)))
            else:
                crop_w = w
                crop_h = max(1, int(round(crop_w / target_ratio)))

            if self.padding > 0:
                crop_w = max(1, int(round(crop_w * (1.0 - self.padding))))
                crop_h = max(1, int(round(crop_h * (1.0 - self.padding))))

            eye_center_y = (upper_y + lower_y) / 2.0
            eyelid_height = max(1.0, lower_y - upper_y)
            # 单眼视频里下眼睑梯度通常更强，过大的向下偏置会导致眼睛落在画面上方。
            # 保留少量下方余量，但整体更接近瞳孔/眼裂中心。
            desired_center_y = eye_center_y + eyelid_height * 0.03
            desired_center_x = center_x

            x0 = int(round(desired_center_x - crop_w / 2.0))
            y0 = int(round(desired_center_y - crop_h / 2.0))
            x0 = max(0, min(x0, w - crop_w))
            y0 = max(0, min(y0, h - crop_h))
            x1 = min(w, x0 + crop_w)
            y1 = min(h, y0 + crop_h)
            cropped = frame_bgr[y0:y1, x0:x1]
            return cropped if cropped.size > 0 else None

        def _enhance_single_eye(self, frame_bgr: Any) -> Any:
            gray = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
            gray = self.clahe.apply(gray)
            p2, p98 = np.percentile(gray, (1, 99))
            if p98 > p2:
                gray = np.clip(gray, p2, p98)
                gray = ((gray - p2) / (p98 - p2) * 255).astype(np.uint8)
            return cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)

        def extract(self, frame_bgr: Any) -> tuple[Any, float]:
            cropped = self._crop_single_eye(frame_bgr)
            if cropped is None:
                return None, 0.0
            enhanced = self._enhance_single_eye(cropped)
            roi_tensor = self.preprocessor(enhanced)
            # single-eye 模式不再依赖面部 landmarks / EAR；固定为非眨眼有效帧。
            return roi_tensor, 1.0

        def close(self) -> None:
            return None

    vw._HNM_SINGLE_EYE_NORMALIZER = SingleEyeNormalizer
    return SingleEyeNormalizer


@contextmanager
def _use_vog_input_mode(vw: Any, input_mode: str | None):
    resolved_mode = _normalize_input_mode(input_mode)
    if resolved_mode != INPUT_MODE_SINGLE_EYE:
        yield resolved_mode
        return

    original_normalizer = getattr(vw, "MediaPipeEyeNormalizer")
    vw.MediaPipeEyeNormalizer = _get_single_eye_normalizer_class(vw)
    try:
        yield resolved_mode
    finally:
        vw.MediaPipeEyeNormalizer = original_normalizer


def _compact_timestamp(value: str) -> str:
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return dt.strftime("%Y%m%dT%H%M%S")
    except Exception:
        digits = "".join(ch for ch in value if ch.isdigit())
        return digits[:15] if digits else datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S")


def _package_basename(record_id: str, patient_id: str, started_at: str) -> str:
    ts = _compact_timestamp(started_at)
    pid = _safe_slug(patient_id or "unknown", default="unknown", max_len=40)
    rid = _safe_slug(record_id, default="record", max_len=48)
    return f"hnm_{ts}_pid-{pid}_rec-{rid}"


def _normalize_for_json(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(k): _normalize_for_json(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_normalize_for_json(v) for v in value]
    if hasattr(value, "tolist"):
        return _normalize_for_json(value.tolist())
    if isinstance(value, (str, int, bool)) or value is None:
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    try:
        return float(value)
    except Exception:
        return str(value)


def _pick_typical_clip_range(results: dict[str, Any]) -> tuple[float, float] | None:
    nystagmus = results.get("nystagmus", {})
    all_patterns: list[dict[str, Any]] = []

    for key in ("horizontal_analysis", "vertical_analysis"):
        analysis = nystagmus.get(key, {})
        if analysis.get("has_nystagmus"):
            patterns = analysis.get("patterns", [])
            if isinstance(patterns, list):
                all_patterns.extend([p for p in patterns if isinstance(p, dict)])

    if all_patterns:
        best_pattern = max(all_patterns, key=lambda p: float(p.get("amplitude", 0.0) or 0.0))
        center_time = float(best_pattern.get("time_point", 0.0) or 0.0)
        duration = float(best_pattern.get("total_time", 0.5) or 0.5)
        padding = 0.3
        start_time = max(0.0, center_time - duration - padding)
        end_time = center_time + duration + padding
        if video_duration > 0:
            end_time = min(end_time, video_duration)
        if end_time > start_time:
            return start_time, end_time

    return None


def _roi_tensor_to_bgr_image(roi_tensor: Any, scale: float = 2.0) -> Any:
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    roi_np = roi_tensor.squeeze().detach().cpu().numpy()
    if roi_np.ndim == 2:
        roi_np = (np.clip(roi_np, 0.0, 1.0) * 255).astype(np.uint8)
        roi_rgb = cv2.cvtColor(roi_np, cv2.COLOR_GRAY2RGB)
    else:
        roi_np = (np.clip(roi_np.transpose(1, 2, 0), 0.0, 1.0) * 255).astype(np.uint8)
        roi_rgb = roi_np
    height, width = roi_rgb.shape[:2]
    resized = cv2.resize(
        roi_rgb,
        (int(width * scale), int(height * scale)),
        interpolation=cv2.INTER_CUBIC,
    )
    return cv2.cvtColor(resized, cv2.COLOR_RGB2BGR)


def _render_eye_video(
    video_path: str,
    output_path: Path,
    vw: Any,
    input_mode: str = DEFAULT_INPUT_MODE,
    clip_range: tuple[float, float] | None = None,
    target_size: tuple[int, int] = (72, 120),
    scale: float = 2.0,
) -> int:
    import cv2  # type: ignore
    import numpy as np  # type: ignore

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError("无法打开视频用于导出眼部视频")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 30.0

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    start_frame = 0
    end_frame = total_frames
    if clip_range is not None:
        start_time, end_time = clip_range
        start_frame = max(0, int(start_time * fps))
        end_frame = min(total_frames, int(end_time * fps))
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    normalizer_cls = (
        _get_single_eye_normalizer_class(vw)
        if _normalize_input_mode(input_mode) == INPUT_MODE_SINGLE_EYE
        else vw.MediaPipeEyeNormalizer
    )
    eye_normalizer = normalizer_cls(
        eye="left",
        target_size=target_size,
        enhance_gamma=1.2,
        enhance_clahe_clip=2.0,
    )

    blank_width = int(target_size[1] * scale)
    blank_height = int(target_size[0] * scale)
    writer = cv2.VideoWriter(
        str(output_path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (blank_width, blank_height),
    )

    written = 0
    try:
        for _ in range(start_frame, end_frame):
            ok, frame = cap.read()
            if not ok:
                break
            roi_tensor, _ = eye_normalizer.extract(frame)
            if roi_tensor is not None:
                eye_frame = _roi_tensor_to_bgr_image(roi_tensor, scale=scale)
            else:
                eye_frame = np.zeros((blank_height, blank_width, 3), dtype=np.uint8)
            writer.write(eye_frame)
            written += 1
    finally:
        writer.release()
        cap.release()
        eye_normalizer.close()

    return written


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(_normalize_for_json(payload), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def _record_package_metadata(record: dict[str, Any], package_path: Path) -> dict[str, Any]:
    return {
        "recordId": record.get("id"),
        "accountId": record.get("accountId"),
        "accountName": record.get("accountName"),
        "patientId": record.get("patientId"),
        "sourceVideoName": record.get("sourceVideoName"),
        "inputMode": record.get("inputMode"),
        "startedAt": record.get("startedAt"),
        "durationSec": record.get("durationSec"),
        "analysisCompleted": record.get("analysisCompleted"),
        "suspectNystagmus": record.get("suspectNystagmus"),
        "summary": record.get("summary"),
        "horizontalDirectionLabel": record.get("horizontalDirectionLabel"),
        "verticalDirectionLabel": record.get("verticalDirectionLabel"),
        "dominantFrequencyHz": record.get("dominantFrequencyHz"),
        "spvDegPerSec": record.get("spvDegPerSec"),
        "packageName": package_path.name,
        "packageSizeBytes": package_path.stat().st_size if package_path.exists() else 0,
    }


def _write_record_package_zip(
    stored: StoredRecord,
    zip_path: Path,
    source_video_name: str,
    input_mode: str,
    video_path: str,
    report_path: Path | None,
    eye_video_path: Path | None,
    eye_clip_path: Path | None,
) -> None:
    staging_dir = Path(tempfile.mkdtemp(prefix="hnm_pkg_", dir=str(DATA_DIR)))
    try:
        videos_dir = staging_dir / "videos"
        videos_dir.mkdir(parents=True, exist_ok=True)

        original_ext = Path(video_path).suffix or ".mp4"
        original_arc = videos_dir / f"original{original_ext}"
        eye_full_arc = videos_dir / "eye_full.mp4"
        eye_clip_arc = videos_dir / "eye_typical_clip.mp4"
        patient_info_arc = staging_dir / "patient_info.json"
        record_arc = staging_dir / "record.json"

        shutil.copy2(video_path, original_arc)
        if report_path is not None and report_path.exists():
            shutil.copy2(report_path, staging_dir / "report.pdf")
        if eye_video_path is not None and eye_video_path.exists():
            shutil.copy2(eye_video_path, eye_full_arc)
        if eye_clip_path is not None and eye_clip_path.exists():
            shutil.copy2(eye_clip_path, eye_clip_arc)

        _write_json(
            patient_info_arc,
            {
                "patientId": stored.patientId,
            },
        )
        _write_json(
            record_arc,
            {
                "id": stored.id,
                "accountId": stored.accountId,
                "accountName": stored.accountName,
                "patientId": stored.patientId,
                "startedAt": stored.startedAt,
                "durationSec": stored.durationSec,
                "analysisCompleted": stored.analysisCompleted,
                "suspectNystagmus": stored.suspectNystagmus,
                "summary": stored.summary,
                "horizontalDirectionLabel": stored.horizontalDirectionLabel,
                "verticalDirectionLabel": stored.verticalDirectionLabel,
                "dominantFrequencyHz": stored.dominantFrequencyHz,
                "spvDegPerSec": stored.spvDegPerSec,
                "sampleCount": len(stored.timestampsMs),
                "sourceVideoName": source_video_name,
                "inputMode": _normalize_input_mode(input_mode),
                "hasTypicalClip": eye_clip_path is not None and eye_clip_path.exists(),
                "packageName": zip_path.name,
            },
        )

        zip_path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(staging_dir.rglob("*")):
                if path.is_file():
                    zf.write(path, arcname=str(path.relative_to(staging_dir)))
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)


def _get_record_or_404(record_id: str) -> dict[str, Any]:
    record = store.get_record(record_id)
    if record is None:
        raise HTTPException(status_code=404, detail=f"记录不存在: {record_id}")
    return record


def _get_package_path_or_404(record: dict[str, Any]) -> Path:
    package_file = str(record.get("packageFile") or "").strip()
    if not package_file:
        raise HTTPException(status_code=404, detail="该记录尚未生成 ZIP 包")
    path = Path(package_file)
    if not path.exists() or not path.is_file():
        raise HTTPException(status_code=404, detail="ZIP 包文件不存在")
    return path


def _build_target_path(parsed: Any) -> str:
    path = parsed.path or "/"
    if parsed.query:
        path += f"?{parsed.query}"
    return path


def _excerpt_text(raw: bytes, limit: int = 2000) -> str:
    if not raw:
        return ""
    return raw[:limit].decode("utf-8", errors="replace")


def _open_target_connection(target_url: str, timeout_sec: int) -> tuple[Any, Any]:
    parsed = urlparse(target_url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise RuntimeError("targetUrl 仅支持 http/https 且必须包含主机名")
    if parsed.scheme == "https":
        conn = http.client.HTTPSConnection(parsed.hostname, parsed.port or 443, timeout=timeout_sec)
    else:
        conn = http.client.HTTPConnection(parsed.hostname, parsed.port or 80, timeout=timeout_sec)
    return conn, parsed


def _send_binary_package(
    conn: Any,
    parsed: Any,
    package_path: Path,
    request: PackagePushRequest,
    metadata: dict[str, Any],
) -> tuple[int, str, bytes]:
    method = request.method.upper()
    if method not in {"POST", "PUT"}:
        raise RuntimeError("binary 模式仅支持 POST 或 PUT")

    size = package_path.stat().st_size
    headers = {
        "Content-Type": "application/zip",
        "Content-Length": str(size),
        "X-HNM-Record-Id": str(metadata.get("recordId") or ""),
        "X-HNM-Patient-Id": str(metadata.get("patientId") or ""),
        "X-HNM-Account-Id": str(metadata.get("accountId") or ""),
    }
    headers.update({str(k): str(v) for k, v in request.headers.items()})

    conn.putrequest(method, _build_target_path(parsed), skip_accept_encoding=True)
    for key, value in headers.items():
        conn.putheader(key, value)
    conn.endheaders()

    with package_path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            conn.send(chunk)

    response = conn.getresponse()
    body = response.read()
    return int(response.status), str(response.reason), body


def _send_multipart_package(
    conn: Any,
    parsed: Any,
    package_path: Path,
    request: PackagePushRequest,
    metadata: dict[str, Any],
) -> tuple[int, str, bytes]:
    method = request.method.upper()
    if method not in {"POST", "PUT"}:
        raise RuntimeError("multipart 模式仅支持 POST 或 PUT")

    boundary = f"----HNMServer{os.urandom(8).hex()}"
    package_name = request.fileName or package_path.name
    preamble_parts: list[bytes] = []

    def add_text_part(name: str, value: str, content_type: str = "text/plain; charset=utf-8") -> None:
        preamble_parts.append(
            (
                f"--{boundary}\r\n"
                f"Content-Disposition: form-data; name=\"{name}\"\r\n"
                f"Content-Type: {content_type}\r\n\r\n"
            ).encode("utf-8")
        )
        preamble_parts.append(value.encode("utf-8"))
        preamble_parts.append(b"\r\n")

    for key, value in request.formFields.items():
        add_text_part(str(key), str(value))

    if request.includeRecordMetadata:
        add_text_part(
            request.metadataFieldName,
            json.dumps(_normalize_for_json(metadata), ensure_ascii=False),
            "application/json; charset=utf-8",
        )

    file_header = (
        f"--{boundary}\r\n"
        f"Content-Disposition: form-data; name=\"{request.fileFieldName}\"; filename=\"{package_name}\"\r\n"
        "Content-Type: application/zip\r\n\r\n"
    ).encode("utf-8")
    closing = f"\r\n--{boundary}--\r\n".encode("utf-8")

    total_length = (
        sum(len(part) for part in preamble_parts)
        + len(file_header)
        + package_path.stat().st_size
        + len(closing)
    )

    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(total_length),
    }
    headers.update({str(k): str(v) for k, v in request.headers.items()})

    conn.putrequest(method, _build_target_path(parsed), skip_accept_encoding=True)
    for key, value in headers.items():
        conn.putheader(key, value)
    conn.endheaders()

    for part in preamble_parts:
        conn.send(part)
    conn.send(file_header)
    with package_path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            conn.send(chunk)
    conn.send(closing)

    response = conn.getresponse()
    body = response.read()
    return int(response.status), str(response.reason), body


def _push_record_package(record: dict[str, Any], request: PackagePushRequest) -> dict[str, Any]:
    package_path = _get_package_path_or_404(record)
    metadata = _record_package_metadata(record, package_path)
    method = request.method.upper()
    mode = request.mode.lower().strip()

    if request.dryRun:
        return {
            "ok": True,
            "dryRun": True,
            "targetUrl": request.targetUrl,
            "method": method,
            "mode": mode,
            "packageFile": str(package_path),
            "packageName": package_path.name,
            "packageSizeBytes": metadata["packageSizeBytes"],
            "metadata": metadata,
        }

    conn, parsed = _open_target_connection(request.targetUrl, request.timeoutSec)
    try:
        if mode == "binary":
            status, reason, body = _send_binary_package(conn, parsed, package_path, request, metadata)
        elif mode == "multipart":
            status, reason, body = _send_multipart_package(conn, parsed, package_path, request, metadata)
        else:
            raise RuntimeError("mode 仅支持 multipart 或 binary")
    finally:
        conn.close()

    return {
        "ok": 200 <= status < 300,
        "dryRun": False,
        "targetUrl": request.targetUrl,
        "method": method,
        "mode": mode,
        "packageFile": str(package_path),
        "packageName": package_path.name,
        "packageSizeBytes": metadata["packageSizeBytes"],
        "httpStatus": status,
        "reason": reason,
        "responseExcerpt": _excerpt_text(body),
        "metadata": metadata,
        "sentAt": datetime.now(timezone.utc).isoformat(),
    }


def _build_record_package(
    stored: StoredRecord,
    source_video_name: str,
    raw_results: dict[str, Any],
    input_mode: str = DEFAULT_INPUT_MODE,
) -> dict[str, str]:
    runtime, err = _get_vog_runtime()
    if runtime is None:
        raise RuntimeError(err or "VertiWisdom 初始化失败")
    vw = runtime["vw"]

    if not stored.videoFile:
        raise RuntimeError("缺少原始视频路径，无法打包")

    package_base = _package_basename(stored.id, stored.patientId, stored.startedAt)
    report_path = REPORT_DIR / f"{package_base}.pdf"
    eye_video_path = EYE_VIDEO_DIR / f"{package_base}.mp4"
    eye_clip_path = EYE_CLIP_DIR / f"{package_base}_clip.mp4"
    zip_path = PACKAGE_DIR / f"{package_base}.zip"

    report_generator = vw.MedicalReportGenerator()
    pdf_bytes = report_generator.generate(raw_results, patient_info={"id": stored.patientId})
    report_path.write_bytes(pdf_bytes)

    _render_eye_video(stored.videoFile, eye_video_path, vw=vw, input_mode=input_mode)
    clip_range = _pick_typical_clip_range(raw_results)
    generated_eye_clip_path: Path | None = None
    if clip_range is not None:
        _render_eye_video(
            stored.videoFile,
            eye_clip_path,
            vw=vw,
            input_mode=input_mode,
            clip_range=clip_range,
        )
        generated_eye_clip_path = eye_clip_path

    _write_record_package_zip(
        stored=stored,
        zip_path=zip_path,
        source_video_name=source_video_name,
        input_mode=input_mode,
        video_path=stored.videoFile,
        report_path=report_path,
        eye_video_path=eye_video_path,
        eye_clip_path=generated_eye_clip_path,
    )

    return {
        "reportFile": str(report_path),
        "eyeVideoFile": str(eye_video_path),
        "eyeClipFile": str(generated_eye_clip_path) if generated_eye_clip_path is not None else None,
        "packageFile": str(zip_path),
    }


def analyze_video_with_vertiwisdom(
    video_path: str,
    input_mode: str = DEFAULT_INPUT_MODE,
) -> dict[str, Any]:
    runtime, err = _get_vog_runtime()
    if runtime is None:
        raise RuntimeError(err or "VertiWisdom 初始化失败")
    vw = runtime["vw"]
    device = runtime["device"]
    model = runtime["model"]
    resolved_input_mode = _normalize_input_mode(input_mode)
    try:
        with _use_vog_input_mode(vw, resolved_input_mode):
            results = vw.process_video(
                video_path=video_path,
                gaze_model=model,
                device=device,
                batch_size=16,
                progress_callback=None,
            )
    except ValueError as exc:
        # 常见场景：全部帧被判定为眨眼/无效，触发 numpy min/max on empty array
        # 这里返回可落库的“分析不足”结果，而不是 500。
        if "zero-size array" in str(exc):
            print(f"[HNM] vertiwisdom empty-sample fallback: {exc}")
            return {
                "analysis": {
                    "analysisCompleted": True,
                    "suspectNystagmus": False,
                    "summary": "分析完成：有效眼区帧不足，无法判定眼震",
                    "horizontalDirectionLabel": "-",
                    "verticalDirectionLabel": "-",
                    "dominantFrequencyHz": 0.0,
                    "spvDegPerSec": 0.0,
                    "pitchSeries": [],
                    "yawSeries": [],
                    "timestampsMs": [],
                    "inputMode": resolved_input_mode,
                },
                "rawResults": {
                    "input_mode": resolved_input_mode,
                    "fps": 30.0,
                    "frames": 0,
                    "video_duration": 0.0,
                    "valid_frames": 0,
                    "nystagmus": {
                        "horizontal": {"present": False, "direction_label": "无", "spv": 0.0, "n_patterns": 0},
                        "vertical": {"present": False, "direction_label": "无", "spv": 0.0, "n_patterns": 0},
                        "horizontal_analysis": {"success": False},
                        "vertical_analysis": {"success": False},
                        "summary": "分析完成：有效眼区帧不足，无法判定眼震",
                    },
                },
            }
        raise
    smooth_angles = _normalize_2d_angles(results.get("gaze_angles_smooth"))
    time_ms = _normalize_time_ms(results.get("time"), len(smooth_angles))
    pitch_series = [row[0] for row in smooth_angles]
    yaw_series = [row[1] for row in smooth_angles]
    if len(time_ms) != len(pitch_series):
        # 保底对齐，避免脏数据导致长度不一致
        size = min(len(time_ms), len(pitch_series))
        time_ms = time_ms[:size]
        pitch_series = pitch_series[:size]
        yaw_series = yaw_series[:size]

    nys = results.get("nystagmus", {})
    if not isinstance(nys, dict) or not nys:
        return {
            "analysis": {
                "analysisCompleted": True,
                "suspectNystagmus": False,
                "summary": "分析完成：眼震结果为空，未检测到可用眼震特征",
                "horizontalDirectionLabel": "-",
                "verticalDirectionLabel": "-",
                "dominantFrequencyHz": 0.0,
                "spvDegPerSec": 0.0,
                "pitchSeries": pitch_series,
                "yawSeries": yaw_series,
                "timestampsMs": time_ms,
                "inputMode": resolved_input_mode,
            },
            "rawResults": {**results, "input_mode": resolved_input_mode},
        }
    h = nys.get("horizontal", {})
    v = nys.get("vertical", {})
    h_present = bool(h.get("present", False))
    v_present = bool(v.get("present", False))
    has_nys = h_present or v_present
    h_analysis = nys.get("horizontal_analysis", {})
    v_analysis = nys.get("vertical_analysis", {})
    freq_h = float(h_analysis.get("dominant_frequency", h_analysis.get("frequency", 0.0)) or 0.0)
    freq_v = float(v_analysis.get("dominant_frequency", v_analysis.get("frequency", 0.0)) or 0.0)
    summary_raw = str(nys.get("summary", "")).strip()
    summary = summary_raw or ("疑似眼震（服务端分析）" if has_nys else "分析完成：未见明显眼震")
    return {
        "analysis": {
            "analysisCompleted": True,
            "suspectNystagmus": has_nys,
            "summary": summary,
            "horizontalDirectionLabel": str(h.get("direction_label", "无")),
            "verticalDirectionLabel": str(v.get("direction_label", "无")),
            "dominantFrequencyHz": max(freq_h, freq_v),
            "spvDegPerSec": max(float(h.get("spv", 0.0) or 0.0), float(v.get("spv", 0.0) or 0.0)),
            "pitchSeries": pitch_series,
            "yawSeries": yaw_series,
            "timestampsMs": time_ms,
            "inputMode": resolved_input_mode,
        },
        "rawResults": {**results, "input_mode": resolved_input_mode},
    }


def _normalize_2d_angles(raw: Any) -> list[list[float]]:
    if raw is None:
        return []
    try:
        arr = raw.tolist() if hasattr(raw, "tolist") else raw
        out: list[list[float]] = []
        for item in arr:
            if not isinstance(item, (list, tuple)) or len(item) < 2:
                continue
            p = float(item[0])
            y = float(item[1])
            if math.isfinite(p) and math.isfinite(y):
                out.append([p, y])
        return out
    except Exception:
        return []


def _normalize_time_ms(raw: Any, expected_len: int) -> list[int]:
    if raw is None:
        return list(range(expected_len))
    try:
        arr = raw.tolist() if hasattr(raw, "tolist") else raw
        out: list[int] = []
        for t in arr:
            value = float(t)
            if not math.isfinite(value):
                continue
            # vertiwisdom time 通常是秒，这里统一转 ms
            out.append(int(value * 1000.0))
        if not out:
            return list(range(expected_len))
        base = out[0]
        return [max(0, t - base) for t in out]
    except Exception:
        return list(range(expected_len))


@app.get("/health")
def health() -> dict[str, Any]:
    runtime, err = _get_vog_runtime()
    return {
        "ok": True,
        "service": "home-nystagmus-monitor-server",
        "records": store.count_records(),
        "vertiwisdomReady": runtime is not None,
        "vertiwisdomError": err,
        "runtimeConfig": {
            "dataDir": str(DATA_DIR),
            "modelDir": str(MODEL_DIR),
            "vogDir": str(VOG_PROJECT_DIR),
            "moduleDirs": runtime.get("moduleDirs", []) if runtime else [str(p) for p in _candidate_vog_module_dirs()],
            "checkpoint": runtime.get("checkpoint") if runtime else None,
        },
    }


@app.post("/api/records")
def upload_records(payload: UploadRequest) -> dict[str, Any]:
    uploaded_ids, analyzed_records = store.upsert_many(payload.records)
    return {
        "acceptedCount": len(uploaded_ids),
        "uploadedRecordIds": uploaded_ids,
        "analyzedRecords": analyzed_records,
    }


@app.post("/api/videos")
async def upload_video_record(
    accountId: str = Form(...),
    recordId: str = Form(...),
    accountName: str = Form(""),
    patientId: str = Form(""),
    startedAt: str = Form(""),
    durationSec: int = Form(0),
    inputMode: str = Form(DEFAULT_INPUT_MODE),
    pushTargetUrl: str = Form(""),
    pushMode: str = Form("multipart"),
    pushTimeoutSec: int = Form(30),
    video: UploadFile = File(...),
) -> dict[str, Any]:
    suffix = Path(video.filename or "upload.mp4").suffix or ".mp4"
    tmp_dir = Path(tempfile.mkdtemp(prefix="hnm_upload_", dir=str(UPLOAD_DIR)))
    tmp_video_path = tmp_dir / f"{recordId}{suffix}"
    try:
        with tmp_video_path.open("wb") as f:
            while True:
                chunk = await video.read(1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
        resolved_input_mode = _normalize_input_mode(inputMode)
        analyzed = analyze_video_with_vertiwisdom(str(tmp_video_path), input_mode=resolved_input_mode)
        analysis = analyzed["analysis"]
        raw_results = analyzed["rawResults"]
        saved_video_path = UPLOAD_DIR / f"{recordId}{suffix}"
        os.replace(tmp_video_path, saved_video_path)

        stored = StoredRecord(
            id=recordId,
            accountId=accountId,
            accountName=accountName,
            patientId=patientId.strip(),
            startedAt=startedAt,
            durationSec=durationSec,
            analysisCompleted=bool(analysis.get("analysisCompleted", True)),
            suspectNystagmus=bool(analysis["suspectNystagmus"]),
            summary=str(analysis["summary"]),
            horizontalDirectionLabel=str(analysis["horizontalDirectionLabel"]),
            verticalDirectionLabel=str(analysis["verticalDirectionLabel"]),
            dominantFrequencyHz=float(analysis["dominantFrequencyHz"]),
            spvDegPerSec=float(analysis["spvDegPerSec"]),
            uploaded=True,
            videoFile=str(saved_video_path),
            reportFile=None,
            eyeVideoFile=None,
            eyeClipFile=None,
            packageFile=None,
            sourceVideoName=video.filename or saved_video_path.name,
            inputMode=resolved_input_mode,
            pitchSeries=list(analysis.get("pitchSeries", [])),
            yawSeries=list(analysis.get("yawSeries", [])),
            timestampsMs=list(analysis.get("timestampsMs", [])),
            receivedAt=datetime.now(timezone.utc).isoformat(),
        )
        artifacts = _build_record_package(
            stored=stored,
            source_video_name=video.filename or saved_video_path.name,
            raw_results=raw_results,
            input_mode=resolved_input_mode,
        )
        stored.reportFile = artifacts["reportFile"]
        stored.eyeVideoFile = artifacts["eyeVideoFile"]
        stored.eyeClipFile = artifacts["eyeClipFile"]
        stored.packageFile = artifacts["packageFile"]
        store.upsert_one(stored)
        package_push_result = None
        if pushTargetUrl.strip():
            push_request = PackagePushRequest(
                targetUrl=pushTargetUrl.strip(),
                mode=pushMode.strip() or "multipart",
                timeoutSec=pushTimeoutSec,
            )
            try:
                package_push_result = _push_record_package(asdict(stored), push_request)
            except Exception as push_exc:
                package_push_result = {
                    "ok": False,
                    "targetUrl": push_request.targetUrl,
                    "mode": push_request.mode,
                    "method": push_request.method.upper(),
                    "packageFile": stored.packageFile,
                    "error": str(push_exc),
                    "sentAt": datetime.now(timezone.utc).isoformat(),
                }
        return {
            "uploadedRecordId": recordId,
            "patientId": stored.patientId,
            "analysisCompleted": stored.analysisCompleted,
            "suspectNystagmus": stored.suspectNystagmus,
            "summary": stored.summary,
            "horizontalDirectionLabel": stored.horizontalDirectionLabel,
            "verticalDirectionLabel": stored.verticalDirectionLabel,
            "dominantFrequencyHz": stored.dominantFrequencyHz,
            "spvDegPerSec": stored.spvDegPerSec,
            "sampleCount": len(stored.timestampsMs),
            "inputMode": resolved_input_mode,
            "reportFile": stored.reportFile,
            "eyeVideoFile": stored.eyeVideoFile,
            "eyeClipFile": stored.eyeClipFile,
            "packageFile": stored.packageFile,
            "sourceVideoName": stored.sourceVideoName,
            "packagePushResult": package_push_result,
        }
    except Exception as exc:
        print(
            f"[HNM] Video analysis failed: recordId={recordId} accountId={accountId} "
            f"file={video.filename}"
        )
        print(traceback.format_exc())
        detail = f"视频分析失败: {exc}"
        raise HTTPException(status_code=500, detail=detail) from exc
    finally:
        try:
            await video.close()
        except Exception:
            pass
        try:
            if tmp_video_path.exists():
                tmp_video_path.unlink()
            tmp_dir.rmdir()
        except Exception:
            pass


@app.get("/api/records")
def list_records(
    accountId: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=1000),
    includeArchived: bool = Query(default=False),
) -> dict[str, Any]:
    records = store.list_records(
        account_id=accountId,
        limit=limit,
        include_archived=includeArchived
    )
    return {"count": len(records), "records": records}


@app.get("/api/records/{record_id}/package/download")
def download_record_package(record_id: str) -> FileResponse:
    record = _get_record_or_404(record_id)
    package_path = _get_package_path_or_404(record)
    return FileResponse(
        path=str(package_path),
        media_type="application/zip",
        filename=package_path.name,
    )


@app.post("/api/records/{record_id}/package/push")
def push_record_package(record_id: str, payload: PackagePushRequest) -> dict[str, Any]:
    record = _get_record_or_404(record_id)
    try:
        return _push_record_package(record, payload)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"ZIP 推送失败: {exc}") from exc


@app.get("/api/admin/db-stats")
def db_stats() -> dict[str, Any]:
    db_size = DB_FILE.stat().st_size if DB_FILE.exists() else 0
    return {
        "dbPath": str(DB_FILE),
        "dbSizeBytes": db_size,
        "totalRecords": store.count_records(),
        "byAccount": store.count_by_account(),
    }


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard(
    accountId: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=500),
    showArchived: bool = Query(default=False),
    msg: str | None = Query(default=None),
) -> HTMLResponse:
    stats = db_stats()
    records = store.list_records(account_id=accountId, limit=limit, include_archived=showArchived)
    safe_account = html.escape(accountId or "")
    by_account = stats.get("byAccount", [])
    uploaded_count = sum(1 for r in records if r.get("uploaded"))
    analyzed_count = sum(1 for r in records if r.get("analysisCompleted"))

    def _fmt_size(size: int) -> str:
        value = float(size)
        for unit in ["B", "KB", "MB", "GB"]:
            if value < 1024.0:
                return f"{value:.1f} {unit}"
            value /= 1024.0
        return f"{value:.1f} TB"

    rows_html = []
    for r in records:
        rid = html.escape(r["id"])
        rid_url = quote(str(r["id"]), safe="")
        started_at = html.escape(r.get("startedAt", "-"))
        summary = html.escape(r.get("summary", ""))
        uploaded = bool(r.get("uploaded"))
        analyzed = bool(r.get("analysisCompleted"))
        uploaded_badge = "<span class='badge ok'>已上传</span>" if uploaded else "<span class='badge wait'>待上传</span>"
        analyzed_badge = "<span class='badge ok'>已分析</span>" if analyzed else "<span class='badge wait'>待分析</span>"
        package_action = (
            f"<a class='action-link' href='/api/records/{rid_url}/package/download'>下载 ZIP</a>"
            if r.get("packageFile")
            else "<span class='muted'>无 ZIP</span>"
        )
        sample_count = min(
            len(r.get("timestampsMs", []) or []),
            len(r.get("pitchSeries", []) or []),
            len(r.get("yawSeries", []) or []),
        )
        rows_html.append(
            f"""
            <tr>
              <td><a class="id-link" href="/dashboard/record/{rid}">{rid}</a></td>
              <td>{html.escape(str(r.get("accountId", "")))}</td>
              <td>{started_at}</td>
              <td>{uploaded_badge}</td>
              <td>{analyzed_badge}</td>
              <td>{sample_count}</td>
              <td title="{summary}">{summary[:80]}</td>
              <td>
                <div class="row-actions">
                  {package_action}
                <form method="post" action="/dashboard/delete" onsubmit="return confirm('确认删除该记录？');" style="margin:0;">
                  <input type="hidden" name="recordId" value="{rid}" />
                  <input type="hidden" name="accountId" value="{safe_account}" />
                  <input type="hidden" name="limit" value="{limit}" />
                  <input type="hidden" name="showArchived" value={"1" if showArchived else "0"} />
                  <button class="danger-btn" type="submit">归档</button>
                </form>
                </div>
              </td>
            </tr>
            """
        )

    msg_html = f"<div class='toast'>{html.escape(msg)}</div>" if msg else ""
    account_cards = "".join(
        [
            f"<div class='mini-card'><div class='k'>{html.escape(item['accountId'])}</div><div class='v'>{item['count']} 条</div></div>"
            for item in by_account[:8]
        ]
    ) or "<div class='muted'>暂无账号统计</div>"
    page = _render_template(
        "dashboard.html",
        {
            "MSG_HTML": msg_html,
            "TOTAL_RECORDS": str(stats["totalRecords"]),
            "LIST_COUNT": str(len(records)),
            "UPLOADED_COUNT": str(uploaded_count),
            "ANALYZED_COUNT": str(analyzed_count),
            "DB_PATH": html.escape(str(stats["dbPath"])),
            "DB_SIZE": _fmt_size(int(stats["dbSizeBytes"])),
            "ACCOUNT_CARDS": account_cards.replace("mini-card", "mini"),
            "SAFE_ACCOUNT": safe_account,
            "LIMIT": str(limit),
            "SHOW_ARCHIVED_CHECKED": "checked" if showArchived else "",
            "ROWS_HTML": "".join(rows_html) if rows_html else "<tr><td colspan='8' class='muted'>当前条件下无记录</td></tr>",
        },
    )
    return HTMLResponse(content=page)


@app.get("/dashboard/record/{record_id}", response_class=HTMLResponse)
def dashboard_record_detail(record_id: str) -> HTMLResponse:
    record = store.get_record(record_id)
    if record is None:
        return HTMLResponse(content=f"<h3>记录不存在: {html.escape(record_id)}</h3><a href='/dashboard'>返回</a>", status_code=404)
    record_id_url = quote(record_id, safe="")
    package_actions = (
        f"<div class='head-actions'>"
        f"<a class='primary-action' href='/api/records/{record_id_url}/package/download'>下载 ZIP</a>"
        f"<div class='api-hint'>推送接口: <code>POST /api/records/{record_id_url}/package/push</code></div>"
        f"</div>"
        if record.get("packageFile")
        else "<div class='api-hint'>当前记录尚未生成 ZIP 包</div>"
    )
    package_endpoints = (
        f"<div class='endpoint'><span>下载</span><code>GET /api/records/{record_id_url}/package/download</code></div>"
        f"<div class='endpoint'><span>推送</span><code>POST /api/records/{record_id_url}/package/push</code></div>"
        if record.get("packageFile")
        else "<div class='meta'>当前无可用 ZIP 产物。</div>"
    )
    payload = html.escape(
        json.dumps(
            {
                "id": record.get("id"),
                "accountId": record.get("accountId"),
                "accountName": record.get("accountName"),
                "patientId": record.get("patientId"),
                "startedAt": record.get("startedAt"),
                "durationSec": record.get("durationSec"),
                "uploaded": record.get("uploaded"),
                "analysisCompleted": record.get("analysisCompleted"),
                "summary": record.get("summary"),
                "horizontalDirectionLabel": record.get("horizontalDirectionLabel"),
                "verticalDirectionLabel": record.get("verticalDirectionLabel"),
                "dominantFrequencyHz": record.get("dominantFrequencyHz"),
                "spvDegPerSec": record.get("spvDegPerSec"),
                "sourceVideoName": record.get("sourceVideoName"),
                "inputMode": record.get("inputMode"),
                "videoFile": record.get("videoFile"),
                "reportFile": record.get("reportFile"),
                "eyeVideoFile": record.get("eyeVideoFile"),
                "eyeClipFile": record.get("eyeClipFile"),
                "packageFile": record.get("packageFile"),
                "packageDownloadUrl": f"/api/records/{record_id_url}/package/download" if record.get("packageFile") else None,
                "packagePushEndpoint": f"/api/records/{record_id_url}/package/push" if record.get("packageFile") else None,
                "sampleCount": min(
                    len(record.get("timestampsMs", []) or []),
                    len(record.get("pitchSeries", []) or []),
                    len(record.get("yawSeries", []) or []),
                ),
                "timestampsMs": record.get("timestampsMs", []),
                "pitchSeries": record.get("pitchSeries", []),
                "yawSeries": record.get("yawSeries", []),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    page = _render_template(
        "record_detail.html",
        {
            "RECORD_ID": html.escape(record_id),
            "PACKAGE_ACTIONS": package_actions,
            "PACKAGE_ENDPOINTS": package_endpoints,
            "PAYLOAD": payload,
        },
    )
    return HTMLResponse(content=page)


@app.post("/dashboard/delete")
def dashboard_delete(
    recordId: str = Form(...),
    accountId: str = Form(default=""),
    limit: int = Form(default=50),
    showArchived: int = Form(default=0),
) -> RedirectResponse:
    deleted = store.archive_record(recordId)
    query = {
        "limit": max(1, min(limit, 500)),
        "showArchived": 1 if showArchived else 0,
        "msg": f"{'已归档' if deleted else '未找到'}: {recordId}",
    }
    if accountId.strip():
        query["accountId"] = accountId.strip()
    return RedirectResponse(url="/dashboard?" + urlencode(query), status_code=303)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8787, reload=True)
