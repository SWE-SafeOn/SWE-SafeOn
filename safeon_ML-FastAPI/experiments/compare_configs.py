# safeon_ML-FastAPI/experiments/compare_configs.py
import os
import shutil
from pathlib import Path

import pandas as pd

from app.model import FlowFeatures, ModelService

DATASET = Path("../datasets/esp32-cam/esp32_win3_dataset.csv")
VAL_RATIO = 0.2
TMP_TRAIN = Path("/tmp/safeon_train_subset.csv")

CONFIGS = [
    {"name": "1번", "contamination": 0.05, "epochs": 16, "batch": 32},
]


def evaluate(service: ModelService, val_df: pd.DataFrame) -> float:
    preds = []
    for _, row in val_df.iterrows():
        flow = FlowFeatures(**row[service.feature_columns].to_dict())
        result = service.predict(flow)
        preds.append((result["is_anom"], row["label"] != 0))
    tp = sum(p and t for p, t in preds)
    fp = sum(p and not t for p, t in preds)
    fn = sum((not p) and t for p, t in preds)
    precision = tp / (tp + fp + 1e-9)
    recall = tp / (tp + fn + 1e-9)
    f1 = 2 * precision * recall / (precision + recall + 1e-9)
    return f1


def main() -> None:
    df = pd.read_csv(DATASET)
    df["proto"] = df["proto"].astype(str).str.upper()
    split = int(len(df) * (1 - VAL_RATIO))
    train_df = df.iloc[:split]
    val_df = df.iloc[split:]
    train_df.to_csv(TMP_TRAIN, index=False)

    results = []
    for cfg in CONFIGS:
        model_dir = Path(f"models/exp_{cfg['name']}")
        if model_dir.exists():
            shutil.rmtree(model_dir)
        model_dir.mkdir(parents=True)

        os.environ["MODEL_DIR"] = str(model_dir)
        os.environ["DATASET_PATH"] = str(TMP_TRAIN)
        os.environ["ALLOW_DUMMY"] = "false"
        os.environ["CONTAMINATION"] = str(cfg["contamination"])

        service = ModelService.from_env()
        service.train(dataset_path=TMP_TRAIN, epochs=cfg["epochs"], batch_size=cfg["batch"])
        f1 = evaluate(service, val_df)
        results.append({"config": cfg["name"], "f1": f1})
        print(cfg["name"], f1)

    pd.DataFrame(results).to_csv("experiments/results.csv", index=False)


if __name__ == "__main__":
    main()
