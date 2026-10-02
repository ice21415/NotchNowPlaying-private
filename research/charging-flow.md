# 充電流光（0.1.101）

充電且電量未滿時，青綠色流光從螢幕底部中央分成左右兩路，沿底部圓角、側邊和頂部圓角向上，到瀏海左右兩側結束。每 3.2 秒同步循環，持續至 100% 或停止充電。不是將流光高度映射至電量百分比。

`NNPChargingController` 使用獨立、透明、不接收觸控的 window，不需音樂播放，也不取得 key window。插件總開關與「啟用充電流光」控制顯示。電量未知、未充電、已滿或熄屏時隱藏並移除動畫。開啟減少動態效果時改成靜態的左右邊緣提示。動畫由 Core Animation 執行，沒有額外輪詢或逐幀 timer。

電池狀態由 UIDevice 的通知更新：[Apple 電池狀態通知](https://developer.apple.com/documentation/uikit/uidevice/batterystatedidchangenotification)。流光使用可動畫的 [CAShapeLayer strokeStart](https://developer.apple.com/documentation/quartzcore/cashapelayer/strokestart) 與 strokeEnd。

熄屏偵測讀取 Darwin `com.apple.iokit.hid.displayStatus` 通知狀態，參考 [PassBy 的原始實作](https://github.com/giorgioiavicoli/PassBy/blob/master/Tweak.xm)。這是私有通知；讀取失敗且沒有活動 AOD 時隱藏。本功能不主動點亮螢幕，也不延長系統亮屏時間。0.1.100 由 NNPController 傳入已鎖定且處於 Active 的 AOD 顯示狀態，即使 iOS 回報 display off，也會保持充電流光。

## AOD 充電喚醒修正

iOS 17.1.2 本機 SpringBoard 反組譯顯示：`SBUIController ACPowerChanged` 呼叫 `possiblyWakeForPowerStatusChangeWithUnlockSource:`，傳入 unlock source 21；此方法再呼叫鎖屏管理器 `unlockUIFromSource:withOptions:`。裝置日誌顯示充電事件的後續背光喚醒會退出 AOD。不要將 unlock source 21 與背光 source 混用，也不要憑充電狀態攔截所有喚醒。

0.1.100 僅在 armed、locked、Active AOD、已觀察到顯示替代、插件與充電流光均啟用時，略過 source 21 的上述充電喚醒。同時在相同範圍略過 `SBLockScreenBatteryChargingViewController presentWithAnimation:`，避免系統充電畫面蓋過流光。原始電池狀態更新與實際充電流程不變。hook 安裝前檢查實際方法參數與回傳型別；型別不符時不安裝。其他 unlock source、側鍵、點按與 AOD 外的充電仍交給原方法。

裝置測試發現喚醒方法的實際參數 encoding 是 `i`（32-bit int），0.1.100 錯誤要求 `q`，因此保護性檢查拒絕安裝喚醒 hook。0.1.101 將函式指標、replacement 與型別檢查統一為 int；電池畫面 hook 的 BOOL encoding 為 `B`，已確認能正常安裝。

共享 C policy 的測試遍歷喚醒來源與開關／鎖定／AOD 狀態，並檢查 screen off + AOD 可見、100%、停止充電、未知電量與減少功能啟用等顯示邊界。GitHub Actions 的一般版與 AOD 版都執行測試。

## 編譯驗證

已在 WSL 使用 RootHide Theos、iPhoneOS16.5 SDK、Clang 22 與 Theos 的 Darwin linker 編譯一般 arm64e 版本並打包。Windows control 檔案已轉成 LF。使用本機工具鏈時命令為：

```sh
make package THEOS=/home/ice21/roothide-theos \
  THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1 DEBUG=0 STRIP=1 \
  NNP_SAFE_BOOT_TEST=0 TARGET_CC=/usr/bin/clang-22 \
  TARGET_CXX=/usr/bin/clang++-22 TARGET_LD=/usr/bin/clang++-22 \
  ADDITIONAL_LDFLAGS=-fuse-ld=/home/ice21/roothide-theos/toolchain/linux/iphone/bin/ld
```

以上工具路徑為本機路徑，其他環境可依 README 的一般命令建置。Safe-boot 版本不啟動充電控制器。既有 MediaRemote 的 dynamic_lookup linker 警告仍存在。

## 實機驗證待辦

- 電量低於 100% 時，亮屏插入有線／無線充電器：兩路同步由底部向上，約 3 秒循環一次。
- 音樂播放與未播放時均可顯示；點擊、滑動和 Home 手勢正常。
- 99% 到 100%、拔掉充電器、關閉充電開關與插件總開關時立即停止。
- 熄屏停止；重新亮屏且仍在充電時恢復，鎖定畫面也確認可見。
- 開啟／關閉減少動態效果，切換為靜態提示／流光。
- 檢查目標裝置實際圓角與瀏海位置、旋轉及與通知蛇形動畫同時顯示的效果。

未安裝至手機，尚未確認實機視覺效果與耗電。`SOURCE-MANIFEST.csv` 保留最初整理時的來源快照，新增與修改檔案不再與該快照全部一致。
