# AOD 環境光亮度（0.1.107）

系統自動亮度可以維持關閉。插件不寫入系統自動亮度設定，也不以 UIScreen.brightness 假裝成環境光。

`NNPAODAmbientLight` 在已鎖定、活動 AOD 且開啟「依環境光調整」時，每 5 秒在獨立序列 queue 讀取 IOKit ambient-light event。不是每幀讀取，不修改感測器屬性或取得裝置獨占權。離開 AOD 時停止 timer、釋放 HID service / client，已排隊的回呼以 generation 拒絕。讀值需為有限的 0～200000 lux，event 時戳不可缺少、未來或超過 30 秒。

iOS 17.1.2 本機 CoreBrightness `-[CBALSNode copyEvent]` 的靜態證據確認 vendor usage 0xff00 / 4，以及 ambient event type 12。服務用 `IOHIDEventSystemClientCopyServices` 列舉並篩選。事件 level 使用欄位 12 << 16；實機有效與更新頻率需以診斷核對。API、權限、服務或新事件不可用時降回 100%，不使用過期值提高亮度。

三段亮度有遲滯：

| 目前亮度 | 環境光條件 | 新亮度 |
| --- | --- | --- |
| 100% | 小於 15 lux | 100% |
| 100% | 15～149 lux | 150% |
| 100% 或 150% | 至少 150 lux | 200% |
| 150% | 至多 8 lux | 100% |
| 200% | 9～79 lux | 150% |
| 200% | 至多 8 lux | 100% |
| 200% | 至少 80 lux | 200% |

100% 釋放固定 nits override，使用既有 AOD 基準。150% / 200% 使用現有 BackBoardServices 路徑要求 45 / 60 nits；實際讀回可能依硬體狀態不同。只在分段變化時更新面板，避免每次採樣重設。喚醒／解鎖沿用現有 nits cleanup。關閉此功能時仍可使用原有手動亮度滑桿。

共享 C 測試覆蓋上下段邊界、遲滯、無效數值與亮度上限。裝置診斷：`AODAmbientSensorActive`、`AODAmbientSampleValid`、`AODAmbientLux`、`AODAmbientSampleAge`、`AODAutomaticBrightnessEffectiveMultiplier`，以及既有 nits target / readback。實機測試需在系統自動亮度關閉時，以遮住／照亮瀏海感測區核對讀值與分段是否變化；不能只看預期 multiplier。

0.1.106 實機確認系統自動亮度關閉時仍能讀到新事件，例如 454 / 651 lux、事件年齡小於 1 ms。亦發現 `aodBrightnessMultiplier` 的預設 setter 為 `setAodBrightnessMultiplier:`，先前手動實作誤用 `setAODBrightnessMultiplier:`，導致 property assignment 僅寫入 synthesized ivar，未呼叫原生 atomic 與面板更新。0.1.107 更正命名；亮度驗證必須同时核對有效 multiplier、native atomic、nits target 及面板 nits readback，不能以計算結果宣告成功。
