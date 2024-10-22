#!/bin/bash

# 作業ディレクトリの定義
WORKSPACE_DIR="$HOME/drep-workspace"
METADATA_DIR="$WORKSPACE_DIR/metadata"
SPLIT_DIR="$WORKSPACE_DIR/split"
mkdir -p "$WORKSPACE_DIR" "$METADATA_DIR" "$SPLIT_DIR"

# 1. 全DRepリストを取得し、JSONに保存
echo "Fetching DRep list..."
curl -X GET "https://api.koios.rest/api/v1/drep_list" \
 -H "accept: application/json" > "$WORKSPACE_DIR/drep_list.json"

# 2. DRepの総数を集計し、登録済みDRepのリストを抽出
echo "Summarizing DReps..."
python3 - << EOF
import json

# ファイル読み込み
with open("$WORKSPACE_DIR/drep_list.json", "r") as file:
    drep_list = json.load(file)

# 総DRep数
total_dreps = len(drep_list)

# 登録済みDRepのカウント
registered_dreps = [drep for drep in drep_list if drep['registered'] == True]
unregistered_dreps = [drep for drep in drep_list if drep['registered'] == False]

# 集計結果保存
summary = {
    "total_dreps": total_dreps,
    "registered_dreps": len(registered_dreps),
    "unregistered_dreps": len(unregistered_dreps)
}

with open("$WORKSPACE_DIR/drep_summary.json", "w") as file:
    json.dump(summary, file, indent=4)

print(f"Total DReps: {total_dreps}, Registered: {len(registered_dreps)}, Unregistered: {len(unregistered_dreps)}")

# 登録済みDRepのIDをリスト化
registered_ids = [drep['drep_id'] for drep in registered_dreps]
with open("$WORKSPACE_DIR/registered_drep_ids.json", "w") as file:
    json.dump(registered_ids, file, indent=4)
EOF

# 3. 登録済みDRepのIDを4000バイトごとに分割
echo "Splitting DRep IDs into chunks..."
python3 - << EOF
import json
import os

# IDリストの読み込み
with open("$WORKSPACE_DIR/registered_drep_ids.json", "r") as file:
    drep_ids = json.load(file)

# 4000バイト以下のファイルに分割
def split_into_files(drep_ids, max_bytes=4000):
    os.makedirs("$SPLIT_DIR", exist_ok=True)
    part_num = 1
    current_size = 0
    current_ids = []

    for drep_id in drep_ids:
        drep_json = json.dumps([drep_id])
        if current_size + len(drep_json) > max_bytes:
            with open(f"$SPLIT_DIR/drep_part_{part_num}.json", "w") as f:
                json.dump(current_ids, f, indent=4)
            part_num += 1
            current_ids = []
            current_size = 0
        current_ids.append(drep_id)
        current_size += len(drep_json)

    if current_ids:
        with open(f"$SPLIT_DIR/drep_part_{part_num}.json", "w") as f:
            json.dump(current_ids, f, indent=4)

split_into_files(drep_ids)
EOF

# 4. Koios APIに分割したDRep IDを使ってメタデータを取得
echo "Fetching DRep metadata..."
for file in $SPLIT_DIR/drep_part_*.json; do
  # DRep ID のリストを取得し、JSONリスト形式にフォーマット
  DREP_ID=$(jq -c '.' < "$file")

  # DREP_IDが空でないか確認
  if [[ -z "$DREP_ID" ]]; then
    echo "Error: DREP_ID is empty in file $file"
    continue
  fi

  # curl でPOSTリクエストを送信
  curl -X POST "https://api.koios.rest/api/v1/drep_metadata" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -d "{\"_drep_ids\":$DREP_ID}" > "$METADATA_DIR/${file##*/}-metadata.json"
  
  # サーバーへのリクエスト間隔を設ける（例: 5秒待機）
  sleep 5
done

# 5. メタデータを1つに統合
echo "Combining metadata..."
jq -s '.' $METADATA_DIR/*-metadata.json | jq -c '.[]' | jq -s add > "$METADATA_DIR/combined_metadata.json"

# 6. Bech32エンコードして必要なデータを抽出し、URLからの情報を取得
echo "Encoding hex to Bech32 and extracting data from metadata..."
python3 - << EOF
import json
import requests
import bech32

# Bech32エンコード関数
def bech32_encode_digest(digest_bytes):
    bech32_data = bech32.convertbits(digest_bytes, 8, 5)
    return bech32.bech32_encode("drep", bech32_data)

# メタデータの読み込み
with open("$METADATA_DIR/combined_metadata.json", "r") as file:
    metadata = json.load(file)

bech32_results = []
for drep in metadata:
    hex_digest = drep['hex']
    digest_bytes = bytes.fromhex(hex_digest)
    drep_id = bech32_encode_digest(digest_bytes)
    url = drep.get('url', '')

    # URLからJSONを取得
    if url:
        try:
            response = requests.get(url)
            response.raise_for_status()
            metadata_json = response.json()

            # 必要な要素を抽出
            body = metadata_json.get('body', {})
            doNotList = body.get('doNotList', '')
            givenName = body.get('givenName', '')
            motivations = body.get('motivations', '')
            objectives = body.get('objectives', '')
            qualifications = body.get('qualifications', '')
            references = body.get('references', '')

            bech32_results.append({
                'drep_id': drep_id,
                'hex': hex_digest,
                'url': url,
                'doNotList': doNotList,
                'givenName': givenName,
                'motivations': motivations,
                'objectives': objectives,
                'qualifications': qualifications,
                'references': references
            })
        except Exception as e:
            print(f"Error fetching URL {url}: {e}")
            continue

# 結果を保存
with open("$WORKSPACE_DIR/bech32_results.json", "w") as file:
    json.dump(bech32_results, file, indent=4)
EOF

# 7. スプレッドシート形式でCSV出力
echo "Generating CSV..."
python3 - << EOF
import csv
import json

# Bech32結果の読み込み
with open("$WORKSPACE_DIR/bech32_results.json", "r") as file:
    bech32_results = json.load(file)

# CSVに書き込む
csv_file = "$WORKSPACE_DIR/drep_output.csv"
fields = ["CIP-105形式", "Name", "Objectives", "Motivations", "Qualifications", "References", "URL"]
with open(csv_file, "w", newline="", encoding="utf-8") as file:
    writer = csv.DictWriter(file, fieldnames=fields)
    writer.writeheader()
    for result in bech32_results:
        writer.writerow({
            "CIP-105形式": result['drep_id'],
            "Name": result['givenName'],
            "Objectives": result['objectives'],
            "Motivations": result['motivations'],
            "Qualifications": result['qualifications'],
            "References": result['references'],
            "URL": result['url']
        })

print(f"CSV file generated: {csv_file}")
EOF

echo "Process complete."
