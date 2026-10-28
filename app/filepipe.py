"""FilePipe: a nightly batch job that cleans payment CSV files.

What it does, in plain English:
  1. Finds every .csv file waiting in the input location.
  2. Checks each row. Good rows are cleaned (dates made ISO, amounts made 2dp).
  3. Writes good rows to an output file and bad rows to a rejects file.
  4. Logs everything as JSON so CloudWatch (or Kubernetes) can read it.

Where files come from is decided by environment variables:
  - Local mode (default): INPUT_DIR and OUTPUT_DIR folders.
  - S3 mode: set INPUT_BUCKET and OUTPUT_BUCKET instead.
"""

import csv
import io
import json
import logging
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

REQUIRED_COLUMNS = ["payment_id", "claimant_ref", "amount", "payment_date", "status"]
VALID_STATUSES = {"PAID", "PENDING", "FAILED"}
OUTPUT_COLUMNS = REQUIRED_COLUMNS + ["processed_at"]


class JsonFormatter(logging.Formatter):
    """Turns every log line into one JSON object (structured logging)."""

    def format(self, record):
        entry = {
            "time": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "service": "filepipe",
        }
        entry.update(getattr(record, "extra_fields", {}))
        return json.dumps(entry)


def get_logger():
    logger = logging.getLogger("filepipe")
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
    logger.setLevel(os.getenv("LOG_LEVEL", "INFO"))
    return logger


log = get_logger()


def info(message, **fields):
    log.info(message, extra={"extra_fields": fields})


def error(message, **fields):
    log.error(message, extra={"extra_fields": fields})


# ---------------------------------------------------------------------------
# Row cleaning: pure functions, easy to unit test
# ---------------------------------------------------------------------------

def parse_date(value):
    """Accept DD/MM/YYYY or YYYY-MM-DD and return YYYY-MM-DD."""
    value = (value or "").strip()
    for fmt in ("%d/%m/%Y", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    raise ValueError(f"bad date '{value}'")


def parse_amount(value):
    """Return the amount as a string with 2 decimal places. Must be > 0."""
    try:
        amount = Decimal((value or "").replace("£", "").replace(",", "").strip())
    except InvalidOperation:
        raise ValueError(f"bad amount '{value}'")
    if amount <= 0:
        raise ValueError(f"amount must be positive, got '{value}'")
    return str(amount.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


def clean_row(row, processed_at):
    """Clean one row. Raises ValueError with a reason if the row is bad."""
    if not (row.get("payment_id") or "").strip():
        raise ValueError("missing payment_id")
    status = (row.get("status") or "").strip().upper()
    if status not in VALID_STATUSES:
        raise ValueError(f"bad status '{row.get('status')}'")
    return {
        "payment_id": row["payment_id"].strip(),
        "claimant_ref": (row.get("claimant_ref") or "").strip().upper(),
        "amount": parse_amount(row.get("amount")),
        "payment_date": parse_date(row.get("payment_date")),
        "status": status,
        "processed_at": processed_at,
    }


def transform(csv_text):
    """Transform the text of one CSV file.

    Returns (good_rows, rejected_rows). Each rejected row has a 'reason'.
    Raises ValueError if the file is missing required columns.
    """
    reader = csv.DictReader(io.StringIO(csv_text))
    missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
    if missing:
        raise ValueError(f"file is missing columns: {', '.join(missing)}")

    processed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    good, rejected = [], []
    for line_number, row in enumerate(reader, start=2):  # line 1 is the header
        try:
            good.append(clean_row(row, processed_at))
        except ValueError as exc:
            rejected.append({**row, "line": line_number, "reason": str(exc)})
    return good, rejected


def to_csv(rows, columns):
    buffer = io.StringIO()
    writer = csv.DictWriter(buffer, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


# ---------------------------------------------------------------------------
# Storage: local folders or S3. The rest of the code doesn't care which.
# ---------------------------------------------------------------------------

class LocalStorage:
    def __init__(self, input_dir, output_dir):
        self.input_dir = input_dir
        self.output_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

    def list_inputs(self):
        if not os.path.isdir(self.input_dir):
            return []
        return sorted(f for f in os.listdir(self.input_dir) if f.lower().endswith(".csv"))

    def read(self, name):
        with open(os.path.join(self.input_dir, name), encoding="utf-8-sig") as f:
            return f.read()

    def write(self, name, text):
        with open(os.path.join(self.output_dir, name), "w", encoding="utf-8", newline="") as f:
            f.write(text)


class S3Storage:
    def __init__(self, input_bucket, output_bucket, prefix="incoming/"):
        import boto3  # only needed in S3 mode

        self.s3 = boto3.client("s3")
        self.input_bucket = input_bucket
        self.output_bucket = output_bucket
        self.prefix = prefix

    def list_inputs(self):
        response = self.s3.list_objects_v2(Bucket=self.input_bucket, Prefix=self.prefix)
        keys = [o["Key"] for o in response.get("Contents", [])]
        return sorted(k for k in keys if k.lower().endswith(".csv"))

    def read(self, name):
        body = self.s3.get_object(Bucket=self.input_bucket, Key=name)["Body"].read()
        return body.decode("utf-8-sig")

    def write(self, name, text):
        key = os.path.basename(name)
        self.s3.put_object(Bucket=self.output_bucket, Key=f"processed/{key}", Body=text.encode())


def storage_from_env():
    if os.getenv("INPUT_BUCKET"):
        return S3Storage(os.environ["INPUT_BUCKET"], os.environ["OUTPUT_BUCKET"])
    return LocalStorage(os.getenv("INPUT_DIR", "input"), os.getenv("OUTPUT_DIR", "output"))


# ---------------------------------------------------------------------------
# Main job
# ---------------------------------------------------------------------------

def run(storage):
    """Process every input file. Returns the process exit code (0 = success)."""
    files = storage.list_inputs()
    info("run started", files_found=len(files))
    if not files:
        error("no input files found")
        return 2

    failed_files = 0
    for name in files:
        base = os.path.splitext(os.path.basename(name))[0]
        try:
            good, rejected = transform(storage.read(name))
        except ValueError as exc:
            failed_files += 1
            error("file rejected", file=name, reason=str(exc))
            continue

        storage.write(f"{base}_clean.csv", to_csv(good, OUTPUT_COLUMNS))
        if rejected:
            columns = REQUIRED_COLUMNS + ["line", "reason"]
            storage.write(f"{base}_rejects.csv", to_csv(rejected, columns))
        info("file processed", file=name, good_rows=len(good), rejected_rows=len(rejected))

    if failed_files:
        error("run finished with failures", failed_files=failed_files)
        return 1
    info("run finished", status="success")
    return 0


if __name__ == "__main__":
    sys.exit(run(storage_from_env()))