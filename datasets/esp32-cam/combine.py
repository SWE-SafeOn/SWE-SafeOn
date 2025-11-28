"""Utility to merge the win3 CSV exports into a single training dataset."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable, List

import pandas as pd


# 기본 정상/공격 CSV 파일 목록
DEFAULT_NORMAL_FILES = ["normal1_win3.csv", "normal2_win3.csv"]
DEFAULT_ATTACK_FILE = "attack_win3.csv"
DEFAULT_OUTPUT = "esp32_win3_dataset.csv"
EXPECTED_COLUMNS = [
    "src_ip",
    "dst_ip",
    "src_port",
    "dst_port",
    "proto",
    "time_bucket",
    "start_time",
    "end_time",
    "duration",
    "packet_count",
    "byte_count",
    "pps",
    "bps",
    "label",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Combine win3 captures (normal + attack) into one CSV dataset."
    )
    parser.add_argument(
        "--normal",
        nargs="+",
        default=DEFAULT_NORMAL_FILES,
        help="List of normal traffic CSV filenames (relative to this script).",
    )
    parser.add_argument(
        "--attack",
        default=DEFAULT_ATTACK_FILE,
        help="Attack traffic CSV filename (relative to this script).",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Name of the combined dataset CSV to write (relative to this script).",
    )
    parser.add_argument(
        "--shuffle-seed",
        type=int,
        default=42,
        help="Random seed used when shuffling the merged rows.",
    )
    return parser.parse_args()


def load_csv(path: Path) -> pd.DataFrame:
    # CSV가 학습에 필요한 컬럼을 모두 갖추고 있는지 확인
    df = pd.read_csv(path)
    missing = [col for col in EXPECTED_COLUMNS if col not in df.columns]
    if missing:
        raise ValueError(f"{path} is missing required columns: {', '.join(missing)}")
    return df[EXPECTED_COLUMNS].copy()


def concat_frames(paths: Iterable[Path]) -> pd.DataFrame:
    frames: List[pd.DataFrame] = []
    for csv_path in paths:
        if not csv_path.exists():
            raise FileNotFoundError(f"Dataset not found: {csv_path}")
        frames.append(load_csv(csv_path))
    # 정상/공격 데이터를 하나로 이어 붙인 DataFrame 반환
    return pd.concat(frames, ignore_index=True)


def main() -> None:
    args = parse_args()
    base_dir = Path(__file__).parent

    normal_paths = [base_dir / filename for filename in args.normal]
    attack_path = base_dir / args.attack
    output_path = base_dir / args.output

    combined = concat_frames([*normal_paths, attack_path])
    # 셔플하여 시계열 상관관계를 줄이고 학습 데이터 편향을 완화
    combined = combined.sample(frac=1, random_state=args.shuffle_seed).reset_index(drop=True)

    combined.to_csv(output_path, index=False)
    print(f"Combined dataset saved to {output_path}")
    print(f"Total rows: {len(combined)}")


if __name__ == "__main__":
    main()
