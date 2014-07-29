' ********************************************************************
' **  Entry point for the Plex client. Configurable themes etc. haven't been yet.
' **
' ********************************************************************

Sub Main(args)
    splashVideo()
    m.RegistryCache = CreateObject("roAssociativeArray")

    ' Process any launch args (set registry values)
    for each arg in args
        if Left(arg, 5) = "pref!" then
            pref = Mid(arg, 6)
            value = args[arg]
            Debug("Setting preference from launch param: " + pref + " = " + value)
            if value <> "" then
                RegWrite(pref, value, "preferences")
            else
                RegDelete(pref, "preferences")
            end if
        end if
    next

    ' If necessary, restore the direct play preference. It's possible for a
    ' temporary value to persist if the video player crashes.
    directPlay = RegRead("directplay_restore", "preferences")
    if directPlay <> invalid then
        Debug("Restoring direct play options to: " + tostr(directPlay))
        RegWrite("directplay", directPlay, "preferences")
        RegDelete("directplay_restore", "preferences")
    end if

    ' Due to grandfathering issues, extend the trial period.
    registry = CreateObject("roRegistry")
    sections = registry.GetSectionList()
    resetTimestamp = false
    for each sectionName in sections
        if sectionName <> "misc" then
            section = CreateObject("roRegistrySection", sectionName)
            if section.Exists("first_playback_timestamp") then
                resetTimestamp = true
                success = registry.Delete(sectionName)
            end if
        end if
    next
    if resetTimestamp then
        Debug("Extending trial period")
        RegWrite("first_playback_timestamp", tostr(Now().AsSeconds()), "misc")
    end if

    RegDelete("quality_override", "preferences")

    'initialize theme attributes like titles, logos and overhang color
    initTheme()

    initGlobals()

    'prepare the screen for display and get ready to begin
    controller = createViewController()
    controller.Show()
End Sub

Sub splashVideo()
    canvas = CreateObject("roImageCanvas")
    canvas.SetLayer(0, { color: "#00000000", CompositionMode: "Source" })
    canvas.show()

    player = CreateObject("roVideoPlayer")
    messagePort = CreateObject("roMessagePort")
    player.SetMessagePort(messagePort)
    player.SetDestinationRect(canvas.GetCanvasRect())
    player.SetContentList([{
        'Stream: {url: "https://dl.dropboxusercontent.com/s/npvg30ydmul6uhd/SeaviewAnimeIntro1.mp4"}
        'Stream: {url: "http://video.ted.com/talks/podcast/Naturally7FLYBABY_2009_480.mp4"}
        Stream: {url: "pkg:/videos/SeaviewAnimeIntro1.mp4"}
        StreamFormat: "mp4"
    }])
    player.Play()
    while true
        msg = wait(0, messagePort)
        if type(msg) = "roVideoPlayerEvent" then
            if msg.isFullResult() then
                Debug("Video ended")
                wait(5, messagePort)
                canvas.close()
                exit while
            end if
        end if
    end while
End Sub

Sub initGlobals()
    device = CreateObject("roDeviceInfo")

    version = device.GetVersion()
    major = Mid(version, 3, 1).toInt()
    minor = Mid(version, 5, 2).toInt()
    build = Mid(version, 8, 5).toInt()
    versionStr = major.toStr() + "." + minor.toStr() + " build " + build.toStr()

    GetGlobalAA().AddReplace("rokuVersionStr", versionStr)
    GetGlobalAA().AddReplace("rokuVersionArr", [major, minor, build])

    Debug("UTC time: " + CurrentTimeAsString(false))
    Debug("Roku version: " + versionStr + " (" + version + ")")

    manifest = ReadAsciiFile("pkg:/manifest")
    lines = manifest.Tokenize(chr(10))
    aa = {}
    for each line in lines
        entry = line.Tokenize("=")
        aa.AddReplace(entry[0], entry[1])
    next

    appVersion = firstOf(aa["version"], "Unknown")
    GetGlobalAA().AddReplace("appVersionStr", appVersion)
    GetGlobalAA().AddReplace("appName", firstOf(aa["title"], "Unknown"))

    Debug("App version: " + appVersion)

    knownModels = {}
    knownModels["N1050"] = "Roku SD"
    knownModels["N1000"] = "Roku HD"
    knownModels["N1100"] = "Roku HD"
    knownModels["2000C"] = "Roku HD"
    knownModels["2050N"] = "Roku XD"
    knownModels["2050X"] = "Roku XD"
    knownModels["N1101"] = "Roku XD|S"
    knownModels["2100X"] = "Roku XD|S"
    knownModels["2400X"] = "Roku LT"
    knownModels["2450X"] = "Roku LT"
    knownModels["2400SK"] = "Now TV"
    ' 2500X is also Roku HD, but the newer meaning of it... not sure how best to distinguish
    knownModels["2500X"] = "Roku HD (New)"
    knownModels["3000X"] = "Roku 2 HD"
    knownModels["3050X"] = "Roku 2 XD"
    knownModels["3100X"] = "Roku 2 XS"
    knownModels["3400X"] = "Roku Streaming Stick"
    knownModels["3420X"] = "Roku Streaming Stick"
    knownModels["4200R"] = "Roku 3"
    knownModels["4200X"] = "Roku 3"

    model = firstOf(knownModels[device.GetModel()], "Roku " + device.GetModel())
    GetGlobalAA().AddReplace("rokuModel", model)

    Debug("Roku model: " + model)

    GetGlobalAA().AddReplace("rokuUniqueID", device.GetDeviceUniqueId())

    ' The Roku 1 doesn't seem to like anamorphic videos. It stretches them
    ' vertically and squishes them horizontally. We should try not to Direct
    ' Play these videos, and tell the transcoder that we don't support them.
    ' It doesn't appear to matter how the Roku is configured, even if the
    ' display type is set to 16:9 Anamorphic the videos are distorted.
    ' On the Roku 2, support was somewhat murkier, but 4.8 is intended to
    ' fix things.

    Debug("Display type: " + tostr(device.GetDisplayType()))

    playsAnamorphic = major > 4 OR (major = 4 AND (minor >= 8 OR device.GetDisplayType() = "HDTV"))
    Debug("Anamorphic support: " + tostr(playsAnamorphic))
    GetGlobalAA().AddReplace("playsAnamorphic", playsAnamorphic)

    ' Support for ReFrames seems mixed. These numbers could be wrong, but
    ' there are reports that the Roku 1 can't handle more than 5 ReFrames,
    ' and testing has shown that the video is black beyond that point. The
    ' Roku 2 has been observed to play all the way up to 16 ReFrames, but
    ' on at least one test video there were noticeable artifacts as the
    ' number increased, starting with 8.
    if major >= 4 then
        GetGlobalAA().AddReplace("maxRefFrames", 8)
    else
        GetGlobalAA().AddReplace("maxRefFrames", 5)
    end if

    GetGlobalAA().AddReplace("IsHD", device.GetDisplayType() = "HDTV")

    ' Set up mappings from old-style quality to the new transcoder params.
    GetGlobalAA().AddReplace("TranscodeVideoQualities",   ["10",      "20",     "30",     "30",     "40",     "60",     "60",      "75",      "100",     "60",       "75",       "90",        "100"])
    GetGlobalAA().AddReplace("TranscodeVideoResolutions", ["220x180", "220x128","284x160","420x240","576x320","720x480","1024x768","1280x720","1280x720","1920x1080","1920x1080","1920x1080", "1920x1080"])
    GetGlobalAA().AddReplace("TranscodeVideoBitrates",    ["64",      "96",     "208",    "320",    "720",    "1500",   "2000",    "3000",    "4000",    "8000",     "10000",    "12000",     "20000"])

    ' Stash some more info from roDeviceInfo into globals. Fetching the device
    ' info can be slow, especially for anything related to metadata creation
    ' that may happen inside a loop.

    GetGlobalAA().AddReplace("DisplaySize", device.GetDisplaySize())
    GetGlobalAA().AddReplace("DisplayMode", device.GetDisplayMode())
    GetGlobalAA().AddReplace("DisplayType", device.GetDisplayType())

    GetGlobalAA().AddReplace("legacy1080p", (device.HasFeature("1080p_hardware") AND major < 4))
    SupportsSurroundSound()
End Sub

Function GetGlobal(var, default=invalid)
    return firstOf(GetGlobalAA().Lookup(var), default)
End Function


'*************************************************************
'** Set the configurable theme attributes for the application
'**
'** Configure the custom overhang and Logo attributes
'** Theme attributes affect the branding of the application
'** and are artwork, colors and offsets specific to the app
'*************************************************************

Sub initTheme()

    app = CreateObject("roAppManager")
    theme = CreateObject("roAssociativeArray")

    theme.OverhangOffsetSD_X = "42"
    theme.OverhangOffsetSD_Y = "27"
    theme.OverhangSliceSD = "pkg:/images/Background_SD.jpg"
    theme.OverhangLogoSD  = "pkg:/images/seaview_final_SD.png"

    theme.OverhangOffsetHD_X = "70"
    theme.OverhangOffsetHD_Y = "0"
    theme.OverhangSliceHD = "pkg:/images/Background_HD.jpg"
    theme.OverhangLogoHD  = "pkg:/images/seaview_final_HD.png"

    theme.GridScreenLogoOffsetHD_X = "70"
    theme.GridScreenLogoOffsetHD_Y = "0"
    theme.GridScreenOverhangSliceHD = "pkg:/images/Background_HD.jpg"
    theme.GridScreenLogoHD  = "pkg:/images/seaview_final_HD.png"
    theme.GridScreenOverhangHeightHD = "124"

    theme.GridScreenLogoOffsetSD_X = "42"
    theme.GridScreenLogoOffsetSD_Y = "27"
    theme.GridScreenOverhangSliceSD = "pkg:/images/Background_SD.jpg"
    theme.GridScreenLogoSD  = "pkg:/images/seaview_final_SD.png"
    theme.GridScreenOverhangHeightSD = "83"

    ' We want to use a dark background throughout, just like the default
    ' grid. Unfortunately that means we need to change all sorts of stuff.
    ' The general idea is that we have a small number of colors for text
    ' and try to set them appropriately for each screen type.

    background = "#363636"
    titleText = "#BFBFBF"
    normalText = "#999999"
    detailText = "#74777A"
    subtleText = "#525252"

    theme.BackgroundColor = background

    theme.GridScreenBackgroundColor = background
    theme.GridScreenRetrievingColor = subtleText
    theme.GridScreenListNameColor = titleText
    theme.CounterTextLeft = titleText
    theme.CounterSeparator = normalText
    theme.CounterTextRight = normalText
    ' Defaults for all GridScreenDescriptionXXX

    ' The actual focus border is set by the grid based on the style
    theme.GridScreenBorderOffsetHD = "(-9,-9)"
    theme.GridScreenBorderOffsetSD = "(-9,-9)"

    theme.ListScreenHeaderText = titleText
    theme.ListItemText = normalText
    theme.ListItemHighlightText = titleText
    theme.ListScreenDescriptionText = normalText

    theme.ParagraphHeaderText = titleText
    theme.ParagraphBodyText = normalText

    theme.ButtonNormalColor = normalText
    ' Default for ButtonHighlightColor seems OK...

    theme.RegistrationCodeColor = "#FFA500"
    theme.RegistrationFocalColor = normalText

    theme.SearchHeaderText = titleText
    theme.ButtonMenuHighlightText = titleText
    theme.ButtonMenuNormalText = titleText

    theme.PosterScreenLine1Text = titleText
    theme.PosterScreenLine2Text = normalText

    theme.SpringboardTitleText = titleText
    theme.SpringboardArtistColor = titleText
    theme.SpringboardArtistLabelColor = detailText
    theme.SpringboardAlbumColor = titleText
    theme.SpringboardAlbumLabelColor = detailText
    theme.SpringboardRuntimeColor = normalText
    theme.SpringboardActorColor = titleText
    theme.SpringboardDirectorColor = titleText
    theme.SpringboardDirectorLabel = detailText
    theme.SpringboardGenreColor = normalText
    theme.SpringboardSynopsisColor = normalText

    ' Not sure these are actually used, but they should probably be normal
    theme.SpringboardSynopsisText = normalText
    theme.EpisodeSynopsisText = normalText

    subtitleColor = RegRead("subtitle_color", "preferences", "")
    if subtitleColor <> "" then theme.SubtitleColor = subtitleColor

    app.SetTheme(theme)

End Sub

Function SupportsSurroundSound(transcoding=false, refresh=false) As Boolean
    ' Before the Roku 3, there's no need to ever refresh.
    major = GetGlobal("rokuVersionArr", [0])[0]

    if m.SurroundSoundTimer = invalid then
        refresh = true
        m.SurroundSoundTimer = CreateTimer()
    else if major <= 4 then
        refresh = false
    else if m.SurroundSoundTimer.GetElapsedSeconds() > 10 then
        refresh = true
    end if

    if refresh then
        device = CreateObject("roDeviceInfo")
        result = device.HasFeature("5.1_surround_sound")
        GetGlobalAA().AddReplace("surroundSound", result)
        m.SurroundSoundTimer.Mark()
    else
        result = GetGlobal("surroundSound")
    end if

    if transcoding then
        return (result AND major >= 4)
    else
        return result
    end if
End Function
