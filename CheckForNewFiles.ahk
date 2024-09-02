/* 
https://github.com/alexofrhodes
anastasioualex@gmail.com

Description:
            List new files from a website           (filtering out those already downloaded)
            Rename by regex before downloading      (the check for wether they were downloaded is by logging their original name to log.txt)
            Filter the new list by text or regex    (//TODO save/load regex pairs)
            Support links like www.url.com/file.txt and relative links like "/folder/file.txt"  (//TODO save/load mainUrl/filesURL)
            Download selected files
            Optionally print                        (//TODO improve print function to allow for more filetypes, currently for pdf only)
*/

#SingleInstance, force
#include includes\Anchor.ahk

TrayIcon := StrReplace("settings\" . A_ScriptName, ".ahk", ".ico")
try
    menu, tray, icon, %TrayIcon%

;-- PART-1   prepare variables -----------------------------------------------------------------------------------

if not FileExist(A_ScriptDir "\settings")
    FileCreateDir, %A_ScriptDir%\settings
    
iniFile := A_ScriptDir "\settings\settings.ini"
logFile := A_ScriptDir "\settings\log.txt"
csvFile := A_ScriptDir "\settings\regexPairs.csv"
csvFileGroups := A_ScriptDir "\settings\urlGroups.csv"


gosub LoadSettings

; Remove trailing slash from UrlWithFiles if present
if (SubStr(UrlWithFiles, 0) = "/")
    UrlWithFiles := SubStr(UrlWithFiles, 1, -1)

;-- PART-2  --------------------------------------------------------------------

GuiCreate:
Gui, New, +Resize +MinSize +hwndHGUI
OnMessage(0x404, Func("AHK_NOTIFYICON").Bind(hGui))

; mouse over control to show tooltip
; variable ControlName_TT := "tooltip text"
OnMessage(0x200, "WM_MOUSEMOVE")

WM_MOUSEMOVE(){
	static CurrControl, PrevControl, _TT
	CurrControl := A_GuiControl
	If (CurrControl <> PrevControl){
			SetTimer, DisplayToolTip, -300 	; shorter wait, shows the tooltip quicker
			PrevControl := CurrControl
	}
	return
	
	DisplayToolTip:
	try
			ToolTip % %CurrControl%_TT
	catch
			ToolTip
	SetTimer, RemoveToolTip, -7000
	return
	
	RemoveToolTip:
	ToolTip
	return
}

Gui, Add, Text, center w100, Extensions:
Gui, Add, Edit, ys vExtensions gSaveSettings w600, %extensions%
Extensions_TT := "comma-separated without dot"
Gui, Add, Button, ys w100 vSaveUrlGroup gSaveUrlGroup, Save Pair

Gui, Add, Text, center xs w100 section, Relative URL:
Gui, Add, Edit, ys vMainUrl gSaveSettings w600, %mainUrl%
MainUrl_TT=
(
if file link path is relative to a website
like /folder/file.txt 
instead of www.url.com/folder/file.txt
)
Gui, Add, Button, ys w100 vLoadUrlGroups gLoadUrlGroups, Load Pair

Gui, Add, Text, center xs w100 section, Files URL:
Gui, Add, Edit, ys vUrlWithFiles gSaveSettings w600, %UrlWithFiles%

Gui, Add, Button, xs w100 section gPickFolder, Download Dir ...
Gui, Add, Edit, ys vDownloadDir gSaveSettings w600, %downloadDir%

Gui, Add, Button, ys w100 vOpenFolder gOpenFolder, Open

Gui, Add, Button, xs section w100 gCheckAgain w100, PARSE
Gui, Add, Button, xs  w100 gGuiSubmit, DOWNLOAD


If (printFiles)
    checkedState := "Checked"
else
    checkedState := ""

Gui, Add, CheckBox, xs vPrintFiles gSaveSettings %checkedState%, Print after DL

Gui, Add, Button, xs w100 gSelectAll, Select All
Gui, Add, Button, xs w100 gDeselectAll, Deselect All

Gui, Add, Button, xs w100 gClearLog, Clear Log 

Gui, Add, Button, xs w100 gGuiCancel w100, Quit

Gui, Add, Text, center ys section w100 section, Filter:
Gui, Add, Edit, ys vFilterText gFilterChanged w380, 

Gui, Add, Button, ys w100 vClearFilter gClearFilter, Clear Filter
Gui, Add, CheckBox, ys+4 vRegexFilter gFilterChanged, Use Regex 

Gui, Add, Text, center xs w100 section, Regex Find:
Gui, Add, Edit, ys vRegexFind gUpdateListView w380, 
Gui, Add, Button, ys w100 vClearRegexFind gClearRegexFind, Clear Find
Gui, Add, Button, ys w100 vSaveRegexPair gSaveRegexPair, Save Pair

Gui, Add, Text, center xs w100 section, Regex Replace:
Gui, Add, Edit, ys vRegexReplace gUpdateListView w380, 
Gui, Add, Button, ys w100 vClearRegexReplace gClearRegexReplace, Clear Replace
Gui, Add, Button, ys w100 vLoadRegexPairs gLoadRegexPairs, Load Pairs

Gui, Add, ListView, xs vFileListView r20 w600, File Name|URL

GOSUB, UpdateListView

Gui, Add, StatusBar,, 

if (fileNames = "")
{
    SB_SetText("No new files found.")
}else{
    SB_SetText(total2 . " new files found.")  
}

Gui, Font, s15
Gui, Show,, File Selection

Return


;------------------
SaveUrlGroup:
    Gui, Submit, NoHide
    InputBox, Desc, Save Group, Enter a description for this group:, , , 
    if (ErrorLevel)
        return 
    FileAppend, %extensions%`,%mainUrl%`,%urlWithFiles% `,%Desc%`n, %csvFileGroups%
    return

LoadUrlGroups:
    ; Open the new GUI for the URL Group Picker
    GuiUrlGroupPicker()
    return

GuiUrlGroupPicker() {
    global
    ; Create a new GUI for the URL Group Picker
    Gui, New, +Resize +hwndHGroupPicker
    Gui, Add, Text, center w380, Double-click a group to load:
    Gui, Add, ListView, xs vUrlGroupsListView r15 w600 gPickGroup, Extensions|Main URL|Files URL|Description

    ; Load saved groups into the ListView
    if FileExist(csvFileGroups)
    {
        FileRead, urlGroupsContent, %csvFileGroups%
        Loop, Parse, urlGroupsContent, `n, `r
        {
            if (A_LoopField = "")
                continue ; Skip empty lines

            StringSplit, group, A_LoopField, `,
            LV_Add("", group1, group2, group3, group4) ; Add extensions, main URL, files URL, and description to ListView
        }
    }
    else
    {
        MsgBox, 16, Error, No URL groups file found.
        return
    }

    Gui, Add, Button, xs gGroupPickerOK w100, OK
    Gui, Add, Button, xs gGroupPickerCancel w100, Cancel
    Gui, Add, Button, xs gDeleteGroup w100, Delete ; Add Delete button

    Gui, Show,, URL Group Picker
}

GroupPickerOK:
    GuiControl, +ReadOnly, Extensions
    GuiControl, +ReadOnly, MainUrl
    GuiControl, +ReadOnly, UrlWithFiles

    ; Get selected row data
    LV_GetText(SelectedExtensions, LV_GetNext(0), 1)
    LV_GetText(SelectedMainUrl, LV_GetNext(0), 2)
    LV_GetText(SelectedUrlWithFiles, LV_GetNext(0), 3)
    ; Update main GUI fields
    GuiControl,%HGui%:, Extensions, %SelectedExtensions%
    GuiControl,%HGui%:, MainUrl, %SelectedMainUrl%
    GuiControl,%HGui%:, UrlWithFiles, %SelectedUrlWithFiles%

    ; Close the Group Picker GUI
    Gui, %HGroupPicker%:Destroy
return

GroupPickerCancel:
    ; Close the Group Picker GUI without changes
    Gui, %HGroupPicker%:Destroy
return

PickGroup:
    if (A_GuiEvent = "DoubleClick")
    {
        ; Double-click event to select the group
        gosub, GroupPickerOK
    }
return

DeleteGroup:
    ; Get the currently selected row
    SelectedRow := LV_GetNext(0)
    if (SelectedRow = 0)
    {
        MsgBox, 48, No Selection, Please select a group to delete.
        return
    }

    ; Confirm deletion
    MsgBox, 4, Confirm Deletion, Are you sure you want to delete the selected URL group?
    IfMsgBox, No
        return

    ; Get selected row data
    LV_GetText(SelectedExtensions, SelectedRow, 1)
    LV_GetText(SelectedMainUrl, SelectedRow, 2)
    LV_GetText(SelectedUrlWithFiles, SelectedRow, 3)

    ; Remove the selected group from the ListView
    LV_Delete(SelectedRow)

    ; Read existing groups and write back without the deleted group
    if FileExist(csvFileGroups)
    {
        FileRead, urlGroupsContent, %csvFileGroups%
        newContent := ""
        Loop, Parse, urlGroupsContent, `n, `r
        {
            if (A_LoopField = "")
                continue ; Skip empty lines

            StringSplit, group, A_LoopField, `,
            if (group1 = SelectedExtensions && group2 = SelectedMainUrl && group3 = SelectedUrlWithFiles)
                continue ; Skip the group to be deleted

            newContent .= A_LoopField "`n" ; Keep all other groups
        }

        ; Write the updated content back to the file
        FileDelete, %csvFileGroups%
        FileAppend, %newContent%, %csvFileGroups%
    }
    else
    {
        MsgBox, 16, Error, No URL groups file found.
        return
    }

    MsgBox, 64, Deletion Successful, The selected URL group has been deleted.
return

;------------------

SaveRegexPair:
    Gui, Submit, NoHide
    InputBox, Desc, Save Pair, Enter a description for this find/replace pair:, , , 
    if (ErrorLevel)
        return 
    FileAppend, %RegexFind%`,%RegexReplace% `,%Desc%`n, %csvFile%

    return

LoadRegexPairs:
    ; Open the new GUI for the Regex Picker
    GuiRegexPicker()
    return

GuiRegexPicker() {
    global
    ; Create a new GUI for the Regex Picker
    Gui, New, +Resize +hwndHPicker
    Gui, Add, Text, center w380, Double-click a pair to load:
    Gui, Add, ListView, xs vRegexPairsListView r15 w400 gPickPair, Find|Replace|Description

    ; Load saved pairs into the ListView
    if FileExist(csvFile)
    {
        FileRead, regexPairsContent, %csvFile%
        Loop, Parse, regexPairsContent, `n, `r
        {
            if (A_LoopField = "")
                continue ; Skip empty lines

            StringSplit, pair, A_LoopField, `,
            LV_Add("", pair1, pair2, pair3) ; Add find, replace, and description to ListView
        }
    }
    else
    {
        MsgBox, 16, Error, No regex pairs file found.
        return
    }

    Gui, Add, Button, xs gPickerOK w100, OK
    Gui, Add, Button, xs gPickerCancel w100, Cancel
    Gui, Add, Button, xs gDeletePair w100, Delete ; Add Delete button

    Gui, Show,, Regex Picker
}

PickerOK:
    GuiControl, +ReadOnly, RegexFind
    GuiControl, +ReadOnly, RegexReplace

    ; Get selected row data
    LV_GetText(SelectedFind, LV_GetNext(0), 1)
    LV_GetText(SelectedReplace, LV_GetNext(0), 2)
    ; Update main GUI fields
    GuiControl,%HGui%:, RegexFind, %SelectedFind%
    GuiControl,%HGui%:, RegexReplace, %SelectedReplace%

    ; Close the Picker GUI
    Gui, %HPicker%:Destroy
return

PickerCancel:
    ; Close the Picker GUI without changes
    Gui, %HPicker%:Destroy
return

PickPair:
    if (A_GuiEvent = "DoubleClick")
    {
        ; Double-click event to select the pair
        gosub, PickerOK
    }
return

DeletePair:
    ; Get the currently selected row
    SelectedRow := LV_GetNext(0)
    if (SelectedRow = 0)
    {
        MsgBox, 48, No Selection, Please select a pair to delete.
        return
    }

    ; Confirm deletion
    MsgBox, 4, Confirm Deletion, Are you sure you want to delete the selected regex pair?
    IfMsgBox, No
        return

    ; Get selected row data
    LV_GetText(SelectedFind, SelectedRow, 1)
    LV_GetText(SelectedReplace, SelectedRow, 2)

    ; Remove the selected pair from the ListView
    LV_Delete(SelectedRow)

    ; Read existing pairs and write back without the deleted pair
    if FileExist(csvFile)
    {
        FileRead, regexPairsContent, %csvFile%
        newContent := ""
        Loop, Parse, regexPairsContent, `n, `r
        {
            if (A_LoopField = "")
                continue ; Skip empty lines

            StringSplit, pair, A_LoopField, `,
            if (pair1 = SelectedFind && pair2 = SelectedReplace)
                continue ; Skip the pair to be deleted

            newContent .= A_LoopField "`n" ; Keep all other pairs
        }

        ; Write the updated content back to the file
        FileDelete, %csvFile%
        FileAppend, %newContent%, %csvFile%
    }
    else
    {
        MsgBox, 16, Error, No regex pairs file found.
        return
    }

    MsgBox, 64, Deletion Successful, The selected regex pair has been deleted.
return

CheckAgain:
    SB_SetText("Checking ...")  
    allx := ""
    ; httpQuery(allx, UrlWithFiles)  ; Download URL (UrlWithFiles) to a variable (allx)
    httpQueryAsync(allx, UrlWithFiles)
    if !allx
    {
        SB_SetText("Connection Timed Out ...") 
        Return
    }
        

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

        ; Check if the file is already logged
        if (IsFileLogged(newFileName)){
            fileExists := true
        }else{
                total1++
                res .= newUrl "|" newFileName "`r`n"  ; Add each found URL and new file name to variable RES
        }
    }

    GOSUB, UpdateListView

    SB_SetText(total1 ? total1 . " new files found." : "No new files found.")

    Gui, Show

return

IsFileLogged(fileName) {
    global
    if not FileExist(logFile)
        return false

    FileRead, logContent, %logFile%
    if RegExMatch(logContent, "^" fileName "`s*,", _)
        return true

    return false
}

LogDownload(fileName, dateTime) {
    global
    ; Ensure the settings directory exists
    if not FileExist(A_ScriptDir "\settings")
        FileCreateDir, %A_ScriptDir%\settings

    ; existingContent := ""
    ; if (FileExist(logFile))
    ;     FileRead, existingContent, %logFile%
        
    FileAppend, %fileName%`, %dateTime%`n, %logFile%
    ; FileAppend, %existingContent%`n%fileName%`, %dateTime%`n, %logFile%
}

ClearFilter:
    GuiControl,, filterText,  
return

ClearRegexFind:
    GuiControl,, RegexFind,  
return

ClearRegexReplace:
    GuiControl,, RegexReplace,  
return

GuiCancel:
    ExitApp
Return

GuiSubmit:
    Gui, Submit, NoHide
    gosub SaveSettings

    ; Check if downloadDir exists
    if !FileExist(downloadDir)
    {
        MsgBox, 4, Directory Not Found, The directory "%downloadDir%" does not exist.`nWould you like to create it?
        IfMsgBox, No
        {
            MsgBox, Cancelled, Operation cancelled by user.
            return
        }
        ; Attempt to create the directory
        FileCreateDir, %downloadDir%
        if !FileExist(downloadDir)
        {
            MsgBox, 16, Error, Failed to create the directory. Please check your permissions or specify a different path.
            return
        }
        else
        {
            MsgBox, 64, Directory Created, The directory "%downloadDir%" was created successfully.
        }
    }

    selectedFiles := []
    Loop
    {
        Row := LV_GetNext(Row)
        if not Row
            break
        LV_GetText(fileName, Row, 1)
        LV_GetText(url, Row, 2)

        selectedFiles.Push({url: url, FileName: fileName})
    }

    if (selectedFiles.MaxIndex() > 0)
    {
        i := 0
        total1 := selectedFiles.MaxIndex()
        FormatTime, TimeString,, yyyy MM dd hh:mm:ss tt

        for index, fileInfo in selectedFiles
        {
            i++
            url := fileInfo.url

            newFileName := fileInfo.FileName

            SplashImage,, w600 x10 y130 C01 CWsilver FS10 ZH0 M2, Download I=%i% / Total=%total1% files, Now downloading=n%newFileName%nto %downloadDir%, Escape to break, Lucida Console
            FilePath := downloadDir "\" newFileName
            UrlDownloadToFile, %url%, %FilePath%

            ; Log the download to the log file
            SplitPath, url, fileNameFromUrl
            LogDownload(fileNameFromUrl, TimeString)

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
    GuiControl, -Redraw, FileListView
    LV_Delete()
    GuiControlGet, regexFind, , RegexFind
    GuiControlGet, regexReplace, , RegexReplace
    GuiControlGet, filterText, , FilterText
    GuiControlGet, regexFilter, , RegexFilter
    filteredCount := 0
    Loop, Parse, res, `n, `r
    {
        if (A_LoopField = "")
            continue
    
        StringSplit, T, A_LoopField, |
        newFileName := T2
    
        ; Apply regex replacement if a find pattern is provided
        if (regexFind != "")
            newFileName := RegExReplace(newFileName, regexFind, regexReplace)
    
        ; Check filter condition
        if (regexFilter ? (RegExMatch(newFileName, filterText) || RegExMatch(T1, filterText))
                        : (InStr(newFileName, filterText) || InStr(T1, filterText)))
        {
            LV_Add("", newFileName, T1)
            filteredCount++
        }
    }
        
    LV_ModifyCol(1, "AutoHdr")
    LV_ModifyCol(2, "AutoHdr")

    ; Update status bar
    if (filteredCount = 0)
        {
            if (filterText != "")
                SB_SetText("No files match the filter.")
            else
                SB_SetText("No new files found.")
        }
        else
        {
            if (filterText != "")
                SB_SetText(filteredCount . " files match the filter out of " . total1 . " new files found.")
            else
                SB_SetText(total1 . " new files found.")
        }
    GuiControl, +Redraw, FileListView
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
    IniRead, extensions, %iniFile%, Settings, Extensions
    IniRead, mainUrl, %iniFile%, Settings, MainUrl
    IniRead, UrlWithFiles, %iniFile%, Settings, UrlWithFiles
    IniRead, downloadDir, %iniFile%, Settings, DownloadDir, %A_ScriptDir%
    IniRead, printFiles, %iniFile%, Settings, PrintFiles, 1
    
    printFiles := printFiles ? 1 : 0
return


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

httpQueryAsync(ByRef Result, lpszUrl, POSTDATA="", HEADERS="")
{
    WebRequest := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    WebRequest.Open("GET", lpszUrl)
    WebRequest.setRequestHeader("Content-Type", "application/x-www-form-urlencoded")

    WebRequest.Send(POSTDATA)
    
    SetTimer, CheckRequestStatus, 100
    
    CheckRequestStatus:
    try
    {
        if (WebRequest.Status != "")
        {
            SetTimer, CheckRequestStatus, Off
            Result := WebRequest.ResponseText
            ; Continue processing
        }
    }
    catch e
    {
        SetTimer, CheckRequestStatus, Off
        MsgBox, 16, Network Error, Network connection appears to be down. Check your internet connection.
        Result := ""
    }
}

CheckNetworkStatus()
{
    RunWait, %comspec% /c ping www.google.com -n 1 -w 30000, , Hide ;-w N means how many seconds to wait
    if ErrorLevel
    {
        MsgBox, 16, Network Error, Network connection appears to be down. Check your internet connection.
        return false
    }
    return true
}

PickFolder:
    FileSelectFolder, folderPath, *%A_ScriptDir% , 3, Select Download Folder
    if folderPath
    {
        GuiControl,, DownloadDir, %folderPath%
        IniWrite, %folderPath%, %iniFile%, Settings, DownloadDir ; Save the new folder path
    }
return

OpenFolder:
    GuiControlGet, DownloadDir, , DownloadDir
    OpenOrActivateFolder(DownloadDir)
Return

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
      Gui, % hGui ":Show"
}

ClearLog:
    FileDelete, %logFile%
    SB_SetText("Log cleared.")
return

GuiSize:
    anchor("Extensions","w")
    anchor("MainUrl","w")
    anchor("UrlWithFiles","w")
    anchor("downloadDir","w")
    anchor("filterText","w")
    anchor("regexFind","w")
    anchor("regexReplace","w")
    anchor("FileListView","w")

    anchor("OpenFolder","x")
    anchor("ClearFilter","x")
    anchor("RegexFilter","x",true)
    anchor("ClearRegexFind","x")
    anchor("ClearRegexReplace","x")
    anchor("SaveUrlGroup","x")
    anchor("LoadUrlGroups","x")
    anchor("SaveRegexPair","x")
    anchor("LoadRegexPairs","x")
return

esc::exitapp  