# 連續環境光亮度（0.1.108）

本版取代先前三段亮度。系統自動亮度關閉也可使用，插件不改系統開關。

只在活動、鎖定 AOD 時，每 5 秒讀取新的 IOKit ambient-light event。有限的 0～200000 lux 才有效，時戳不可缺少、未來或超過 30 秒；無新資料時釋放固定亮度，回到基準。退出 AOD 停止 timer、釋放 HID service / client，以 generation 拒絕舊回呼。

曲線為 `targetNits = 6 + min(lux, 300) × 0.28`。0 / 150 / 300 lux 要求 6 / 48 / 90 nits，超過 300 lux 保持上限。目標變化少於 0.5 nit 時忽略；其餘以六次、間隔 0.15 秒的步進，完成約 0.9 秒漸變。平時沒有逐幀 timer，新目標或退出會取消未完成的步進。每次步進不先清除 override，避免反覆回落到基準。

自動模式直接設定 nits，允許低於原本倍率模式的 30 nit，避免基準與 30 nit 之間突然跳動。關閉自動模式後沿用手動 100～400% 滑桿。

共享 C 測試涵蓋整個 0～300 lux 的線性增量、上下限、無效輸入，以及漸變單調性、端點、不超出範圍。GitHub Actions 的一般版與 AOD 版均執行。

診斷包含 `AODAutomaticBrightnessTargetNits`、`Phase7FixedBrightnessTargetNits`。CoreBrightness 的 `Nits` 在本機為數字字串，已支援解析；但仍可能報告系統基準，不可當成 override 後的物理亮度。`Phase7FixedBrightnessAppliedNits` 來自 `CoreBrightnessFeaturesDisabled.OverrideBrightnessWithFixedNits`，核對套用值，不等同光度計測量。

0.1.107 已由使用者確認環境光亮度會隨遮光變化；此版需再確認連續曲線和漸變的實機感受。亮度策略與微移降低長時間固定發光的負擔，不能保證 OLED 永遠不烙印。

Release 停用 SSH 截圖 probe / experiment，移除舊的每 0.25 秒輪詢與除錯日誌。像素保護及環境光採樣保留。
