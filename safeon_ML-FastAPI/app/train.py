"""Training entrypoint for the SafeOn anomaly detector (IsolationForest + RandomForest).

Run with:
    python -m app.train --dataset ../datasets/esp32-cam/dataset.csv
"""

import argparse
from pathlib import Path

from app.model import ModelService


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train SafeOn models on the provided dataset.")
    # CLI 인자(--dataset같은 --로 시작하는 옵션)로 데이터셋을 덮어써서 빠르게 실험할 수 있도록 한다.
    parser.add_argument(
        "--dataset",
        type=Path,
        default=None,
        help="Path to CSV dataset (defaults to DATASET_PATH env or datasets/esp32-cam/dataset.csv).",
    )
    parser.add_argument(
        "--attacker-dataset",
        type=Path,
        default=None,
        help="Optional attacker dataset CSV to label as attacks (defaults to ATTACKER_DATASET_PATH env).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    # ModelService가 전처리/학습/아티팩트 저장을 모두 관리한다.
    service = ModelService.from_env()
    result = service.train(dataset_path=args.dataset, attacker_dataset_path=args.attacker_dataset)
    print("Training complete.")
    print(f"Artifacts saved to: {result['model_dir']}")
    print(f"Dataset used: {result['dataset']}")


if __name__ == "__main__":
    main()
