# 充電流光（0.1.99）

充電且電量未滿時，青綠色流光從螢幕底部中央分成左右兩路，沿底部圓角、側邊和頂部圓角向上，到瀏海左右兩側結束。每 3.2 秒同步循環，持續至 100% 或停止充電。不是將流光高度映射至電量百分比。

`NNPChargingController` 使用獨立、透明、不接收觸控的 window，不需音樂播放，也不取得 key window。插件總開關與「啟用充電流光」控制顯示。電量未知、未充電、已滿或熄屏時隱藏並移除動畫。開啟減少動態效果時改成靜態的左右邊緣提示。動畫由 Core Animation 執行，沒有額外輪詢或逐幀 timer。

電池狀態由 UIDevice 的通知更新：[Apple 電池狀態通知](https://developer.apple.com/documentation/uikit/uidevice/batterystatedidchangenotification)。流光使用可動畫的 [CAShapeLayer strokeStart](https://developer.apple.com/documentation/quartzcore/cashapelayer/strokestart) 與 strokeEnd。

熄屏偵測只讀取 Darwin `com.apple.iokit.hid.displayStatus` 通知狀態，參考 [PassBy 的原始實作](https://github.com/giorgioiavicoli/PassBy/blob/master/Tweak.xm)。這是私有通知，仍需在目標 iOS 實機確認；讀取失敗時隱藏。本功能不主動點亮螢幕，也不延長系統亮屏時間。實驗性 AOD 將面板維持可見但系統仍回報 display off 時，充電流光仍會暫停。

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
