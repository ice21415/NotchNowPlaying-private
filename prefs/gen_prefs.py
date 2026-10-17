import plistlib, os, sys

root = sys.argv[1]
res = os.path.join(root, "prefs", "Resources")
os.makedirs(res, exist_ok=True)
NOTE = "com.user.notchnowplaying.preferences.changed"
DOM = "com.user.notchnowplaying"


def group(label="", footer=None):
    d = {"cell": "PSGroupCell", "label": label}
    if footer:
        d["footerText"] = footer
    return d


def switch(key, label, default, symbol=None, tint=None, **extra):
    d = {"cell": "PSSwitchCell", "defaults": DOM, "key": key, "label": label,
         "default": bool(default), "PostNotification": NOTE}
    if symbol:
        d["symbol"] = symbol
        d["tint"] = tint or "blue"
    d.update(extra)
    return d


def segment(label, key, default, values, titles, footer=None, **extra):
    """A labelled group holding one segmented control with fixed steps."""
    cell = {"cell": "PSSegmentCell", "defaults": DOM, "key": key, "label": label,
            "default": default, "validValues": values, "validTitles": titles,
            "PostNotification": NOTE}
    cell.update(extra)
    return [group(label, footer), cell]


def slider(key, label, default, lo, hi, **extra):
    d = {"cell": "PSSliderCell", "defaults": DOM, "key": key, "label": label,
         "default": default, "min": lo, "max": hi, "showValue": True, "PostNotification": NOTE}
    d.update(extra)
    return d


def link(label, page, symbol=None, tint=None, controller="NNPPrefsListController"):
    d = {"cell": "PSLinkCell", "label": label, "detail": controller, "isController": True,
         "plistName": page}
    if symbol:
        d["symbol"] = symbol
        d["tint"] = tint or "blue"
    return d


def value(label, getter):
    return {"cell": "PSTitleValueCell", "label": label, "get": getter}


def flat(items):
    out = []
    for i in items:
        out.extend(i if isinstance(i, list) else [i])
    return out


def page(name, title, items):
    items = flat(items)
    with open(os.path.join(res, name + ".plist"), "wb") as f:
        plistlib.dump({"title": title, "items": items}, f, fmt=plistlib.FMT_XML)


page("Root", "瀏海音樂播放器", [
    group("快速開關", "「AOD 顯示」會在鎖定後以黑底持續顯示播放器；詳細選項在「鎖定畫面 AOD」。"),
    switch("Enabled", "啟用播放器", True, "music.note", "pink"),
    switch("ExperimentalLockedVisible", "鎖定後 AOD 顯示", False, "moon.stars.fill", "indigo"),
    group("設定"),
    link("播放器", "Player", "play.rectangle.fill", "pink"),
    link("鎖定畫面 AOD", "AOD", "lock.display", "indigo"),
    link("通知與充電提示", "Alerts", "bolt.fill", "orange"),
    link("乘車碼（MeN Go）", "Mengo", "qrcode", "teal"),
    group("用量"),
    {"cell": "PSLinkCell", "label": "AOD 耗電量", "detail": "NNPPowerController", "isController": True,
     "symbol": "battery.75percent", "tint": "green"},
    group(),
    link("進階與診斷", "Advanced", "gearshape.fill", "gray"),
])

page("Player", "播放器", [
    group("何時顯示"),
    switch("SpotifyOnly", "只顯示 Spotify 播放內容", True, "waveform", "green"),
    switch("ShowWhileUnlocked", "解鎖時顯示", True, "lock.open.fill", "blue"),
    switch("ShowOnLockScreen", "鎖定畫面顯示", True, "lock.fill", "indigo"),
    switch("HideWhenPaused", "暫停時隱藏", True, "pause.fill", "gray"),
    group("顯示的資訊", "歌手名稱下方可顯示目前電量；充電時會加上閃電圖示。橫放時保留所選資訊並重新排列。"),
    switch("ShowArtwork", "專輯封面", True, "photo.fill", "pink"),
    switch("ShowArtist", "歌手名稱", True, "person.fill", "blue"),
    switch("ShowProgress", "播放進度", True, "slider.horizontal.below.rectangle", "orange"),
    switch("ShowClock", "時鐘", True, "clock.fill", "teal"),
    switch("ShowBattery", "電量", True, "battery.100", "green"),
    switch("ShowNextTrack", "下一首預覽", True, "forward.fill", "purple"),
    switch("ShowLyrics", "目前歌詞", True, "text.quote", "red"),
    segment("封面大小", "ArtworkSize", 40, [32, 40, 48, 56], ["小", "標準", "大", "特大"],
            "實際尺寸仍會依螢幕寬度限制。"),
    segment("封面圓角", "CornerRadius", 9, [4, 9, 16], ["小", "標準", "大"]),
    segment("歌名字級", "TextSize", 14, [12, 14, 16, 18], ["小", "標準", "大", "特大"]),
    segment("進度條粗細", "ProgressHeight", 3, [2, 3, 4, 6], ["細", "標準", "粗", "特粗"]),
    segment("歌詞同步", "LyricsSyncOffsetMilliseconds", 100, [-300, -100, 0, 100, 300],
            ["−300", "−100", "0", "+100", "+300"],
            "單位為毫秒。正值提早顯示歌詞，負值延後顯示，預設 +100。Spotify 開啟歌詞頁時才會讀取歌詞。"),
])

page("AOD", "鎖定畫面 AOD", [
    group("AOD 顯示",
          "鎖定後以黑底顯示播放器。這是插件模擬的 AOD，不是系統原生 AOD。也需要開啟「鎖定畫面顯示播放器」。"),
    switch("ExperimentalLockedVisible", "啟用 AOD 顯示", False, "moon.stars.fill", "indigo"),
    switch("AODIdleDisplayEnabled", "無音樂時顯示時鐘／日期／電量", True, "clock.fill", "teal"),
    group("顯示時間", "關閉「持續顯示」時，AOD 在設定時間後結束；解鎖或音樂停止約 15 秒後也會結束。"),
    switch("ExperimentalUnlimitedDuration", "持續顯示（不限時）", False, "infinity", "orange"),
    segment("時間上限", "ExperimentalMaxDuration", 30, [10, 15, 30, 45, 60],
            ["10 秒", "15 秒", "30 秒", "45 秒", "60 秒"],
            dependsOn="ExperimentalUnlimitedDuration", dependsEnabledWhen=False, dependsDefault=False),
    group("亮度", "自動亮度依環境光平滑調整，只影響 AOD，不更改系統設定。關閉後才使用手動亮度。"),
    switch("AODAutomaticBrightnessEnabled", "依環境光調整", True, "sun.max.fill", "yellow"),
    segment("手動亮度", "AODBrightnessMultiplier", 100, [100, 150, 200, 300, 400],
            ["100%", "150%", "200%", "300%", "400%"],
            dependsOn="AODAutomaticBrightnessEnabled", dependsEnabledWhen=False, dependsDefault=True),
    group("省電與感測", "遮住瀏海感測區或螢幕朝下時熄屏，移開或拿起後恢復。不使用相機。橫向版面僅在手機橫放時使用。"),
    switch("AODPocketModeEnabled", "遮蔽／朝下自動熄屏", True, "hand.raised.fill", "red"),
    switch("AODLandscapeEnabled", "橫向版面", True, "iphone.landscape", "blue"),
    group("像素保護", "AOD 期間會定時微幅移動內容，並讓亮度每幾分鐘緩慢起伏，降低烙印風險。自動啟用，無法保證完全避免。"),
])

page("Alerts", "通知與充電提示", [
    group("AOD 通知提醒",
          "只在鎖定且 AOD 顯示時生效。通知到達時，光點沿螢幕邊緣繞行並短暫顯示 App 圖示與內容；通知仍保留在系統通知中心。減少動態效果開啟時改用靜態邊框。"),
    switch("NotificationSnakeWakeEnabled", "蛇形光效通知", False, "bell.badge.fill", "red"),
    group("充電流光",
          "充電時，流光從底部中央沿邊緣向上，充滿或停止充電時結束。AOD 顯示中會取代系統充電喚醒與畫面。不需播放音樂。"),
    switch("ChargingAnimationEnabled", "充電流光", True, "bolt.fill", "orange"),
])

page("Mengo", "乘車碼（MeN Go）", [
    group("乘車碼入口",
          "首次請開啟 MeN Go，登入並顯示一次乘車碼。音樂 AOD 右下角會出現 QR 按鈕，點按後取得最新碼並暫時提高亮度；乘車碼畫面 90 秒後自動關閉。登入失效時需回 MeN Go 登入。"),
    switch("MengoEnabled", "顯示乘車碼入口", True, "qrcode", "teal"),
])

page("Advanced", "進階與診斷", [
    segment("進度更新間隔", "ProgressUpdateInterval", 1, [0.5, 1, 2, 5], ["0.5 秒", "1 秒", "2 秒", "5 秒"],
            "播放器更新進度的間隔。間隔越短越流暢，也越耗電。預設 1 秒。"),
    group("診斷",
          "插件會在手機本機儲存執行紀錄以排查問題。通知喚醒追蹤只記錄來源 App、鎖定／AOD 狀態與背光來源，不記錄通知內容；測試後請關閉。"),
    switch("NotificationWakeTraceEnabled", "記錄通知喚醒事件", False, "ladybug.fill", "gray"),
    group("重設"),
    {"cell": "PSButtonCell", "label": "還原所有設定", "action": "resetAllSettings"},
    group("關於"),
    value("版本", "versionString:"),
])

page("Power", "AOD 耗電量", [
    group("AOD 使用時間"),
    value("總時間", "valueTotalTime:"),
    value("無音樂時鐘", "valueIdleTime:"),
    value("音樂播放", "valueMediaTime:"),
    group("AOD 期間耗電",
          "數值為整支手機的耗電（含螢幕與系統），並非插件單獨耗電；以放電中的 AOD 時段估算，資料量少時僅供參考。"),
    value("平均功率", "valueAveragePower:"),
    value("消耗電量", "valueUsedPercent:"),
    value("每小時消耗", "valuePerHour:"),
    value("AOD 期間充電時間", "valueCharging:"),
    group("電池"),
    value("目前電量", "valueBattery:"),
    value("最大容量", "valueHealth:"),
    value("充電循環", "valueCycles:"),
    value("溫度", "valueTemperature:"),
    group(),
    {"cell": "PSButtonCell", "label": "清除統計資料", "action": "clearStats"},
])

info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleExecutable": "NotchNowPlayingPrefs",
    "CFBundleIdentifier": "com.user.notchnowplaying.prefs",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "NotchNowPlayingPrefs",
    "CFBundlePackageType": "BNDL",
    "CFBundleShortVersionString": "0.1.141",
    "CFBundleVersion": "0.1.141",
    "NSPrincipalClass": "NNPRootListController",
}
with open(os.path.join(res, "Info.plist"), "wb") as f:
    plistlib.dump(info, f, fmt=plistlib.FMT_XML)

loader = {"entry": {"bundle": "NotchNowPlayingPrefs", "cell": "PSLinkCell",
                    "detail": "NNPRootListController", "isController": True,
                    "label": "瀏海音樂播放器"}}
p = os.path.join(root, "layout", "Library", "PreferenceLoader", "Preferences", "NotchNowPlaying.plist")
with open(p, "wb") as f:
    plistlib.dump(loader, f, fmt=plistlib.FMT_XML)
print("ok")
