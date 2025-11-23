import pandas as pd
import numpy as np

# 파일 불러오기
normal_df = pd.read_csv("normal_esp32_ISO.csv")
attack_df = pd.read_csv("esp32_attack_ISO.csv")

# attack 데이터에서 무작위 18줄 추출
attack_sample = attack_df.sample(n=19, random_state=42)

# normal + attack 합치기
combined = pd.concat([normal_df, attack_sample], ignore_index=True)

# 총 개수 확인
print("Before shuffle:", combined.shape)

# 랜덤 셔플
combined = combined.sample(frac=1, random_state=42).reset_index(drop=True)

# 저장
combined.to_csv("esp32_500_dataset.csv", index=False)

print("Saved as esp32_500_dataset.csv")
print("After shuffle:", combined.shape)