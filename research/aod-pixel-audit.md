# AOD 像素保護檢查（0.1.105）

## 發現與修正

- 舊版位移使用 UIKit scale，但 iPhone 12 mini 的渲染比例與 nativeBounds 比例不同。現在按 nativeBounds / bounds 分別換算兩軸，位移單位為面板像素。
- 舊版每 30 秒隨機位移 ±3，可能反覆選到少數位置。現在每 30 秒依序走過 ±6 的 13 × 13 網格，169 次才重複，且每次兩軸都改變。
- 通知 snake 原本用反向 transform 抵消位移，現在取消抵消，跟播放器所有後代一起移動。
- 充電流光是獨立的 CoverSheet 子 view，現在使用相同位移；短暫充電百分比是其子 view，也跟著移動。
- 舊版停止音樂時可能取消位移 timer，但 AOD 的通知或充電元素仍存在。現在 timer 的生命週期跟活動、鎖定的 AOD 一致。
- 小幅位移無法讓大型封面或實心圖樣的中央像素休息。每次位移在播放器、狀態列鏡像及充電根圖層套用 0.3 秒 opacity 動畫，前 0.21 秒為零，後 0.09 秒恢復。底層黑色遮罩保持固定。這會有短暫可見的淡黑效果，不是面板校正或 OLED 修復。
- AOD 像素保護自動啟用，移除關閉開關。退出 AOD 停止 timer 並移除保護動畫；充電 view、shape layers、百分比及其一次性 timer 均釋放。

## 可見元素覆蓋

| 元素 | 位移／休息的根圖層 |
| --- | --- |
| 封面、歌曲、歌手、時鐘、電池、歌詞、播放時間、進度條 | NNPView.layer |
| 通知圖示、未讀數、通知卡、snake 與 finish 圖層 | NNPView.layer |
| 狀態列頂部播放器及通知鏡像 | statusBarPlayerView.layer |
| 充電左右流光及短暫百分比 | NNPChargingView.layer |
| 全螢幕黑色遮罩與透明觸控層 | 不發亮，無需位移 |

## 驗證與限制

共享 C 測試檢查全部 169 個位置、沒有重複、兩軸每次改變、範圍與循環邊界；本機與 GitHub Actions 都執行。裝置診斷記錄三個根圖層的實際 model transform，並在休息動畫開始後 0.1 秒抽查 presentationLayer.opacity，避免只看計時器指令。`AODPlayerRestObserved`、`AODMirrorRestObserved`、`AODChargingRestObserved` 為抽查結果；圖層不存在時不能推論已成功。

充電百分比在開始顯示充電流光或電量改變時出現，7.5 秒後開始淡出，8 秒後移除並釋放。`ChargingPercentageAllocated` 記錄生命週期。

以上能檢查插件圖層的移動與暫停發光，不能量測面板每個子像素的老化、保證沒有永久烙印，也不能保護使用者顯示的系統控制項。重新繪製相同像素值不會消除 OLED 老化。亮度、使用時間、面板狀態仍會影響風險；Apple 亦說明 OLED 長期使用可能產生影像殘留或烙印：https://support.apple.com/en-ie/109039 。
