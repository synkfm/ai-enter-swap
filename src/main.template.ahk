#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName AI Enter Swap
;@Ahk2Exe-SetDescription AIチャットの入力欄で Enter=改行 / Shift+Enter=送信 にする（非公式ツール）
;@Ahk2Exe-SetVersion 2.0.0
;@Ahk2Exe-SetProductVersion 2.0.0
;@Ahk2Exe-SetOrigFilename AIEnterSwap.exe
;@Ahk2Exe-SetMainIcon src\icon.ico

; =====================================================================
;  AI Enter Swap（旧名 Claude Enter Swap）
;  AIチャット（Claude / ChatGPT / Codex / Gemini / Copilot）を使っているときだけ
;    Enter        → 改行
;    Shift+Enter  → 送信
;  に入れ替える。対象はトレイメニューで1つずつオン／オフできる。
;
;  変換中の Enter も裏では Shift+Enter として IME に届くため、
;  IME 側を「変換中の Shift+Enter ＝ 確定」に設定しておく必要がある。
;  その設定を、Google日本語入力 / Microsoft IME の両方について自動で行う。
; =====================================================================

APP_NAME    := "AI Enter Swap"
APP_VERSION := "2.0.0"
DATA_DIR    := A_AppData "\AIEnterSwap"
SETTINGS    := DATA_DIR "\settings.ini"
STARTUP_LNK := A_Startup "\" APP_NAME ".lnk"
BROWSERS    := ",chrome.exe,msedge.exe,firefox.exe,brave.exe,vivaldi.exe,opera.exe,"
; ターミナル（黒い画面）では Shift+Enter が Enter と区別されないことが多いので、対象にしない
CONSOLE_CLASSES := ",ConsoleWindowClass,CASCADIA_HOSTING_WINDOW_CLASS,PseudoConsoleWindow,mintty,VirtualConsoleClass,"

; 旧名（Claude Enter Swap 1.x）からの引っ越し用
OLD_EXE         := "ClaudeEnterSwap.exe"
OLD_DATA_DIR    := A_AppData "\ClaudeEnterSwap"
OLD_STARTUP_LNK := A_Startup "\Claude Enter Swap.lnk"

; 対象のAI
;   exes  … デスクトップアプリのプロセス名
;   hosts … ブラウザで開いたときのアドレス（ドメイン）
;   Claude のブラウザ版だけは、従来どおりタブのタイトルで判定する
TARGETS := [
    {key: "claude",  label: "Claude（アプリ・ブラウザ）",  exes: ",claude.exe,",     hosts: ""},
    ; ChatGPT のデスクトップアプリは Codex と1つにまとまっている（プロセス名 ChatGPT.exe、旧Codexアプリは Codex.exe）
    {key: "chatgpt", label: "ChatGPT / Codex（アプリ・ブラウザ）", exes: ",chatgpt.exe,codex.exe,", hosts: "^(www\.)?chatgpt\.com$|^chat\.openai\.com$"},
    {key: "gemini",  label: "Gemini（アプリ・ブラウザ）",  exes: ",gemini.exe,",     hosts: "^gemini\.google\.com$"},
    {key: "copilot", label: "Copilot（アプリ・ブラウザ）", exes: ",copilotapp.exe,", hosts: "^copilot\.microsoft\.com$|^(www\.)?copilot\.com$"},
]
targetOn := Map()

; --- Google日本語入力 ---
GIME_CFG    := EnvGet("USERPROFILE") "\AppData\LocalLow\Google\Google Japanese Input\config1.db"
GIME_BACKUP := DATA_DIR "\google-ime-config1.db.backup"
GIME_STATES := ["Composition", "Conversion", "Suggestion", "Prediction"]

; --- Microsoft IME ---
MSIME_ROOT   := "HKCU\Software\Microsoft\IME\15.0\IMEJP"
MSIME_CUSTOM := MSIME_ROOT "\StyleList\Custom"
MSIME_LEGACY := "HKCU\Software\Microsoft\Input\TSF\Tsf3Override\{03b5835f-f03c-411b-9ce2-aa23e1171e36}"
MSIME_CUSTOM_BACKUP := DATA_DIR "\msime-custom.reg.backup"

; 開発用テスト（本物の設定には触れない）
;   main.ahk --selftest-gime 入力 出力   … Google日本語入力の設定ファイルのコピーを書き換える
;   main.ahk --selftest-msime 入力 出力  … Microsoft IME のキー表（16進）を書き換える
if (A_Args.Length = 3 && SubStr(A_Args[1], 1, 10) = "--selftest") {
    try {
        if (A_Args[1] = "--selftest-gime") {
            buf := FileRead(A_Args[2], "RAW")
            fields := PbParse(buf)
            style := PbGetVarint(fields, 41, -1)
            table := PbGetString(buf, fields, 42)
            newTable := GimePatchKeymap(style = 0 && table != "" ? table : GimeMsimeKeymap())
            out := PbRebuild(buf, fields, Map(41, PbVarintField(41, 0), 42, PbBytesField(42, newTable)))
            f := FileOpen(A_Args[3], "w"), f.RawWrite(out), f.Close()
        } else {
            hex := Trim(FileRead(A_Args[2]))
            FileAppend(MsimePatchHex(hex), A_Args[3])
        }
        ExitApp(0)
    } catch as e {
        FileAppend("ERROR: " e.Message "`n", "*")
        ExitApp(1)
    }
}

enabled := true
upgraded := MigrateFromOldName()
DirCreate(DATA_DIR)
WarnIfTempDir()
LoadTargets()
SetupTray()
if upgraded
    ShowUpgradeNotice()
FirstRunCheck()

; ---------------------------------------------------------------------
;  キーの入れ替え（対象のAIが前面にあるときだけ有効）
; ---------------------------------------------------------------------
#HotIf IsTargetActive()
$Enter::Send "+{Enter}"
$NumpadEnter::Send "+{Enter}"
$+Enter::Send "{Enter}"
$+NumpadEnter::Send "{Enter}"
#HotIf

IsTargetActive(*) {
    global enabled, BROWSERS, CONSOLE_CLASSES, TARGETS, targetOn
    if !enabled
        return false
    try {
        hwnd := WinExist("A")
        if InStr(CONSOLE_CLASSES, "," WinGetClass(hwnd) ",")
            return false
        exe := StrLower(WinGetProcessName(hwnd))
        for t in TARGETS
            if targetOn[t.key] && t.exes != "" && InStr(t.exes, "," exe ",")
                return true
        if !InStr(BROWSERS, "," exe ",")
            return false

        ; claude.ai のタブのタイトルは「Claude」または「(会話名) - Claude」
        title := WinGetTitle(hwnd)
        byTitle := targetOn["claude"] && RegExMatch(title, "(^| - )Claude( - | と|$)") > 0
        needUrl := false
        for t in TARGETS
            if targetOn[t.key] && t.hosts != ""
                needUrl := true
        if !(byTitle || needUrl)
            return false

        info := BrowserInfo(hwnd, title, needUrl)
        if info.inAddressBar        ; アドレス欄で Enter を押したときは入れ替えない
            return false
        if byTitle
            return true
        for t in TARGETS
            if targetOn[t.key] && t.hosts != "" && info.host != "" && RegExMatch(info.host, t.hosts)
                return true
    }
    return false
}

; ---------------------------------------------------------------------
;  ブラウザのアドレス欄を読む（Windows の「UI オートメーション」という
;  読み上げソフトなどが使う仕組みで、アドレス欄の文字を読むだけ）
;    host         … 開いているページのドメイン（例: chatgpt.com）
;    inAddressBar … いまアドレス欄に文字を打っているところか
;  ドメインは「ウィンドウ＋タブのタイトル」ごとに覚えておき、毎回は読まない
; ---------------------------------------------------------------------
BrowserInfo(hwnd, title, needUrl) {
    static cache := Map()
    res := {host: "", inAddressBar: false}
    edit := 0
    try {
        uia := UiaInit()
        edit := UiaAddressBar(uia, hwnd)
        if !edit
            return res
        ComCall(8, uia, "Ptr*", &focused := 0)                      ; GetFocusedElement
        if focused {
            ComCall(3, uia, "Ptr", focused, "Ptr", edit, "Int*", &same := 0)  ; CompareElements
            ObjRelease(focused)
            if same {
                res.inAddressBar := true
                return res
            }
        }
        if !needUrl
            return res
        k := hwnd "|" title
        if cache.Has(k) {
            res.host := cache[k]
            return res
        }
        r := Buffer(24, 0)
        ComCall(10, edit, "Int", 30045, "Ptr", r)                  ; GetCurrentPropertyValue(Value)
        url := ""
        if NumGet(r, "UShort") = 8 {                                ; VT_BSTR
            p := NumGet(r, 8, "Ptr")
            url := StrGet(p)
            DllCall("OleAut32\SysFreeString", "Ptr", p)
        }
        host := StrLower(RegExReplace(url, "^[a-zA-Z][a-zA-Z0-9+.\-]*://"))
        host := RegExReplace(host, "[/?#:].*$")
        if cache.Count > 200
            cache.Clear()
        cache[k] := host
        res.host := host
    } finally {
        if edit
            ObjRelease(edit)
    }
    return res
}

UiaInit() {
    static uia := 0
    if !uia
        uia := ComObject("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    return uia
}

; ウィンドウの中で最初に見つかる入力欄（ブラウザではアドレス欄）。使い終わったら ObjRelease する
UiaAddressBar(uia, hwnd) {
    static cond := 0
    if !cond {
        v := Buffer(24, 0)
        NumPut("UShort", 3, v), NumPut("Int", 50004, v, 8)        ; VT_I4, ControlType = Edit
        ComCall(23, uia, "Int", 30003, "Ptr", v, "Ptr*", &cond)     ; CreatePropertyCondition
    }
    ComCall(6, uia, "Ptr", hwnd, "Ptr*", &root := 0)              ; ElementFromHandle
    edit := 0
    try ComCall(5, root, "Int", 4, "Ptr", cond, "Ptr*", &edit)      ; FindFirst(子孫から)
    finally ObjRelease(root)
    return edit
}

; ---------------------------------------------------------------------
;  対象のAI（設定ファイルに保存）
; ---------------------------------------------------------------------
LoadTargets() {
    global SETTINGS, TARGETS, targetOn
    ; 1.x から更新した人は、今までどおり Claude だけを対象にしておく
    fromOld := IniRead(SETTINGS, "general", "asked", "0") = "1"
        && IniRead(SETTINGS, "targets", "claude", "") = ""
    ; 2.0.0 の試作版にあった「Codex」の項目は「ChatGPT / Codex」にまとめた
    if IniRead(SETTINGS, "targets", "codex", "") != "" {
        if IniRead(SETTINGS, "targets", "codex", "0") = "1"
            IniWrite("1", SETTINGS, "targets", "chatgpt")
        IniDelete(SETTINGS, "targets", "codex")
    }
    for t in TARGETS {
        def := (fromOld && t.key != "claude") ? "0" : "1"
        v := IniRead(SETTINGS, "targets", t.key, def)
        targetOn[t.key] := (v = "1")
        IniWrite(targetOn[t.key] ? "1" : "0", SETTINGS, "targets", t.key)
    }
}

ToggleTarget(key, name, *) {
    global SETTINGS, targetOn, APP_NAME
    targetOn[key] := !targetOn[key]
    IniWrite(targetOn[key] ? "1" : "0", SETTINGS, "targets", key)
    if targetOn[key]
        TargetMenu().Check(name)
    else
        TargetMenu().Uncheck(name)
    TrayTip(name (targetOn[key] ? " を対象にしました" : " を対象から外しました"), APP_NAME)
}

TargetMenu() {
    static m := Menu()
    return m
}

; 旧名 Claude Enter Swap（1.x）からの引っ越し。引っ越した場合は true
MigrateFromOldName() {
    global OLD_EXE, OLD_DATA_DIR, OLD_STARTUP_LNK, DATA_DIR, STARTUP_LNK
    moved := false
    ; 古いほうが動いたままだと、入れ替えが2回かかって元に戻ってしまう
    while A_ScriptName != OLD_EXE && ProcessExist(OLD_EXE) && A_Index <= 5 {
        ProcessClose(OLD_EXE)
        Sleep 200
    }
    if DirExist(OLD_DATA_DIR) && !DirExist(DATA_DIR) {
        try {
            DirMove(OLD_DATA_DIR, DATA_DIR)
            moved := true
        }
    }
    if FileExist(OLD_STARTUP_LNK) {
        try FileDelete(OLD_STARTUP_LNK)
        try FileCreateShortcut(A_ScriptFullPath, STARTUP_LNK, A_ScriptDir)
        moved := true
    }
    return moved
}

ShowUpgradeNotice() {
    global APP_NAME, OLD_EXE
    MsgBox("「Claude Enter Swap」は「" APP_NAME "」に名前が変わりました。`n`n"
        . "・設定とバックアップは、そのまま引き継ぎました。`n"
        . "・今までどおり、対象は Claude だけになっています。`n"
        . "・ChatGPT・Codex・Gemini・Copilot でも使いたいときは、`n"
        . "　画面右下のアイコンを右クリック →「対象のアプリ」から選んでください。`n`n"
        . "古い " OLD_EXE " は、もう使いません。フォルダごと削除してかまいません。",
        APP_NAME, "Iconi")
}

; ---------------------------------------------------------------------
;  タスクトレイ（画面右下）のメニュー
; ---------------------------------------------------------------------
SetupTray() {
    global APP_NAME, STARTUP_LNK, TARGETS, targetOn
    A_IconTip := APP_NAME "（有効）"
    tm := A_TrayMenu
    tm.Delete()
    tm.Add("有効", ToggleEnabled)
    tm.Check("有効")
    sub := TargetMenu()
    for t in TARGETS {
        sub.Add(t.label, ToggleTarget.Bind(t.key))
        if targetOn[t.key]
            sub.Check(t.label)
    }
    tm.Add("対象のアプリ", sub)
    tm.Add()
    tm.Add("日本語入力（IME）の設定を調整する", (*) => ChooseAndApply(false))
    tm.Add("日本語入力（IME）の設定を元に戻す", (*) => RestoreAll())
    tm.Add()
    tm.Add("Windows起動時に自動で起動する", ToggleStartup)
    if FileExist(STARTUP_LNK)
        tm.Check("Windows起動時に自動で起動する")
    tm.Add()
    tm.Add("使い方（バージョン " APP_VERSION "）", (*) => ShowHelp())
    tm.Add("終了", (*) => ExitApp())
    tm.Default := "使い方（バージョン " APP_VERSION "）"
}

; zipを解凍せずに中から起動すると、一時フォルダから動くため自動起動などが壊れる
WarnIfTempDir() {
    global APP_NAME
    tmp := StrLower(EnvGet("TEMP"))
    if (tmp != "" && InStr(StrLower(A_ScriptDir), tmp) = 1) {
        MsgBox("zipファイルの中から直接起動しているようです。`n`n"
            . "このままだと「Windows起動時に自動で起動する」がうまく動きません。`n"
            . "いったん終了して、zipを右クリック →「すべて展開」で取り出してから、`n"
            . "取り出したフォルダの AIEnterSwap.exe を起動してください。",
            APP_NAME, "Icon!")
    }
}

ToggleEnabled(name, *) {
    global enabled, APP_NAME
    enabled := !enabled
    if enabled {
        A_TrayMenu.Check(name)
        A_IconTip := APP_NAME "（有効）"
    } else {
        A_TrayMenu.Uncheck(name)
        A_IconTip := APP_NAME "（一時停止中）"
    }
    TrayTip(enabled ? "有効にしました" : "一時停止しました（普段どおりのEnterに戻ります）", APP_NAME)
}

ToggleStartup(name, *) {
    global STARTUP_LNK, APP_NAME
    if FileExist(STARTUP_LNK) {
        FileDelete(STARTUP_LNK)
        A_TrayMenu.Uncheck(name)
        TrayTip("Windows起動時の自動起動をやめました", APP_NAME)
    } else {
        FileCreateShortcut(A_ScriptFullPath, STARTUP_LNK, A_ScriptDir)
        A_TrayMenu.Check(name)
        TrayTip("Windows起動時に自動で起動するようにしました", APP_NAME)
    }
}

ShowHelp() {
    global APP_NAME, APP_VERSION, TARGETS, targetOn
    list := ""
    for t in TARGETS
        list .= "      " (targetOn[t.key] ? "✓ " : "　 ") t.label "`n"
    MsgBox("AIチャットを使っているときだけ、キーの動きを入れ替えます。`n`n"
        . "      Enter          → 改行`n"
        . "      Shift + Enter  → 送信`n`n"
        . "いまの対象（✓が付いているもの）：`n" list
        . "（それ以外のアプリや、ターミナル（黒い画面）では、いつもどおりの動きです）`n`n"
        . "日本語の変換中は、Enter でも Shift + Enter でも「確定」になります。`n"
        . "（そのために、日本語入力（IME）の設定を1か所だけ変えています）`n`n"
        . "画面右下のアイコンを右クリックすると、`n"
        . "対象のアプリの選択・一時停止・自動起動・IMEの設定を元に戻す、などができます。`n"
        . "（アイコンが見えないときは、右下の「^」を押すと出てきます）`n`n"
        . "※個人が作った非公式のツールです。各AIの提供会社とは関係ありません。",
        APP_NAME " " APP_VERSION, "Iconi")
}

; ---------------------------------------------------------------------
;  初回起動：使っているIMEを調べて、設定を調整するか確認する
; ---------------------------------------------------------------------
FirstRunCheck() {
    global SETTINGS
    if IniRead(SETTINGS, "general", "asked", "0") = "1"
        return
    IniWrite("1", SETTINGS, "general", "asked")
    ChooseAndApply(true)
}

GimeInstalled() {
    global GIME_CFG
    return FileExist(EnvGet("ProgramFiles(x86)") "\Google\Google Japanese Input\GoogleIMEJaConverter.exe")
        || FileExist(A_ProgramFiles "\Google\Google Japanese Input\GoogleIMEJaConverter.exe")
        || FileExist(GIME_CFG)
}

; 使っているIMEを選んでもらい、その設定を調整する
ChooseAndApply(firstRun) {
    global APP_NAME
    hasGoogle := GimeInstalled()
    head := firstRun ? "起動しました。画面右下（タスクトレイ）にアイコンがあります。`n"
        . "（見えないときは、右下の「^」を押すと出てきます）`n`n"
        . "対象：Claude・ChatGPT・Codex・Gemini・Copilot`n"
        . "（アイコンを右クリック →「対象のアプリ」で1つずつオン／オフできます）`n`n" : ""
    msg := head
        . "日本語の変換中に Enter を押したとき、ちゃんと「確定」になるように、`n"
        . "日本語入力（IME）のキー設定を1か所だけ変更します。`n"
        . "（変更前の設定はバックアップします。あとでメニューから元に戻せます）`n`n"
        . (hasGoogle ? "普段使っている日本語入力はどれですか？"
                     : "Microsoft IME（Windows標準）の設定を変更しますか？")
    choices := hasGoogle
        ? ["Google日本語入力", "Microsoft IME（Windows標準）", "両方使っている", "今はしない"]
        : ["変更する", "今はしない"]
    pick := AskButtons(msg, choices)

    doGoogle := hasGoogle && (pick = 1 || pick = 3)
    doMs := hasGoogle ? (pick = 2 || pick = 3) : (pick = 1)
    if !(doGoogle || doMs) {
        MsgBox("変更しませんでした。あとでトレイメニューの`n「日本語入力（IME）の設定を調整する」から変更できます。", APP_NAME, "Iconi")
        return
    }
    if doMs {
        r := MsgBox("Microsoft IME は、キー設定を変えるために`n"
            . "「以前のバージョンの Microsoft IME」に切り替わります。`n"
            . "（入力の仕方はほぼ同じですが、変換候補の見た目などが少し変わります）`n`nよろしいですか？",
            APP_NAME, "OKCancel Icon?")
        if r != "OK"
            doMs := false
    }
    results := ""
    if doGoogle
        results .= "Google日本語入力：" (GimeApply() ? "変更しました" : "変更できませんでした") "`n"
    if doMs
        results .= "Microsoft IME：" (MsimeApply() ? "変更しました" : "変更できませんでした") "`n"
    if results = ""
        return
    MsgBox(results
        . (doMs ? "`n※Microsoft IME の変更は、アプリを開き直すと反映されます。`n"
                . "　Claude や ChatGPT などのデスクトップアプリは「×」で閉じても裏で動き続けることがあるので、`n"
                . "　画面右下（タスクトレイ）のそのアプリのアイコンを右クリック →「終了（Quit）」で`n"
                . "　完全に終了してから、もう一度開いてください。ブラウザの場合はブラウザを開き直してください。`n"
                . "　（それでもだめならPCを再起動してください）" : ""),
        APP_NAME, "Iconi")
}

; ボタンを並べて選んでもらう小さな画面。選んだ番号を返す（閉じたら最後の選択肢扱い）
AskButtons(text, labels) {
    global APP_NAME
    res := {picked: labels.Length}
    g := Gui("+AlwaysOnTop -MinimizeBox", APP_NAME)
    g.SetFont("s10", "Yu Gothic UI")
    g.MarginX := 20, g.MarginY := 16
    g.Add("Text", "w460", text)
    for i, label in labels {
        b := g.Add("Button", (i = 1 ? "xm y+16 " : "xm y+6 ") "w460 h34", label)
        b.OnEvent("Click", AskButtonsPick.Bind(res, g, i))
    }
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show()
    WinWaitClose(g.Hwnd)
    return res.picked
}

AskButtonsPick(res, g, i, *) {
    res.picked := i
    g.Destroy()
}

RestoreAll() {
    global APP_NAME, GIME_BACKUP, SETTINGS
    hasG := FileExist(GIME_BACKUP)
    hasM := IniRead(SETTINGS, "msime", "backup", "0") = "1"
    if !(hasG || hasM) {
        MsgBox("元に戻す設定はありません（このアプリでIMEの設定を変更していません）。", APP_NAME, "Iconi")
        return
    }
    r := MsgBox("日本語入力（IME）の設定を、このアプリで変更する前の状態に戻します。`n`n"
        . "※変更後にIMEの設定画面で別の設定を変えていた場合、それも元に戻ることがあります。`n`n戻しますか？",
        APP_NAME, "YesNo Icon?")
    if r != "Yes"
        return
    out := ""
    if hasG
        out .= "Google日本語入力：" (GimeRestore() ? "戻しました" : "戻せませんでした") "`n"
    if hasM
        out .= "Microsoft IME：" (MsimeRestore() ? "戻しました" : "戻せませんでした") "`n"
    MsgBox(out (hasM ? "`n※Microsoft IME は、アプリを開き直すと反映されます。`n"
        . "　Claude や ChatGPT などのデスクトップアプリは、画面右下のアイコンから完全に終了してから開き直してください。" : ""), APP_NAME, "Iconi")
}

; =====================================================================
;  Microsoft IME
;  ・「以前のバージョンの Microsoft IME を使う」をオン
;      HKCU\...\Tsf3Override\{03b5835f-...}  NoTsf3Override2 = 1
;  ・キー設定のスタイルを「Custom」にして、キー表の「Shift+Enter」を全部「全確定(09)」に
;      HKCU\...\IMEJP\MSIME  keystyle = "Custom"
;      HKCU\...\IMEJP\StyleList\Custom  key = "キー名=xx xx xx xx xx xx" の並び（Shift-JIS、\0区切り）
; =====================================================================
MsimeApply() {
    global MSIME_ROOT, MSIME_CUSTOM, MSIME_LEGACY, MSIME_CUSTOM_BACKUP, SETTINGS, APP_NAME
    try {
        style := RegRead(MSIME_ROOT "\MSIME", "keystyle", "")
        curHex := RegRead(MSIME_CUSTOM, "key", "")
        legacy := RegRead(MSIME_LEGACY, "NoTsf3Override2", "")

        ; --- バックアップ（初回だけ。2回目以降は最初の状態を残しておく） ---
        if IniRead(SETTINGS, "msime", "backup", "0") != "1" {
            IniWrite(style = "" ? "(none)" : style, SETTINGS, "msime", "prev_keystyle")
            IniWrite(legacy = "" ? "(none)" : legacy, SETTINGS, "msime", "prev_legacy")
            hadCustom := RegKeyExists(MSIME_CUSTOM)
            IniWrite(hadCustom ? "1" : "0", SETTINGS, "msime", "had_custom")
            if hadCustom {
                if RunWait('reg.exe export "' MSIME_CUSTOM '" "' MSIME_CUSTOM_BACKUP '" /y', , "Hide") != 0
                    throw Error("バックアップを作れませんでした")
            }
            IniWrite("1", SETTINGS, "msime", "backup")
        }

        ; --- キー表 ---
        if (style = "Custom" && curHex != "") {
            ; すでに自分でカスタマイズしている → その表の Shift+Enter だけ変える
            newHex := MsimePatchHex(curHex)
            if (newHex != curHex)
                RegWrite(newHex, "REG_BINARY", MSIME_CUSTOM, "key")
        } else {
            ; 初期設定のまま → 初期設定の表（Shift+Enter だけ変更済み）を書き込む
            for line in StrSplit(MsimeCustomTemplate(), "`n") {
                p := StrSplit(Trim(line, "`r"), "`t")
                if p.Length < 3
                    continue
                RegWrite(p[2] = "REG_DWORD" ? Integer(p[3]) : p[3], p[2], MSIME_CUSTOM, p[1])
            }
            RegWrite("Custom", "REG_SZ", MSIME_ROOT "\MSIME", "keystyle")
        }

        ; --- 以前のバージョンを使う ---
        RegWrite(1, "REG_DWORD", MSIME_LEGACY, "NoTsf3Override2")
        return MsimeIsPatched()
    } catch as e {
        MsgBox("Microsoft IME の設定を変更できませんでした。`n`n詳細: " e.Message, APP_NAME, "Iconx")
        return false
    }
}

MsimeRestore() {
    global MSIME_ROOT, MSIME_CUSTOM, MSIME_LEGACY, MSIME_CUSTOM_BACKUP, SETTINGS
    try {
        prevStyle := IniRead(SETTINGS, "msime", "prev_keystyle", "(none)")
        prevLegacy := IniRead(SETTINGS, "msime", "prev_legacy", "(none)")
        hadCustom := IniRead(SETTINGS, "msime", "had_custom", "0") = "1"

        if (hadCustom && FileExist(MSIME_CUSTOM_BACKUP)) {
            RegDeleteKey(MSIME_CUSTOM)
            RunWait('reg.exe import "' MSIME_CUSTOM_BACKUP '"', , "Hide")
        } else if (!hadCustom) {
            try RegDeleteKey(MSIME_CUSTOM)
        }
        if (prevStyle = "(none)") {
            try RegDelete(MSIME_ROOT "\MSIME", "keystyle")
        } else {
            RegWrite(prevStyle, "REG_SZ", MSIME_ROOT "\MSIME", "keystyle")
        }
        if (prevLegacy = "(none)") {
            try RegDelete(MSIME_LEGACY, "NoTsf3Override2")
        } else {
            RegWrite(Integer(prevLegacy), "REG_DWORD", MSIME_LEGACY, "NoTsf3Override2")
        }

        IniDelete(SETTINGS, "msime")
        try FileDelete(MSIME_CUSTOM_BACKUP)
        return true
    } catch {
        return false
    }
}

MsimeIsPatched() {
    global MSIME_ROOT, MSIME_CUSTOM, MSIME_LEGACY
    if RegRead(MSIME_LEGACY, "NoTsf3Override2", 0) != 1
        return false
    if RegRead(MSIME_ROOT "\MSIME", "keystyle", "") != "Custom"
        return false
    hex := RegRead(MSIME_CUSTOM, "key", "")
    return hex != "" && MsimePatchHex(hex) = hex
}

RegKeyExists(key) {
    try {
        loop reg, key, "KV"
            return true
        RegRead(key)   ; 値が1つもないキーでも、あれば例外にならない
        return true
    }
    return false
}

; キー表（16進の文字列）の中の「Shift+Enter=xx xx xx xx xx xx」を
; 「Shift+Enter=xx 09 09 09 09 09」（最初の欄＝入力なしの状態はそのまま）にする。
; 行が無ければ末尾に足す。
MsimePatchHex(hex) {
    pat := "53686966742B456E7465723D"          ; "Shift+Enter="
    want := "203039203039203039203039203039"  ; " 09 09 09 09 09"
    start := 1
    while (pos := InStr(hex, pat, false, start)) {
        ; 2文字単位の区切りに合っていて、直前が行の区切り(00)か先頭のときだけ
        ; （「Ctrl+Shift+Enter=」の途中に一致したものは除く）
        if (Mod(pos - 1, 2) = 0 && (pos = 1 || SubStr(hex, pos - 2, 2) = "00")) {
            valPos := pos + StrLen(pat)
            ; 値は "xx xx xx xx xx xx" の17文字 = 16進で34文字
            if (SubStr(hex, valPos + 34, 2) != "00")
                throw Error("キー表の形式が想定と違います")
            return SubStr(hex, 1, valPos + 3) want SubStr(hex, valPos + 34)
        }
        start := pos + 2
    }
    ; 無い場合：最後の区切り(00)の手前に1行足す
    if (SubStr(hex, -4) != "0000")
        throw Error("キー表の形式が想定と違います")
    return SubStr(hex, 1, StrLen(hex) - 2) pat "383020303920303920303920303920303900" "00"
}

; Microsoft IME（以前のバージョン）の初期キー表。Shift+Enter だけ「全確定」にしてある。
MsimeCustomTemplate() {
    return "
    (
{{MSIME_CUSTOM}}
    )"
}

; =====================================================================
;  Google日本語入力
;  設定ファイル config1.db（Protocol Buffers という形式）の2項目だけ書き換える：
;    41番 = キー設定のスタイル（0=カスタム, 1=ATOK, 2=MS-IME, 3=ことえり）
;    42番 = カスタムのキー設定表（タブ区切りの文字）
; =====================================================================
GimeApply() {
    global GIME_CFG, GIME_BACKUP, APP_NAME
    if !FileExist(GIME_CFG) {
        MsgBox("Google日本語入力の設定ファイルが見つかりません。`n一度Google日本語入力で文字を入力してから、もう一度お試しください。", APP_NAME, "Icon!")
        return false
    }
    try {
        buf := FileRead(GIME_CFG, "RAW")
        fields := PbParse(buf)
        style := PbGetVarint(fields, 41, -1)
        table := PbGetString(buf, fields, 42)

        if (style = 0 && table != "") {
            base := table                       ; すでにカスタム設定 → それを元に1か所だけ変える
        } else if (style = 2 || style = -1) {
            base := GimeMsimeKeymap()           ; MS-IME風（初期設定）→ その内容を元にする
        } else {
            MsgBox("Google日本語入力のキー設定が「" (style = 1 ? "ATOK" : "ことえり") "」スタイルのため、`n"
                . "自動では変更できませんでした。`n`n"
                . "次のどちらかで使えるようになります：`n`n"
                . "【A】キー設定を「MS-IME」スタイルにしてよい場合`n"
                . "　Google日本語入力のプロパティ →「キー設定の選択」を「MS-IME」に →「OK」。`n"
                . "　そのあと、このアプリのメニュー「日本語入力（IME）の設定を調整する」をもう一度。`n`n"
                . "【B】今のスタイルのまま使いたい場合`n"
                . "　プロパティ →「キー設定の選択」の横の「編集」を押し、`n"
                . "　モード「変換前入力中」「変換中」と、名前に「サジェスト」「予測」が付くもの`n"
                . "　それぞれで、入力キー「Shift Enter」のコマンドを「確定」にして「OK」。`n"
                . "　（スタイルは自動で「カスタム」になります）", APP_NAME, "Icon!")
            return false
        }

        newTable := GimePatchKeymap(base)
        if (style = 0 && newTable = table)
            return true                         ; すでに調整済み

        if !FileExist(GIME_BACKUP)
            FileCopy(GIME_CFG, GIME_BACKUP)

        out := PbRebuild(buf, fields, Map(41, PbVarintField(41, 0), 42, PbBytesField(42, newTable)))
        ; 書き込んだ結果が正しく読めるか確認してから置き換える
        check := PbParse(out)
        if PbGetVarint(check, 41, -1) != 0 || PbGetString(out, check, 42) != newTable
            throw Error("書き込み内容の確認に失敗しました")
        tmp := GIME_CFG ".ces-tmp"
        f := FileOpen(tmp, "w")
        f.RawWrite(out)
        f.Close()
        FileMove(tmp, GIME_CFG, true)
        GimeRestartConverter()
        return true
    } catch as e {
        MsgBox("Google日本語入力の設定を変更できませんでした。`n（設定ファイルは変更していません）`n`n詳細: " e.Message, APP_NAME, "Iconx")
        return false
    }
}

GimeRestore() {
    global GIME_CFG, GIME_BACKUP
    try {
        FileCopy(GIME_BACKUP, GIME_CFG, true)
        FileDelete(GIME_BACKUP)
        GimeRestartConverter()
        return true
    } catch {
        return false
    }
}

; Google日本語入力の変換エンジンを再起動して、新しい設定を読み込ませる
; （次にキーを押したとき自動で起動し直す）
GimeRestartConverter() {
    while ProcessExist("GoogleIMEJaConverter.exe") && A_Index <= 5 {
        ProcessClose("GoogleIMEJaConverter.exe")
        Sleep 200
    }
}

; キー設定表の「Shift Enter」の行を、変換中の各状態で「Commit（確定）」に揃える
GimePatchKeymap(tsv) {
    global GIME_STATES
    tsv := StrReplace(tsv, "`r", "")
    lines := StrSplit(RTrim(tsv, "`n"), "`n")
    out := []
    for line in lines {
        p := StrSplit(line, "`t")
        if (p.Length >= 2 && p[2] = "Shift Enter" && HasValue(GIME_STATES, p[1]))
            continue
        out.Push(line)
    }
    for st in GIME_STATES
        out.Push(st "`tShift Enter`tCommit")
    s := ""
    for line in out
        s .= line "`n"
    return s
}

HasValue(arr, v) {
    for x in arr
        if x = v
            return true
    return false
}

; ---- Protocol Buffers の最小限の読み書き ----
PbReadVarint(buf, &pos) {
    result := 0, shift := 0
    loop {
        if pos >= buf.Size
            throw Error("設定ファイルの形式が想定と違います")
        b := NumGet(buf, pos, "UChar"), pos += 1
        result |= (b & 0x7F) << shift
        shift += 7
        if !(b & 0x80)
            return result
        if shift > 63
            throw Error("設定ファイルの形式が想定と違います")
    }
}

PbParse(buf) {
    fields := []
    pos := 0
    while pos < buf.Size {
        start := pos
        key := PbReadVarint(buf, &pos)
        f := {num: key >> 3, wt: key & 7, start: start, val: 0, dStart: 0, dLen: 0}
        switch f.wt {
            case 0: f.val := PbReadVarint(buf, &pos)
            case 1: pos += 8
            case 2:
                f.dLen := PbReadVarint(buf, &pos)
                f.dStart := pos
                pos += f.dLen
            case 5: pos += 4
            default: throw Error("設定ファイルの形式が想定と違います")
        }
        if pos > buf.Size
            throw Error("設定ファイルの形式が想定と違います")
        f.end := pos
        fields.Push(f)
    }
    return fields
}

PbGetVarint(fields, num, default) {
    v := default
    for f in fields
        if f.num = num && f.wt = 0
            v := f.val
    return v
}

PbGetString(buf, fields, num) {
    s := ""
    for f in fields
        if f.num = num && f.wt = 2
            s := f.dLen ? StrGet(buf.Ptr + f.dStart, f.dLen, "UTF-8") : ""
    return s
}

PbVarintBytes(n) {
    arr := []
    loop {
        b := n & 0x7F
        n := n >>> 7
        if n {
            arr.Push(b | 0x80)
        } else {
            arr.Push(b)
            return arr
        }
    }
}

PbVarintField(num, value) {
    arr := PbVarintBytes(num << 3)
    for b in PbVarintBytes(value)
        arr.Push(b)
    return arr
}

PbBytesField(num, str) {
    n := StrPut(str, "UTF-8") - 1
    sb := Buffer(n + 1)
    StrPut(str, sb, "UTF-8")
    arr := PbVarintBytes((num << 3) | 2)
    for b in PbVarintBytes(n)
        arr.Push(b)
    loop n
        arr.Push(NumGet(sb, A_Index - 1, "UChar"))
    return arr
}

; 元のファイルから、置き換える番号の項目を除いてコピーし、新しい項目を後ろに付ける
PbRebuild(buf, fields, replacements) {
    total := 0
    for f in fields
        if !replacements.Has(f.num)
            total += f.end - f.start
    for num, arr in replacements
        total += arr.Length
    out := Buffer(total)
    pos := 0
    for f in fields {
        if replacements.Has(f.num)
            continue
        len := f.end - f.start
        DllCall("RtlMoveMemory", "Ptr", out.Ptr + pos, "Ptr", buf.Ptr + f.start, "UPtr", len)
        pos += len
    }
    for num, arr in replacements
        for b in arr
            NumPut("UChar", b, out, pos++)
    return out
}

; Google日本語入力（Mozc）の「MS-IME」キー設定（初期設定）
; 出典: https://github.com/google/mozc/blob/master/src/data/keymap/ms-ime.tsv
GimeMsimeKeymap() {
    return "
    (
{{MSIME_TSV}}
    )"
}
