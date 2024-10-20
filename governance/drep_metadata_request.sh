#!/bin/bash

# 作業ディレクトリを作成（存在しない場合のみ）
mkdir -p "$HOME/drep-workspace"

# 全DRepリスト取得
curl -X GET "https://api.koios.rest/api/v1/drep_list" \
 -H "accept: application/json" >> $HOME/drep-workspace/drep_list.json

# 登録済みのDRep（True）のみを抽出
jq '.[] | select(.registered == true)' < $HOME/drep-workspace/drep_list.json | jq -s '.' > $HOME/drep-workspace/true_drep_list.json

# 登録済みのDRep（False）のみを抽出
jq '.[] | select(.registered == false)' < $HOME/drep-workspace/drep_list.json | jq -s '.' > $HOME/drep-workspace/false_drep_list.json

# 登録済みのDRepを集計
echo "登録済みのDRep (総数) = $(jq '. | length' < $HOME/drep-workspace/drep_list.json)"
echo "登録済みのDRep (True) = $(jq '[.[]] | length' < $HOME/drep-workspace/true_drep_list.json)"
echo "登録済みのDRep (False) = $(jq '[.[]] | length' < $HOME/drep-workspace/false_drep_list.json)"

# JSONファイルを分割するスクリプトの作成
cat > $HOME/drep-workspace/split_json_by_size.sh << EOF 
#!/bin/bash

# 入力ファイルと出力ディレクトリの設定
input_file="$HOME/drep-workspace/true_drep_list.json"
output_dir="$HOME/drep-workspace/split"
max_size=4000  # 1ファイルの最大バイト数

# 出力ディレクトリを作成
mkdir -p "\$output_dir"

# 元のJSONファイルを1行ごとにオブジェクトに変換
jq -c '.[]' "\$input_file" > true_drep_list_lines.json

# 分割処理の初期化
file_counter=1
current_file="\$output_dir/drep_part_\$file_counter.json"

# 最初のファイルを作成し、JSON配列開始
echo "[" > "\$current_file"
current_size=\$(stat --format=%s "\$current_file")

# 各オブジェクトを処理
while read -r line; do
  # 1行を一時ファイルに追加してサイズを確認
  temp_file=\$(mktemp)
  echo "\$line" >> "\$temp_file"
  temp_size=\$((\$(stat --format=%s "\$current_file") + \$(stat --format=%s "\$temp_file")))

  # サイズが4000バイトを超えない場合
  if [ "\$temp_size" -lt "\$max_size" ]; then
    if [ "\$current_size" -gt 2 ]; then
      echo "," >> "\$current_file"  # 2バイト以上ならカンマを追加
    fi
    cat "\$temp_file" >> "\$current_file"
    current_size=\$temp_size
  else
    # 4000バイトを超えた場合はファイルを閉じて新しいファイルを作成
    echo "]" >> "\$current_file"
    file_counter=\$((file_counter + 1))
    current_file="\$output_dir/drep_part_\$file_counter.json"
    echo "[" > "\$current_file"
    cat "\$temp_file" >> "\$current_file"
    current_size=\$(stat --format=%s "\$current_file")
  fi

  rm "\$temp_file"
done < true_drep_list_lines.json

# 最後のファイルを閉じる
echo "]" >> "\$current_file"

# 中間ファイルを削除
rm true_drep_list_lines.json

echo "分割完了: \$output_dir 内にファイルが保存されました。"
EOF

# 実行権限付与
chmod +x $HOME/drep-workspace/split_json_by_size.sh

# split_json_by_size.sh 実行
$HOME/drep-workspace/split_json_by_size.sh

# メタデータを保存するディレクトリ
metadata_dir="$HOME/drep-workspace/metadata"

# ディレクトリを作成（存在しない場合のみ）
mkdir -p "$metadata_dir"

# DRep ID のリストを含むファイルをループ処理
for file in $HOME/drep-workspace/split/drep_part_*.json; do
  # DRep ID のリストを取得
  DREP_ID=$(jq -r '[.[] | select(.registered == true) | .drep_id]' < "$file")

  # curl でPOSTリクエストを送信
  curl -X POST "https://api.koios.rest/api/v1/drep_metadata" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -d "{\"_drep_ids\":$DREP_ID}" > "$metadata_dir/${file##*/}-metadata.json"

  # サーバーへのリクエスト間隔を設ける（例: 5秒待機）
  sleep 5
done

# 指定したディレクトリ内のすべての -metadata.json ファイルを一つにまとめる
jq -s '.' $HOME/drep-workspace/metadata/*-metadata.json > $HOME/drep-workspace/metadata/combined_metadata.json
