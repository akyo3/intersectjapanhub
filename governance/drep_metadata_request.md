# Koios-APIを用いて、DRepのmetadataを取得

スクリプトの動作
1. DRepリストの取得：指定された URL から DRep リストを取得し、ファイルに保存します。
2. 登録済みの DRep の抽出：true と false の DRep をそれぞれ抽出してファイルに保存します。
3. 統計の表示：登録済みの DRep の総数を表示します。
4. JSONファイルの分割：true_drep_list.json を 4000 バイト以下のファイルに分割するためのサブスクリプトを作成して実行します。
5. POSTリクエストの送信：分割された各 JSON ファイルについて、登録済み DRep ID を抽出し、POST リクエストを送信します。リクエストの間に 5 秒待機します。

使用方法
1. 上記のスクリプトを drep_metadata_request.sh として保存します。
```
wget https://raw.githubusercontent.com/btbf/spojapanguild/master/scripts/blocks.sh -O ./drep_metadata_request.sh
```
2. 実行権限を与えます。
```
chmod +x drep_metadata_request.sh
```
3. スクリプトを実行します。
```
./drep_metadata_request.sh
```

このスクリプトを実行すると、すべての処理が自動的に行われ、DRep メタデータのリクエストがサーバーに送信されます。

# 指定したディレクトリ内のすべての -metadata.json ファイルを一つにまとめる
```
jq -s '.' $HOME/drep-workspace/metadata/*-metadata.json > $HOME/drep-workspace/metadata/combined_metadata.json
```