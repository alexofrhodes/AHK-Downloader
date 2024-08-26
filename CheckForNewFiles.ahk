;-------- saved at Montag, 11. Mai 2015 09:05:58 --------------
;-------- http://www.autohotkey.com/board/topic/50123-extract-all-urls-from-page-source/ ---

;modified=20230802

TrayIcon := StrReplace("settings\" . A_ScriptName, ".ahk", ".ico")
try
    menu, tray, icon, %TrayIcon%

;-- PART-1   prepare variables -----------------------------------------------------------------------------------
OnMessage(0x404, Func("AHK_NOTIFYICON").Bind(hGui))
iniFile := A_ScriptDir "\settings\settings.ini"

; Ensure the settings directory exists
if not FileExist(A_ScriptDir "\settings")
    FileCreateDir, %A_ScriptDir%\settings

; Load settings from INI file
gosub LoadSettings

fd := A_ScriptDir  ;- where to download
f2 := fd "settings\log.txt"  ;- if wanted write URL from each PDF to a file
olderDir := fd "\older"  ;- directory to move old files

ifnotexist, %fd%  ;- create folder
    filecreatedir, %fd%
ifnotexist, %olderDir%
    filecreatedir, %olderDir%

; Remove trailing slash from UrlWithFiles if present
if (SubStr(UrlWithFiles, 0) = "/")
    UrlWithFiles := SubStr(UrlWithFiles, 1, -1)

;-- PART-2  --------------------------------------------------------------------

GuiCreate:
Gui, New, +Resize
Gui, Add, Text, center w100, Extensions:
Gui, Add, Edit, ys vExtensions gSaveSettings w300, %extensions%
gui, add, text, ys,(comma-separated without dot)

Gui, Add, Text, center xs w100 section, Relative URL:
Gui, Add, Edit, ys vMainUrl gSaveSettings w700, %mainUrl%

Gui, Add, Text, center xs w100 section, Files URL:
Gui, Add, Edit, ys vUrlWithFiles gSaveSettings w700, %UrlWithFiles%

Gui, Add, Button, xs w100 section gPickFolder, Download Dir ...
Gui, Add, Edit, ys vDownloadDir gSaveSettings w700, %downloadDir%

Gui, Add, Button, xs w100 section gGuiCancel w100, Cancel
Gui, Add, Button, ys w100 gCheckAgain w100, Check now

Gui, Add, Button, ys w100 gSelectAll, Select All
Gui, Add, Button, ys w100 gDeselectAll, Deselect All
Gui, Add, Button, ys w100 gGuiSubmit, Download selected

If (printFiles)
    checkedState := "Checked"
else
    checkedState := ""

Gui, Add, CheckBox, ys+4 vPrintFiles gSaveSettings %checkedState%, Print files after download

Gui, Add, Text, center xs w100 section, Filter:
Gui, Add, Edit, ys vFilterText gFilterChanged w300, 
Gui, Add, Button, ys w100 gClearFilter, Clear Filter
Gui, Add, CheckBox, ys vRegexFilter gFilterChanged, Use Regex 

Gui, Add, Text, center xs w100 section, Regex Find:
Gui, Add, Edit, ys vRegexFind gUpdateListView w300, ; Input field for regex find pattern
Gui, Add, Button, ys w100 gClearRegexFind, Clear Find

Gui, Add, Text, center xs w100 section, Regex Replace:
Gui, Add, Edit, ys vRegexReplace gUpdateListView w300, ; Input field for regex replace text
Gui, Add, Button, ys w100 gClearRegexReplace, Clear Replace

Gui, Add, ListView, xs vFileListView r20 w800, File Name|URL

; Populate ListView
GOSUB, UpdateListView

Gui, Add, StatusBar,, 

if (fileNames = "")
{
    SB_SetText("No new files found.")
}else{
    SB_SetText(total2 . " new files found.")  
}

Gui, Show,, File Selection

Return

CheckAgain:
    allx := ""
    httpQuery(allx, UrlWithFiles)  ; Download URL (UrlWithFiles) to a variable (allx)

    res := ""
    total1 := 0

    ; Check if the extensions array is empty
    if (extensions = "")
    {
        ; If extensions are empty, match all files
        regexPattern := "<a\s+[^>]*href\s*=\s*""([^""]+)"""
    }
    else
    {
        ; If extensions are not empty, match only files with specified extensions
        Loop, Parse, extensions, `,
        {
            extension := A_LoopField
            regexPattern := "<a\s+[^>]*href\s*=\s*""([^""]+\." extension ")"
        }
    }

    while pos := RegExMatch(allx, regexPattern, m, A_Index=1 ? 1 : pos + StrLen(m))
    {
        m := m1  ; Use the captured group
        newUrl := mainUrl m  ; URL found in UrlWithFiles

        ; Extract the filename from the URL
        ; Remove any query parameters or fragments
        newUrl := RegExReplace(newUrl, "\?.*$", "")  ; Remove query parameters
        newUrl := RegExReplace(newUrl, "#.*$", "")   ; Remove fragments

        ; Extract the filename from the URL path
        SplitPath, newUrl, fileName, folderPath, ext, name_no_ext, drive

        ; Reconstruct the filename from the folder path and file name
        newFileName := fileName

        ; Check if a file with a similar name exists
        fileExists := false
        Loop, Files, %downloadDir%\*%fileName%
        {
            existingFile := A_LoopFileName
            ; Compare filenames
            if (fileName = existingFile)
            {
                fileExists := true
                break
            }
        }

        ; Collect new files only if they do not exist
        if !fileExists
        {
            total1++
            res .= newUrl "|" newFileName "`r`n"  ; Add each found URL and new file name to variable RES
        }
    }

    ; Update ListView
    GOSUB, UpdateListView

    ; Show status in the status bar
    if (fileNames = "")
    {
        SB_SetText("No new files found.")
    }
    else
    {
        SB_SetText(total2 . " new files found.")
    }


return

ClearFilter:
    GuiControl,, filterText,  ; Clear the Regex Find field
return

ClearRegexFind:
    GuiControl,, RegexFind,  ; Clear the Regex Find field
return

ClearRegexReplace:
    GuiControl,, RegexReplace,  ; Clear the Regex Replace field
return

GuiCancel:
    ExitApp

GuiSubmit:
    Gui, Submit, NoHide
    gosub SaveSettings

    ; Collect selected files
    selectedFiles := []
    Loop
    {
        Row := LV_GetNext(Row)
        if not Row
            break
        LV_GetText(fileName, Row, 1)
        LV_GetText(url, Row, 2)
        selectedFiles.Push({url: url, newFileName: fileName})
    }

    ; Proceed with downloading and printing selected files
    if (selectedFiles.MaxIndex() > 0)
    {
        i := 0
        total1 := selectedFiles.MaxIndex()
        FormatTime, TimeString,, yyyy MM dd hh:mm:ss tt
        newContent := "nn" . TimeString . "nn"

        for index, fileInfo in selectedFiles
        {
            i++
            url := fileInfo.url
            newFileName := fileInfo.newFileName
            newContent .= url "|" newFileName "rn"
            SplashImage,, w600 x10 y130 C01 CWsilver FS10 ZH0 M2, Download I=%i% / Total=%total1% files, Now downloading=n%newFileName%nto %downloadDir%, Escape to break, Lucida Console
            FilePath := downloadDir "\" newFileName
            UrlDownloadToFile, %url%, %FilePath%

            if (printFiles)
            {
                Run, print %FilePath%
                printTimeout := 30000 ; 30 seconds timeout for printing
                startTime := A_TickCount
                Loop
                {
                    Sleep, 1000 ; Wait 1 second before checking again
                    WinGet, PID, PID, Adobe Reader ahk_class AcroRd32
                    if (!PID)
                    {
                        ; Debug message to check if Adobe Reader closed properly
                        ;MsgBox, Adobe Reader closed successfully for %newFileName%.
                        break
                    }
                    if (A_TickCount - startTime > printTimeout)
                    {
                        ; Debug message for timeout
                        ;MsgBox, Printing timeout for %newFileName%.
                        WinClose, Adobe Reader ahk_class AcroRd32
                        break
                    }
                }
                ; Ensure the Adobe Reader window is closed
                WinClose, Adobe Reader ahk_class AcroRd32
                WinWaitClose, Adobe Reader ahk_class AcroRd32,, 5 ; Wait max 5 seconds for the window to close
            }

            SplashImage, off
        }

        ; Prepend new content to log file
        if (FileExist(f2))
        {
            FileRead, existingContent, %f2%
        }
        else
        {
            existingContent := ""
        }
        newContent := newContent . existingContent
        FileDelete, %f2% ; Optional: delete the file first to ensure clean write
        FileAppend, %newContent%, %f2%

        ; Open the folder or activate the existing window
        ifexist, %downloadDir%
        {
            ; Check if the folder window exists
            IfWinExist, ahk_class CabinetWClass, %downloadDir%
            {
                WinActivate ; Activate the existing window
            }
            else
            {
                run, %downloadDir% ; Open the folder if the window doesn't exist
            }
        }

    }
    else
    {
        MsgBox, No files selected.
        return
    }

    res := ""  ;- clear variable  RES
    allx := ""  ;- clear variable  allx
  
    Gosub CheckAgain

return

SelectFolder:
    FileSelectFolder, downloadDir
    if (downloadDir != "")
        GuiControl,, DownloadDir, %downloadDir%
    return




FilterChanged:
    GuiControlGet, filterText, , FilterText
    GuiControlGet, regexFilter, , RegexFilter
    GOSUB, UpdateListView
return

UpdateListView:
    LV_Delete()
    GuiControlGet, regexFind, , RegexFind
    GuiControlGet, regexReplace, , RegexReplace
    GuiControlGet, filterText, , FilterText
    GuiControlGet, regexFilter, , RegexFilter
    Loop, Parse, res, `n, `r
    {
        if (A_LoopField != "")
        {
            StringSplit, T, A_LoopField, |
            newFileName := T2
            ; Apply regex replacement if a find pattern is provided
            if (regexFind != "")
            {
                newFileName := RegExReplace(newFileName, regexFind, regexReplace)
            }
            ; Apply filter if needed
            if (regexFilter)
            {
                ; Use regex for filtering
                if (RegExMatch(newFileName, filterText) || RegExMatch(T1, filterText))
                {
                    LV_Add("", newFileName, T1)
                }
            }
            else
            {
                ; Use simple string matching for filtering
                if (InStr(newFileName, filterText) || InStr(T1, filterText))
                {
                    LV_Add("", newFileName, T1)
                }
            }
        }
    }
    LV_ModifyCol(1, "AutoHdr")
    LV_ModifyCol(2, "AutoHdr")
return

SelectAll:
    {
        LV_Modify(0, "Select")
    }
return

DeselectAll:
    Loop, Parse, res, `n, `r
    {
        if (A_LoopField != "")
        {
            Row := LV_GetNext(0)
            while (Row)
            {
                LV_Modify(Row, "-Select")
                Row := LV_GetNext(Row)
            }
        }
    }
return

SaveSettings:
    Gui, Submit, NoHide
    IniWrite, %extensions%, %iniFile%, Settings, Extensions
    IniWrite, %mainUrl%, %iniFile%, Settings, MainUrl
    IniWrite, %UrlWithFiles%, %iniFile%, Settings, UrlWithFiles
    IniWrite, %downloadDir%, %iniFile%, Settings, DownloadDir
    IniWrite, %printFiles%, %iniFile%, Settings, PrintFiles
return

LoadSettings:
    ; If the settings.ini file does not exist, create it with default values
    if !FileExist(iniFile)
    {
        ; Create the settings.ini file with default settings
        IniWrite, pdf, %iniFile%, Settings, Extensions
        IniWrite, https://rodospublictransport.gr/, %iniFile%, Settings, MainUrl
        IniWrite, https://rodospublictransport.gr/index.php?c=schedule&p=pdf, %iniFile%, Settings, UrlWithFiles
        IniWrite, %A_ScriptDir%, %iniFile%, Settings, DownloadDir
        IniWrite, 1, %iniFile%, Settings, PrintFiles
    }

    ; Read settings from settings.ini
    IniRead, extensions, %iniFile%, Settings, Extensions, pdf
    IniRead, mainUrl, %iniFile%, Settings, MainUrl, https://rodospublictransport.gr/
    IniRead, UrlWithFiles, %iniFile%, Settings, UrlWithFiles, https://rodospublictransport.gr/index.php?c=schedule&p=pdf
    IniRead, downloadDir, %iniFile%, Settings, DownloadDir, %A_ScriptDir%
    IniRead, printFiles, %iniFile%, Settings, PrintFiles, 1
    ; Convert read value to integer
    printFiles := printFiles ? 1 : 0
return

;-----------------------------------------------------------------------------------------------------------------
esc::exitapp  ;- ESCAPE break download / close this script
;-----------------------------------------------------------------------------------------------------------------

;---------------- function urldownloadtovariable ------------------------------------------------------------------
httpQuery(byref Result, lpszUrl, POSTDATA="", HEADERS="")
{
    WebRequest := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    WebRequest.Open("GET", lpszUrl)
    WebRequest.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")
    WebRequest.Send(POSTDATA)
    Result := WebRequest.ResponseText
    WebRequest := ""
}

; ----- function to pick folder
PickFolder:
    FileSelectFolder, folderPath, *%A_ScriptDir% , 3, Select Download Folder
    if folderPath
    {
        GuiControl,, DownloadDir, %folderPath%
        IniWrite, %folderPath%, %iniFile%, Settings, DownloadDir ; Save the new folder path
    }
return

;---------------- function openoractivatewindow -------------------------------------------------------------------
OpenOrActivateFolder(folderPath) {
   for Window in ComObjCreate("Shell.Application").Windows
      continue
   until Window.document.Folder.Self.Path = folderPath && hWnd := Window.hwnd
   if hWnd
      WinActivate, ahk_id %hWnd%
   else
      Run, % folderPath
}

AHK_NOTIFYICON(hGui, wp, lp) {
   static WM_LBUTTONDOWN := 0x201
   if (lp = WM_LBUTTONDOWN)
      gosub, CheckAgain
}
;================= END script =====================================================================================
