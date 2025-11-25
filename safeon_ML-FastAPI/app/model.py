import joblib
import numpy as np
import pandas as pd
import torch
import torch.nn as nn

# ============================================================
# Transformer Autoencoder (train.py와 동일 구조)
# ============================================================
class TransformerAE(nn.Module):
    def __init__(self, num_features, seq_len, emb_dim=64, nhead=4, num_layers=2):
        super().__init__()

        # 같은 이름 = 같은 구조 = weight load 성공
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
        enc = self.encoder(x_emb)
        dec = self.decoder(x_emb, enc)  # IMPORTANT: (tgt=x_emb, memory=enc)
        out = self.output_layer(dec)
        return out


# ============================================================
# 1. 모델/인코더 불러오기
# ============================================================
print("Using device:", "mps" if torch.backends.mps.is_available() else "cpu")
device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")

# LabelEncoders
enc_src_ip = joblib.load("models/enc_src_ip.pkl")
enc_dst_ip = joblib.load("models/enc_dst_ip.pkl")
enc_proto  = joblib.load("models/enc_proto.pkl")

# Scaler
scaler = joblib.load("models/scaler.pkl")

# Isolation Forest
iso = joblib.load("models/isolation_forest.pkl")

# Autoencoder (load after building same structure)
NUM_FEATURES = 10
SEQ_LEN = 20

transformer = TransformerAE(num_features=NUM_FEATURES, seq_len=SEQ_LEN).to(device)
transformer.load_state_dict(torch.load("models/transformer_ae.pth", map_location=device))
transformer.eval()


# ============================================================
# 2. 최근 패킷을 쌓아 시퀀스 만드는 버퍼
# ============================================================
packet_buffer = []   # 실시간 데이터 시퀀스 누적
INTRUSION_COUNT = 0  # 누적 이상치 건수 카운트


# ============================================================
# 3. 패킷 전처리 함수
# ============================================================
def preprocess_packet(row: dict):

    df = pd.DataFrame([row])

    # LabelEncoding
    df["src_ip"] = enc_src_ip.transform(df["src_ip"])
    df["dst_ip"] = enc_dst_ip.transform(df["dst_ip"])
    df["proto"]  = enc_proto.transform(df["proto"])
  
    df = df[[
        "src_ip", "dst_ip",
        "src_port", "dst_port",
        "proto",
        "packet_count", "byte_count",
        "duration", "pps", "bps"
    ]]  

    # Scaling
    scaled = scaler.transform(df)

    return scaled[0]


# ============================================================
# 4. 실시간 탐지 함수
# ============================================================
def detect_intrusion(raw_packet: dict):
    global INTRUSION_COUNT, packet_buffer

    # -------------------------
    # 1) 전처리
    # -------------------------
    vec = preprocess_packet(raw_packet)
    packet_buffer.append(vec)

    if len(packet_buffer) < SEQ_LEN:
        return None  # 아직 시퀀스 부족 → 판단 불가

    if len(packet_buffer) > SEQ_LEN:
        packet_buffer = packet_buffer[-SEQ_LEN:]

    seq = np.array(packet_buffer).reshape(1, SEQ_LEN, NUM_FEATURES)

    # -------------------------
    # 2) IsolationForest anomaly score
    # -------------------------
    if_score = -iso.decision_function([vec])[0]
    if_score = max(0, min(1, if_score))

    # -------------------------
    # 3) Transformer AE reconstruction error
    # -------------------------
    seq_t = torch.tensor(seq, dtype=torch.float32).to(device)
    with torch.no_grad():
        recon = transformer(seq_t)
    ae_err = torch.mean((seq_t - recon) ** 2).item()
    ae_err = min(1.0, ae_err * 10)

    # -------------------------
    # 4) 통합 스코어
    # -------------------------
    final = 0.5 * if_score + 0.5 * ae_err

    # -------------------------
    # 5) 이상 판정
    # -------------------------
    is_intrusion = final > 0.35  # 임계값 직접 조정 가능 뭘로 할지 안 정함

    if is_intrusion:
        INTRUSION_COUNT += 1

    return {
        "if_score": float(if_score),
        "ae_error": float(ae_err),
        "final_score": float(final),
        "is_intrusion": bool(is_intrusion),
        "intrusion_count": INTRUSION_COUNT,
    }


# ============================================================
# 5. 테스트 예시 (정상 데이터 25개)
# ============================================================
print("\nTesting intrusion detection...")

sample_df = pd.read_csv("data/normal_esp32_win10.csv").head(50)

for i in range(len(sample_df)):
    pkt = {
        "src_ip":  sample_df.iloc[i]["src_ip"],
        "dst_ip":  sample_df.iloc[i]["dst_ip"],
        "proto":   sample_df.iloc[i]["proto"],
        "src_port": sample_df.iloc[i]["src_port"],
        "dst_port": sample_df.iloc[i]["dst_port"],
        "packet_count": sample_df.iloc[i]["packet_count"],
        "byte_count": sample_df.iloc[i]["byte_count"],
        "duration": sample_df.iloc[i]["duration"],
        "pps": sample_df.iloc[i]["pps"],
        "bps": sample_df.iloc[i]["bps"],
    }

    result = detect_intrusion(pkt)
    print(i, result)

