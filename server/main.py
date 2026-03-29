from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import html
import math
import os
import sqlite3
import sys
import tempfile
import traceback
import types
from statistics import median
from pathlib import Path
from threading import Lock
from typing import Any
from urllib.parse import urlencode

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DATA_FILE = DATA_DIR / "records.jsonl"
DB_FILE = DATA_DIR / "records.db"
UPLOAD_DIR = DATA_DIR / "uploads"
MODEL_DIR = BASE_DIR / "models"
WEB_DIR = BASE_DIR / "web"
WEB_TEMPLATE_DIR = WEB_DIR / "templates"
VOG_PROJECT_DIR = Path("/home/kk/Documents/proj/SwinUNet-VOG")


class RecordPayload(BaseModel):
    id: str
    accountId: str
    accountName: str
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


@dataclass
class StoredRecord:
    id: str
    accountId: str
    accountName: str
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
                    pitch_series_json TEXT NOT NULL,
                    yaw_series_json TEXT NOT NULL,
                    timestamps_ms_json TEXT NOT NULL,
                    received_at TEXT NOT NULL
                )
                """
            )
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
                    pitch_series_json, yaw_series_json, timestamps_ms_json, received_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            stored = StoredRecord(
                id=rec.id,
                accountId=rec.accountId,
                accountName=rec.accountName,
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
                videoFile=None,
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

    def archive_record(self, record_id: str) -> bool:
        with self._connect() as conn:
            cur0 = conn.execute("SELECT id FROM records WHERE id = ?", (record_id,))
            row = cur0.fetchone()
            if row is None:
                return False
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


def _get_vog_runtime() -> tuple[dict[str, Any] | None, str | None]:
    global _VOG_RUNTIME, _VOG_INIT_ERROR
    if _VOG_RUNTIME is not None:
        return _VOG_RUNTIME, None
    if _VOG_INIT_ERROR is not None:
        return None, _VOG_INIT_ERROR
    try:
        # 允许两种位置：
        # 1) 当前仓库 server/vertiwisdom.py
        # 2) 外部 /home/kk/Documents/proj/SwinUNet-VOG/vertiwisdom.py
        if str(BASE_DIR) not in sys.path:
            sys.path.insert(0, str(BASE_DIR))
        if str(VOG_PROJECT_DIR) not in sys.path:
            sys.path.insert(0, str(VOG_PROJECT_DIR))
        _install_streamlit_stub_if_needed()
        import torch  # type: ignore
        import vertiwisdom as vw  # type: ignore
        mp_obj = getattr(vw, "mp", None)
        if mp_obj is None or not hasattr(mp_obj, "solutions"):
            raise RuntimeError(
                "当前 mediapipe 缺少 legacy solutions API。"
                "请安装兼容版本（例如 mediapipe==0.10.14）后重启服务。"
            )

        # 优先使用当前仓库内模型：server/models/
        env_ckpt = os.getenv("VOG_CHECKPOINT_PATH", "").strip()
        env_ckpt_path = Path(env_ckpt) if env_ckpt else None
        ckpt = _first_existing(
            [
                env_ckpt_path if env_ckpt_path else Path("/nonexistent"),
                MODEL_DIR / "checkpoint_best.pth",
                MODEL_DIR / "checkpoint_latest.pth",
                MODEL_DIR / "checkpoints_best.pth",
                VOG_PROJECT_DIR / "checkpoints/gaze/checkpoint_best.pth",
                VOG_PROJECT_DIR / "checkpoints/gaze/checkpoint_latest.pth",
                VOG_PROJECT_DIR / "checkpoints/checkpoint_best.pth",
                VOG_PROJECT_DIR / "checkpoints/checkpoint_latest.pth",
            ]
        )
        if ckpt is None:
            raise RuntimeError(
                "未找到 checkpoint。请将模型放到 server/models/checkpoint_best.pth "
                "或设置环境变量 VOG_CHECKPOINT_PATH"
            )
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        model = vw.load_gaze_model(str(ckpt), device)
        _VOG_RUNTIME = {"vw": vw, "device": device, "model": model, "checkpoint": str(ckpt)}
        print(f"[HNM] VertiWisdom runtime ready. checkpoint={ckpt} device={device}")
        return _VOG_RUNTIME, None
    except Exception as exc:
        _VOG_INIT_ERROR = f"{exc}"
        print("[HNM] VertiWisdom runtime init failed:")
        print(traceback.format_exc())
        return None, _VOG_INIT_ERROR


def analyze_video_with_vertiwisdom(video_path: str) -> dict[str, Any]:
    runtime, err = _get_vog_runtime()
    if runtime is None:
        raise RuntimeError(err or "VertiWisdom 初始化失败")
    vw = runtime["vw"]
    device = runtime["device"]
    model = runtime["model"]
    try:
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
    startedAt: str = Form(""),
    durationSec: int = Form(0),
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
        analysis = analyze_video_with_vertiwisdom(str(tmp_video_path))
        saved_video_path = UPLOAD_DIR / f"{recordId}{suffix}"
        os.replace(tmp_video_path, saved_video_path)

        stored = StoredRecord(
            id=recordId,
            accountId=accountId,
            accountName=accountName,
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
            pitchSeries=list(analysis.get("pitchSeries", [])),
            yawSeries=list(analysis.get("yawSeries", [])),
            timestampsMs=list(analysis.get("timestampsMs", [])),
            receivedAt=datetime.now(timezone.utc).isoformat(),
        )
        store.upsert_one(stored)
        return {
            "uploadedRecordId": recordId,
            "analysisCompleted": stored.analysisCompleted,
            "suspectNystagmus": stored.suspectNystagmus,
            "summary": stored.summary,
            "horizontalDirectionLabel": stored.horizontalDirectionLabel,
            "verticalDirectionLabel": stored.verticalDirectionLabel,
            "dominantFrequencyHz": stored.dominantFrequencyHz,
            "spvDegPerSec": stored.spvDegPerSec,
            "sampleCount": len(stored.timestampsMs),
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
        started_at = html.escape(r.get("startedAt", "-"))
        summary = html.escape(r.get("summary", ""))
        uploaded = bool(r.get("uploaded"))
        analyzed = bool(r.get("analysisCompleted"))
        uploaded_badge = "<span class='badge ok'>已上传</span>" if uploaded else "<span class='badge wait'>待上传</span>"
        analyzed_badge = "<span class='badge ok'>已分析</span>" if analyzed else "<span class='badge wait'>待分析</span>"
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
                <form method="post" action="/dashboard/delete" onsubmit="return confirm('确认删除该记录？');" style="margin:0;">
                  <input type="hidden" name="recordId" value="{rid}" />
                  <input type="hidden" name="accountId" value="{safe_account}" />
                  <input type="hidden" name="limit" value="{limit}" />
                  <input type="hidden" name="showArchived" value={"1" if showArchived else "0"} />
                  <button class="danger-btn" type="submit">归档</button>
                </form>
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
    payload = html.escape(
        json.dumps(
            {
                "id": record.get("id"),
                "accountId": record.get("accountId"),
                "accountName": record.get("accountName"),
                "startedAt": record.get("startedAt"),
                "durationSec": record.get("durationSec"),
                "uploaded": record.get("uploaded"),
                "analysisCompleted": record.get("analysisCompleted"),
                "summary": record.get("summary"),
                "horizontalDirectionLabel": record.get("horizontalDirectionLabel"),
                "verticalDirectionLabel": record.get("verticalDirectionLabel"),
                "dominantFrequencyHz": record.get("dominantFrequencyHz"),
                "spvDegPerSec": record.get("spvDegPerSec"),
                "videoFile": record.get("videoFile"),
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
