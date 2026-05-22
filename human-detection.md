# PCだけで人体検知（ESP32なし・WiFi RSSIのみ）

ESP32-S3 を使わず、**手元のノートPCのWiFi電波強度（RSSI）だけ**で人の在室・動きを検知する手順。
RuView の [issue #36（Windows WiFi Sensing Quick Start）](https://github.com/ruvnet/RuView/issues/36) が元ネタ。
追加ハード $0・WiFiにつながっているだけでOK。

> #36 の本家チュートリアルは **Windows（`netsh`）専用**。ただし RuView 本体には
> **Linux 用 (`LinuxWifiCollector`)** と **macOS 用** のコレクタも入っているので、
> このガイドでは **Linux（Ubuntu, このマシン）を主**に、Windows/macOS の差分も併記する。

---

## できること / できないこと

| | RSSIのみ（PCだけ） |
|---|---|
| ✅ 在室検知 (presence) | RSSIの**分散**がしきい値を超えるか |
| ✅ 動き検知 (motion) | スペクトルの**動き帯域(0.5–3Hz)パワー**で静止/活動 |
| ❌ 呼吸・心拍 | sub-dBm分解能が必要 → ESP32 CSI（#34）が要る |
| ❌ 姿勢推定・壁越し | RSSIは粗すぎる |

**仕組み**: 人がPCとルーターの間で動くと電波が遮られ、RSSIが 3〜10dBm 揺れる。
その揺れ（分散・動き帯域パワー）を特徴量にして在室/動作を判定する。
パイプラインは `RSSI収集 → 特徴抽出(FFT/バンドパワー) → ルールベース分類`。

**制約**: RSSIは 1dBm 刻みで粗い・サンプリングは実用上 ~2Hz（Windowsのnetsh）〜10Hz（Linux）。
受信機は1台のみ・見通し範囲が中心。

---

## OS別のRSSI取得方法

| OS | コレクタ | データ源 |
|----|---------|---------|
| **Linux** (このマシン) | `LinuxWifiCollector` | `/proc/net/wireless` ＋ `iw dev <iface> station dump` |
| **Windows** | `WindowsWifiCollector` | `netsh wlan show interfaces` |
| **macOS** | macOSコレクタ | CoreWLAN（`src/sensing/mac_wifi.swift`） |

---

## 0. 準備

```bash
export PROJECT_ROOT=/home/pcafe/projects/pcafe/iotlt_2026_06_ruview   # 自分の環境に合わせる

# RuView 本体（まだ無ければ）
cd ${PROJECT_ROOT}
git clone https://github.com/ruvnet/RuView.git    # 既にあるならスキップ
cd RuView

# Python 環境（numpy / scipy が必要）。uv で venv を作る例:
uv venv
source .venv/bin/activate
uv pip install numpy scipy
```

> 以降のコマンドは **RuView リポジトリのルート** で実行する。
> RSSI パイプラインは `archive/v1/src/sensing/` にあり、`PYTHONPATH=archive/v1` を付けて
> `from src.sensing... import ...` で読み込む（#36 と同じ流儀）。

---

## 1. Linux（Ubuntu）での手順 ★このマシン

### 1-1. 無線インターフェイス名を確認
```bash
cat /proc/net/wireless        # 先頭に出るのが無線IF（このマシンは wlp3s0）
# または: ls /sys/class/net/ / iw dev
```
以降の `wlp3s0` は自分のIF名に置き換える。

### 1-2. RSSIを1回だけ取得（動作確認）
```bash
PYTHONPATH=archive/v1 python3 -c "
from src.sensing.rssi_collector import LinuxWifiCollector
c = LinuxWifiCollector(interface='wlp3s0')
s = c.collect_once()
print(f'RSSI: {s.rssi_dbm} dBm, Quality: {s.link_quality:.0%}')
"
```

### 1-3. フルパイプライン（15秒収集して判定）
```bash
PYTHONPATH=archive/v1 python3 -c "
import time
from src.sensing.rssi_collector import LinuxWifiCollector
from src.sensing.feature_extractor import RssiFeatureExtractor
from src.sensing.classifier import PresenceClassifier

collector  = LinuxWifiCollector(interface='wlp3s0', sample_rate_hz=10.0)
extractor  = RssiFeatureExtractor(window_seconds=15.0)
classifier = PresenceClassifier(presence_variance_threshold=0.3, motion_energy_threshold=0.05)

collector.start(); print('15秒 収集中...（途中で歩き回ると反応する）'); time.sleep(15); collector.stop()
samples  = collector.get_samples()
features = extractor.extract(samples)
result   = classifier.classify(features)

print(f'Samples:   {len(samples)}')
print(f'RSSI mean: {features.mean:.1f} dBm')
print(f'Variance:  {features.variance:.4f}')
print(f'Motion:    {features.motion_band_power:.4f}')
print(f'Verdict:   {result.motion_level.value} ({result.confidence:.0%})')
"
```

### 1-4. ライブモニタ（3秒ごとに判定を表示）
`tests/integration/live_sense_monitor.py` は Windows固定なので、Linux版を作って動かす:

```bash
cat > /tmp/rssi_live.py <<'PY'
import sys, time
sys.path.insert(0, 'archive/v1')
from src.sensing.rssi_collector import LinuxWifiCollector
from src.sensing.feature_extractor import RssiFeatureExtractor
from src.sensing.classifier import PresenceClassifier

IFACE = 'wlp3s0'   # ← 自分のIFに変更
collector  = LinuxWifiCollector(interface=IFACE, sample_rate_hz=10.0)
extractor  = RssiFeatureExtractor(window_seconds=15.0)
classifier = PresenceClassifier(presence_variance_threshold=0.3, motion_energy_threshold=0.05)

collector.start()
print('baseline収集中... 15秒後に歩き回って反応を見る。Ctrl+Cで停止')
try:
    while True:
        time.sleep(3)
        samples = collector.get_samples()
        if len(samples) < 10:
            print(f'  buffering... ({len(samples)})'); continue
        f = extractor.extract(samples)
        r = classifier.classify(f)
        print(f"[{time.strftime('%H:%M:%S')}] {r.motion_level.value:8s} "
              f"conf={r.confidence:.0%}  var={f.variance:.4f}  motion={f.motion_band_power:.4f}")
except KeyboardInterrupt:
    collector.stop(); print('\nstopped.')
PY
PYTHONPATH=archive/v1 python3 /tmp/rssi_live.py
```

> `iw dev <iface> station dump` は root が要ることがあるが、RSSI自体は `/proc/net/wireless`
> から root なしで読める（iw が失敗しても自動でフォールバックする）。

---

## 2. Windows での手順（#36 本家・verbatim）

```powershell
git clone https://github.com/ruvnet/RuView.git
cd RuView
pip install numpy scipy

# WiFi接続を確認（State: connected と Signal: % を見る）
netsh wlan show interfaces
```

1回サンプル:
```powershell
python -c "import sys; sys.path.insert(0,'archive/v1'); from src.sensing.rssi_collector import WindowsWifiCollector; c=WindowsWifiCollector(interface='Wi-Fi'); s=c.collect_once(); print(f'RSSI: {s.rssi_dbm} dBm, Quality: {s.link_quality:.0%}')"
```

ライブモニタ（Windowsはこのまま使える）:
```powershell
$env:PYTHONPATH = "archive/v1"
python archive/v1/tests/integration/live_sense_monitor.py   # Ctrl+C で停止、3秒ごと表示
```

CommodityBackend API（共通の使い方）:
```python
import sys; sys.path.insert(0, 'archive/v1')
from src.sensing.backend import CommodityBackend
from src.sensing.rssi_collector import WindowsWifiCollector   # Linuxなら LinuxWifiCollector

backend = CommodityBackend(collector=WindowsWifiCollector(interface="Wi-Fi", sample_rate_hz=2.0))
print(backend.get_capabilities())
backend.start()
r = backend.get_result()
print(r.motion_level, r.confidence)
backend.stop()
```

> Windowsの `netsh` は遅いので `sample_rate_hz=2.0`・`presence_variance_threshold=0.3` 推奨。

---

## 3. macOS の注意
- コレクタは CoreWLAN を使う Swift ユーティリティ（`archive/v1/src/sensing/mac_wifi.swift`）経由。
- ビルド/権限まわりが必要なことがある。基本の流れ（clone → numpy/scipy → パイプライン）は Linux と同じで、
  コレクタを macOS 用に差し替える。インターフェイス名は通常 `en0`。

---

## 4.（任意）WebSocketダッシュボード
リアルタイムにブラウザ等へ流すなら、WebSocketサーバが使える:

```bash
uv pip install websockets
PYTHONPATH=archive/v1 python3 archive/v1/src/sensing/ws_server.py   # ws://localhost:8765
```
（ESP32がUDP :5005にいればそちらを優先。無ければRSSI/シミュレータにフォールバック）

---

## 5. テスト・検証

```bash
# 信号処理パイプラインが本物かの決定論的検証（RESULT: PASS が出ればOK）
./verify
# もしくは
python3 archive/v1/data/proof/verify.py

# ユニットテスト（WiFi不要・36件）
PYTHONPATH=archive/v1 python3 -m pytest archive/v1/tests/unit/test_sensing.py -v -o "addopts="

# 統合テスト（接続済みWiFiが必要・Windows向け）
PYTHONPATH=archive/v1 python3 -m pytest archive/v1/tests/integration/test_windows_live_sensing.py -v -o "addopts=" -s
```

---

## 6. 限界とコツ
- **しきい値はキャリブレーションが要る**: 起動後しばらく静止して baseline を作り、`presence_variance_threshold` /
  `motion_energy_threshold` を環境に合わせて調整。
- **PCとルーターの“間”を横切る**と一番反応する（フレネルゾーンを遮るため）。
- **RSSIは粗い**: 「いる/いない・動いた」までが現実的。呼吸・心拍・姿勢が欲しければ ESP32 CSI（#34）へ。
- ノートPC1台で完結＝**$0**。まず「人がいるか」を知りたいだけなら、これで十分なことが多い。

---

## 関連
- ESP32-S3 + CSI で生波形〜呼吸/心拍まで見たい場合 → リポジトリ直下の `README.md`（ESP32構成）と RuView #34
- このガイドの元ネタ: RuView issue #36（Windows WiFi Sensing Quick Start）
