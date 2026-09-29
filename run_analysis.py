from pathlib import Path
import os

import duckdb


PROJECT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = PROJECT_DIR / "outputs"


def main() -> None:
    OUTPUT_DIR.mkdir(exist_ok=True)
    os.chdir(PROJECT_DIR)

    sql = (PROJECT_DIR / "analysis.sql").read_text(encoding="utf-8")
    with duckdb.connect() as connection:
        connection.execute(sql)

    print(f"Analysis complete. Results written to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()