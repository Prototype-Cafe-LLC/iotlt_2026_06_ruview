# iotlt_2026_06_ruview

RuView LT

## 準備するもの

- ESP32-S3 (２つ)
  - 秋月電子通商などで購入可能 (執筆時点で 2,380円/個)
  - [ESP32-S3-DevKitC-1 公式ドキュメント](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32s3/esp32-s3-devkitc-1/index.html)

## ソフトウェアの準備

```bash
export PROJECT_ROOT=/home/pcafe/projects/pcafe/iotlt_2026_06_ruview
```

### esp-idf

```bash
# 長い時間かかります
git clone -b v6.0.1 --recursive https://github.com/espressif/esp-idf.git esp-idf-v6.0.1

cd ${PROJECT_ROOT}/esp-idf-v6.0.1/
# ちょっと長い時間かかる
./install.sh esp32s3
. ./export.sh
```

### esp-csi

```bash
cd ${PROJECT_ROOT}
git clone https://github.com/espressif/esp-csi.git
cd esp-csi
```

## 構成

### ESP32-S3 構成: 送信機一つ・受信機一つ

micro USB 端子を UARTと書いている側のコネクタでPCと接続

参考: Ubuntuでみたときのデバイス名はこれだった `CP2102N USB to UART Bridge Controller`

#### 送信側

```bash
# ESP-IDF 環境を有効化（このシェルで未実行、または esp-idf を移動した場合は再実行）
# ※ idf.py はフルパス指定せず、export.sh を source して PATH 経由で使うこと。
#    フルパスと IDF_PATH が食い違うとエラーになる。
cd ${PROJECT_ROOT}
# 古い IDF_PATH が残っていたら消してから source する
unset IDF_PATH
. esp-idf-v6.0.1/export.sh
echo $IDF_PATH   # → ${PROJECT_ROOT}/esp-idf-v6.0.1 を指していればOK

cd ${PROJECT_ROOT}/esp-csi/examples/get-started/csi_send

# 【重要】clone 直後は ESP-IDF v6 ではビルドできない（修正適用済み）:
#   main/app_main.c の Wi-Fi 帯域幅 enum が v6 でリネームされたため
#     WIFI_BW_HT40 → WIFI_BW40 / WIFI_BW_HT20 → WIFI_BW20

# ターゲット設定（最初の1回だけ）
idf.py set-target esp32s3

# ビルド＋書き込み＋モニタ（/dev/ttyUSB4 は個別に確認）
idf.py flash -b 921600 -p /dev/ttyUSB4 monitor
# 書き込み済みで、ログだけ見たいとき
idf.py monitor -p /dev/ttyUSB4


# ログがこのあたりまででていれば成功です
# I (519) wifi:mode : sta (90:70:69:35:36:4c)
# I (519) wifi:enable tsf
# I (520) wifi:Set ps type: 0, coexist: 0

# I (523) wifi:enable tsf
# I (525) ESPNOW: espnow [version: 2.0] init
# I (525) csi_send: ================ CSI SEND ================
# I (529) csi_send: wifi_channel: 11, send_frequency: 100, mac: 1a:00:00:00:00:00
```

#### 受信側

```bash
# ESP-IDF 環境を有効化（シェルごとに必要。送信側とは別ターミナルなら必ず実行）
# ※ esp-idf を移動・コピーした直後は `install.sh esp32s3` を再実行してから source すること
cd ${PROJECT_ROOT}
unset IDF_PATH
. esp-idf-v6.0.1/export.sh
echo $IDF_PATH   # → ${PROJECT_ROOT}/esp-idf-v6.0.1 を指していればOK

cd ${PROJECT_ROOT}/esp-csi/examples/esp-radar/console_test

# 【重要】clone 直後は ESP-IDF v6 ではビルドできない（修正適用済み）:
#   components/commands/src/wifi_cmd.c: ESP_IF_WIFI_AP → WIFI_IF_AP（v6 で削除された別名）
#   CMakeLists.txt: managed component led_strip(2.5.5) が esp_heap_caps.h を
#     include し忘れているため、-include esp_heap_caps.h を追加して回避
idf.py set-target esp32s3

# 書き込み（受信側は送信側とは別ポート。可視化ツールも同じポートを使うので monitor は付けない）
# /dev/ttyUSB5 は個別に確認してください
idf.py flash -b 921600 -p /dev/ttyUSB5
```

#### PC側で可視化ツール

```bash
cd ${PROJECT_ROOT}/esp-csi/examples/esp-radar/console_test/tools

# uv で仮想環境を作成して有効化（初回のみ。.venv は再利用可）
uv venv
source .venv/bin/activate

# 依存をインストール（requirements.txt: PyQt5, pyqtgraph, pandas, numpy, scipy, pyserial ...）
uv pip install -r requirements.txt

# 【重要】requirements.txt はバージョン無指定のため、uv は最新の pandas 3.0 / numpy 2.x を
# 入れてしまう。これらは esp_csi_tool.py と非互換で、起動後に TypeError が大量に出て
# CSI データを取り込めない（data 列への list 代入が失敗する）。互換版に固定する:
uv pip install "numpy==1.26.4" "pandas==2.2.3"

# CSI波形、RSSI、Wi-Fiチャネル情報、在室・動作判定のしきい値調整などを表示
# ポートは受信側を flash したものと同じ（/dev/ttyUSB5 は個別に確認してください）
python esp_csi_tool.py -p /dev/ttyUSB5
```

### ESP32-S3 構成: 受信機２つ（オフィスのAPをCSI源にする）

送信機（csi_send）を使わず、**オフィスの既存Wi-Fi AP（ルーター）をCSIの発生源**にし、
ESP32-S3 **2台を両方とも受信機**にする構成。各受信機は「自分とAPの間」のCSIを取得するので、
2台を空間的に離して置くことで**広いエリア**をカバーできる（RuView 本来の使い方）。

```text
            (CSI源)
        オフィスのAP / ルーター
          /              \
         / Wi-Fi          \ Wi-Fi
        /                  \
  ESP32-S3 #1          ESP32-S3 #2     ← どちらも console_test（受信機）
   (/dev/ttyUSBx)       (/dev/ttyUSBy)
        |                   |
   esp_csi_tool.py     esp_csi_tool.py  ← PCで2インスタンス起動
```

> 仕組み: `console_test` はAPに STA として接続し、AP へ ping を打ってトラフィックを発生させ、
> その応答パケットから CSI を抽出する（`components/commands/src/ping_cmd.c`）。
> esp-crab（master/slave 受信）は ESP32-C5 専用基板向けなので、ESP32-S3 では使わない。

#### 1. 両方のデバイスに受信機ファーム（console_test）を書き込む

「送信機一つ・受信機一つ」構成と同じ `console_test` を、2台それぞれのポートへ flash する。
（IDF v6 向け修正は適用済み。各シェルで `export.sh` を source 済みであること）

```bash
cd ${PROJECT_ROOT}/esp-csi/examples/esp-radar/console_test
idf.py set-target esp32s3   # 既に済んでいれば不要

# 1台目（ポートは個別に確認）
idf.py flash -b 921600 -p /dev/ttyUSB4
# 2台目を接続し直し、そのポートへ
idf.py flash -b 921600 -p /dev/ttyUSB5
```

> ヒント: 2台のポート(/dev/ttyUSB*)を取り違えないこと。
> 1台ずつ挿して `ls /dev/ttyUSB`* の差分を見ると確実。

#### 2. PC側で可視化ツールを2インスタンス起動（受信機ごと）

`esp_csi_tool.py` は1ポート＝1台なので、**ターミナルを2つ開いて各ポートを指定**する。
venv（pandas==2.2.3 / numpy==1.26.4 固定済み）は使い回せる。

```bash
# ターミナルA（受信機#1）
cd ${PROJECT_ROOT}/esp-csi/examples/esp-radar/console_test/tools
source .venv/bin/activate
python esp_csi_tool.py -p /dev/ttyUSB4

# ターミナルB（受信機#2）
cd ${PROJECT_ROOT}/esp-csi/examples/esp-radar/console_test/tools
source .venv/bin/activate
python esp_csi_tool.py -p /dev/ttyUSB4
```

#### 3. 各GUIでオフィスのAPに接続する

左上の **router connection window** で、各受信機をAPに接続する:

1. **SSID** / **password** にオフィスAPの情報を入力
2. **connect** をクリック（接続後、デバイスがAPへ ping を開始し CSI が流れ始める）
3. **auto connect** にチェックを入れておくと、次回起動時に自動再接続

接続できると subcarrier amplitude に波形が出る。2台とも同様に接続する。

#### 補足・注意

- **APはなるべく他端末を繋がない**（混雑するとパケット間隔が乱れCSI品質が落ちる。esp-csi 公式も推奨）。
- 2.4GHz 帯・チャネル固定が安定しやすい。2台の受信機は**1〜数m離して**設置するとカバー範囲が広がる。
- 在室(someone)/動作(move)判定は**各受信機で個別に**走る。2台の結果を突き合わせて
「どちらのエリアで動きがあったか」を見るのが2受信機構成の旨味（自動統合は esp-csi 標準にはなく、RuView 側の付加価値ポイント）。
- ESP-NOW構成（送信機一つ）と違い、こちらはAPトラフィックに依存するため、ping応答が来ないとCSIが途切れる。
途切れる場合は AP との距離・電波状況・APのファイアウォール(ping遮断)を確認する。

## 用語集

- **CSI**  
Channel State Information（チャネル状態情報）。Wi-Fi のサブキャリア等のチャネル推定結果で、
多径・遮蔽・人体の動きなどが反映される。本リポジトリでは esp-csi で取得・可視化する。
- **CSI源**  
CSI を得る参照リンクの相手。ESP-NOW 構成では送信機、AP 構成ではオフィスの AP など。
- **ESP-IDF**  
Espressif の ESP32 向け開発フレームワーク。`idf.py` でビルド・書き込み・モニタを行う。
- **IDF_PATH**  
ESP-IDF ルートの環境変数。`export.sh` を source すると設定。誤パスと混在するとビルドエラー。
- **AP**  
Access Point。Wi-Fi 基地局（ルーター無線部など）。本 README では STA が接続する相手。
- **STA**  
Station。インフラモードで AP に接続するクライアント。`console_test` は STA として AP に接続。
- **SSID**  
接続先ネットワーク名。可視化ツールのルータ接続画面で入力する。
- **RSSI**  
Received Signal Strength Indicator。受信信号強度。可視化ツールで CSI と併せて表示。
- **サブキャリア**  
OFDM 等でチャネルを周波数分割した各成分。GUI の subcarrier amplitude は振幅の推移。
- **ESP-NOW**  
Espressif のピアツーピア無線。`csi_send` 例で用い、送信機と受信機間でパケットをやり取り。
- **csi_send**  
esp-csi の送信サンプル（`examples/get-started/csi_send`）。CSI 取得用トラフィックを送る。
- **console_test**  
esp-csi の受信サンプル（`examples/esp-radar/console_test`）。CSI を受信しシリアルで PC に渡す。
- **esp_csi_tool.py**  
`console_test/tools` の PyQt 可視化ツール。CSI 波形・RSSI・在室/動作しきい値などを扱う。
- **RuView**  
本プロジェクト名の由来となる製品・コンセプト。LT 向けに ESP32-S3 と esp-csi をまとめる。
- **flash**  
マイコンへファームウェアを書き込むこと。`idf.py flash` で実行する。

