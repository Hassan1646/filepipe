import pytest

from app.filepipe import LocalStorage, parse_amount, parse_date, run, transform

GOOD_CSV = (
    "payment_id,claimant_ref,amount,payment_date,status\n"
    "P001,ab123c,£1,250.5,01/10/2026,paid\n"
    "P002,CD456E,99.999,2026-10-02,PENDING\n"
)


def test_parse_date_accepts_uk_and_iso():
    assert parse_date("01/10/2026") == "2026-10-01"
    assert parse_date("2026-10-01") == "2026-10-01"


def test_parse_date_rejects_rubbish():
    with pytest.raises(ValueError):
        parse_date("31/02/2026")


def test_parse_amount_rounds_and_strips_symbols():
    assert parse_amount("£1,250.5") == "1250.50"
    assert parse_amount("99.999") == "100.00"


def test_parse_amount_rejects_zero_and_negative():
    for bad in ["0", "-5", "abc"]:
        with pytest.raises(ValueError):
            parse_amount(bad)


def test_transform_cleans_good_rows():
    # Quote the amount because it contains a comma
    csv_text = GOOD_CSV.replace("£1,250.5", '"£1,250.5"')
    good, rejected = transform(csv_text)
    assert rejected == []
    assert good[0]["amount"] == "1250.50"
    assert good[0]["claimant_ref"] == "AB123C"
    assert good[0]["status"] == "PAID"


def test_transform_sends_bad_rows_to_rejects():
    csv_text = (
        "payment_id,claimant_ref,amount,payment_date,status\n"
        "P001,AB1,10,01/10/2026,PAID\n"
        "P002,AB2,10,not-a-date,PAID\n"
        ",AB3,10,01/10/2026,PAID\n"
    )
    good, rejected = transform(csv_text)
    assert len(good) == 1
    assert len(rejected) == 2
    assert rejected[0]["line"] == 3
    assert "bad date" in rejected[0]["reason"]


def test_transform_rejects_file_with_missing_columns():
    with pytest.raises(ValueError, match="missing columns"):
        transform("payment_id,amount\nP1,10\n")


def test_run_end_to_end(tmp_path):
    input_dir = tmp_path / "input"
    input_dir.mkdir()
    (input_dir / "batch.csv").write_text(
        "payment_id,claimant_ref,amount,payment_date,status\n"
        "P1,AB1,10,01/10/2026,PAID\n"
        "P2,AB2,10,bad,PAID\n"
    )
    storage = LocalStorage(str(input_dir), str(tmp_path / "output"))
    assert run(storage) == 0
    assert (tmp_path / "output" / "batch_clean.csv").exists()
    assert (tmp_path / "output" / "batch_rejects.csv").exists()


def test_run_fails_when_no_files(tmp_path):
    storage = LocalStorage(str(tmp_path / "empty"), str(tmp_path / "output"))
    assert run(storage) == 2