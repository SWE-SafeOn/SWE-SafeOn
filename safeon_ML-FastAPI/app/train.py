import os
import joblib
import numpy as np
import pandas as pd
from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from sklearn.ensemble import IsolationForest
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

# ---------------------------------------------------
# 모델 저장 폴더 생성
# ---------------------------------------------------
os.makedirs("models", exist_ok=True)

# ---------------------------------------------------
# Transformer Autoencoder 정의
# ---------------------------------------------------
class TransformerAE(nn.Module):
    def __init__(self, num_features, seq_len, emb_dim=64, nhead=4, num_layers=2):
        super().__init__()
        self.input_layer = nn.Linear(num_features, emb_dim)

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=emb_dim, nhead=nhead, batch_first=True
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)

        decoder_layer = nn.TransformerDecoderLayer(
            d_model=emb_dim, nhead=nhead, batch_first=True
        )
        self.decoder = nn.TransformerDecoder(decoder_layer, num_layers=num_layers)

        self.output_layer = nn.Linear(emb_dim, num_features)

    def forward(self, x):
        x_emb = self.input_layer(x)
        encoded = self.encoder(x_emb)
        decoded = self.decoder(x_emb, encoded)
        out = self.output_layer(decoded)
        return out

# ---------------------------------------------------
# 1. 데이터 불러오기
# ---------------------------------------------------
normal = pd.read_csv("data/normal_esp32_win10.csv")
attack = pd.read_csv("data/esp32_attack.csv")

normal["label"] = 0
attack["label"] = 1

df = pd.concat([normal, attack], ignore_index=True)
df = df.sort_values("start_time")
df = df.reset_index(drop=True)

print("Loaded dataset shape:", df.shape)

# ---------------------------------------------------
# 2. Feature 선택 및 전처리
# ---------------------------------------------------
features = [
    "src_ip", "dst_ip", "src_port", "dst_port",
    "proto", "packet_count", "byte_count",
    "duration", "pps", "bps"
]

df_feat = df[features].copy()

# LabelEncoder 3개 생성
enc_src_ip = LabelEncoder()
enc_dst_ip = LabelEncoder()
enc_proto = LabelEncoder()

df_feat["src_ip"] = enc_src_ip.fit_transform(df_feat["src_ip"])
df_feat["dst_ip"] = enc_dst_ip.fit_transform(df_feat["dst_ip"])
df_feat["proto"]  = enc_proto.fit_transform(df_feat["proto"])

# 저장
joblib.dump(enc_src_ip, "models/enc_src_ip.pkl")
joblib.dump(enc_dst_ip, "models/enc_dst_ip.pkl")
joblib.dump(enc_proto, "models/enc_proto.pkl")

# Scaling feature들 0~1로 정규화
scaler = MinMaxScaler()
scaled = scaler.fit_transform(df_feat)
joblib.dump(scaler, "models/scaler.pkl")

print("Feature scaling done.")

labels = df["label"].values

# ---------------------------------------------------
# 3. Sequence 생성 함수
# ---------------------------------------------------
def create_sequences(data, labels, seq_len=20):
    X, y = [], []
    for i in range(len(data) - seq_len):
        X.append(data[i:i+seq_len])
        y.append(labels[i+seq_len])
    return np.array(X), np.array(y)

SEQ_LEN = 20
X_seq, y_seq = create_sequences(scaled, labels, SEQ_LEN)

print("Sequence shape:", X_seq.shape)

# 정상 데이터만 AE에 사용
X_seq_normal = X_seq[y_seq == 0]
print("Normal sequences for AE:", X_seq_normal.shape)

# ---------------------------------------------------
# 4. Isolation Forest
# ---------------------------------------------------
print("Training IsolationForest~")
iso = IsolationForest(contamination=0.05, random_state=42)
iso.fit(scaled)
joblib.dump(iso, "models/isolation_forest.pkl")
print("IsolationForest saved")

# ---------------------------------------------------
# 5. Transformer Autoencoder 학습
# ---------------------------------------------------
device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
print("Using device:", device)

num_features = X_seq.shape[2]

X_tensor = torch.tensor(X_seq_normal, dtype=torch.float32)
dataset = DataLoader(TensorDataset(X_tensor, X_tensor), batch_size=32, shuffle=True)

model = TransformerAE(num_features=num_features, seq_len=SEQ_LEN).to(device)
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
criterion = nn.MSELoss()

print("Training Transformer Autoencoder~")

EPOCHS = 10
for epoch in range(1, EPOCHS + 1):
    model.train()
    epoch_loss = 0

    for batch_x, _ in dataset:
        batch_x = batch_x.to(device)
        optimizer.zero_grad()

        out = model(batch_x)
        loss = criterion(out, batch_x)
        loss.backward()
        optimizer.step()

        epoch_loss += loss.item()

    print(f"Epoch {epoch}/{EPOCHS}, Loss: {epoch_loss:.5f}")

torch.save(model.state_dict(), "models/transformer_ae.pth")
print("Transformer AE saved.")

print("\nTraining Complete.")

