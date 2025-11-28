"""Training entrypoint for the SafeOn anomaly detector.

Run with:
    python -m app.train --dataset ../datasets/esp32-cam/esp32_win3_dataset.csv
"""

import argparse
import os
from pathlib import Path

from app.model import ModelService


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train SafeOn models on the provided dataset.")
    # CLI 인자(--dataset같은 --로 시작하는 옵션)로 데이터셋과
    # 하이퍼파라미터(모델학습에 미리 정해두는 설정값, 코드가 스스로 학습하지 않는 수치를 말함 ex. --epochs or --batch-size)
    # 를 덮어써서 빠르게 실험할 수 있도록 한다.
    parser.add_argument(
        "--dataset",
        type=Path,
        default=None,
        help="Path to CSV dataset (defaults to DATASET_PATH env or datasets/esp32-cam/esp32_win3_dataset.csv).",
    )
    parser.add_argument(
        "--epochs",
        type=int,
        default=int(os.getenv("EPOCHS", "10")),
        help="Number of epochs for the Transformer autoencoder.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        dest="batch_size",
        default=int(os.getenv("BATCH_SIZE", "32")),
        help="Batch size for the Transformer autoencoder.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    # ModelService가 전처리/학습/아티팩트 저장을 모두 관리한다.
    service = ModelService.from_env()
    result = service.train(dataset_path=args.dataset, epochs=args.epochs, batch_size=args.batch_size)
    print("Training complete.")
    print(f"Artifacts saved to: {result['model_dir']}")
    print(f"Dataset used: {result['dataset']}")
    print(f"Device: {result['device']}")


if __name__ == "__main__":
    main()
