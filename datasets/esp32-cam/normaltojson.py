import pandas as pd

# Mac에서의 실제 파일 경로
df = pd.read_csv('normal1_win3.csv')

# JSON 저장
df.to_json('normal1_win3.json', orient='records', indent=2)

print("변환 완료: normal1_win3.json 생성됨")
