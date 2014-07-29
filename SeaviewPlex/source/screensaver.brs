Sub RunScreenSaver()
    m.RegistryCache = CreateObject("roAssociativeArray")
    mode = RegRead("screensaver", "preferences", "animated")

    if mode <> "disabled" then
        initGlobals()
        DisplayScreenSaver(mode)
    else
        Debug("Deferring to system screensaver")
    end if
End Sub

Sub DisplayScreenSaver(mode)
    if GetGlobal("IsHD") then
        m.default_screensaver = {url:"pkg:/images/screensaver-hd.png", SourceRect:{w:300,h:281}, TargetRect:{x:0,y:0}}
    else
        m.default_screensaver = {url:"pkg:/images/screensaver-sd.png", SourceRect:{w:248,h:140}, TargetRect:{x:0,y:0}}
    end if

    m.ss_timer = CreateObject("roTimespan")
    m.ss_last_url = invalid

    canvas = CreateScreenSaverCanvas("#FF141414")
    canvas.SetImageFunc(GetScreenSaverImage)
    canvas.SetUpdatePeriodInMS(6000)
    canvas.SetUnderscan(.05)

    if mode = "animated" then
        canvas.SetLocFunc(screensaverLib_SmoothAnimation)
        canvas.SetLocUpdatePeriodInMS(40)
    else if mode = "random" then
        canvas.SetLocFunc(screensaverLib_RandomLocation)
        canvas.SetLocUpdatePeriodInMS(0)
    else
        Debug("Unrecognized screensaver preference: " + tostr(mode))
        return
    end if

    canvas.Go()
End Sub

Function GetScreenSaverImage()
    savedImage = ReadAsciiFile("tmp:/plex_screensaver")
    if savedImage <> "" then
        tokens = savedImage.Tokenize("\")
        width = tokens[0].toint()
        height = tokens[1].toint()
        image = {url:tokens[2], SourceRect:{w:width, h:height}, TargetRect:{x:0,y:0}}
    else
        image = m.default_screensaver
    end if

    ' If we've been on the same screensaver image for a long time, give the
    ' PMS a break and switch to the default image from the package.

    if m.ss_last_url <> image.url then
        m.ss_timer.Mark()
        m.ss_last_url = image.url
    end if

    o = CreateObject("roAssociativeArray")
    o.art = image
    o.content_list = [image]

    o.GetHeight = function() :return m.art.SourceRect.h :end function
    o.GetWidth  = function() :return m.art.SourceRect.w :end function
    o.Update = function(x, y)
        m.art.TargetRect.x = x
        m.art.TargetRect.y = y
        return m.content_list
    end function

    return o
End Function