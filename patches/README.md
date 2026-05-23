# Patches

## `esp-csi`（ESP-IDF v6 互換）

`esp-idf-v6-compat.patch` は **esp-csi の特定コミット**向けです。`bootstrap-dev-env.sh` で checkout
するコミットと一致させてください。

- **想定コミット:** `8633d67152db2808f141cc1595970aa9cf406045`（`master` 上の Merge コミット）
- **適用:** リポジトリルートから `./scripts/apply-esp-csi-patches.sh`  
  （[スクリプト](../scripts/apply-esp-csi-patches.sh)）。**二重適用はスキップ**  
  （`git apply --reverse --check`）。

esp-csi をバンプしたら、クリーンなツリーで `git diff` からパッチを作り直し、
この README とスクリプト内の `EXPECTED_ESP_CSI_COMMIT` を更新してください。

参考: [git-apply](https://git-scm.com/docs/git-apply)
