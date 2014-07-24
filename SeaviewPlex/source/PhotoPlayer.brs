'*
'* A simple wrapper around a slideshow. Single items and lists are both supported.
'*

Function createPhotoPlayerScreen(context, contextIndex, viewController, shuffled=false)
    obj = CreateObject("roAssociativeArray")
    initBaseScreen(obj, viewController)

    screen = CreateObject("roSlideShow")
    screen.SetMessagePort(obj.Port)

    screen.SetUnderscan(2.5)
    screen.SetMaxUpscale(8.0)
    screen.SetDisplayMode("photo-fit")
    screen.SetPeriod(RegRead("slideshow_period", "preferences", "6").toInt())
    screen.SetTextOverlayHoldTime(RegRead("slideshow_overlay", "preferences", "2500").toInt())

    ' Standard screen properties
    obj.Screen = screen
    if type(context) = "roArray" then
        obj.Item = context[contextIndex]
        AddAccountHeaders(screen, obj.Item.server.AccessToken)
        screen.SetContentList(context)
        screen.SetNext(contextIndex, true)
        obj.CurIndex = contextIndex
        obj.PhotoCount = context.count()
        obj.Context = context
    else
        obj.Item = context
        AddAccountHeaders(screen, obj.Item.server.AccessToken)
        screen.AddContent(context)
        screen.SetNext(0, true)
        obj.CurIndex = 0
        obj.PhotoCount = 1
        obj.Context = [context]
    end if

    NowPlayingManager().SetControllable("photo", "skipPrevious", obj.Context.Count() > 1)
    NowPlayingManager().SetControllable("photo", "skipNext", obj.Context.Count() > 1)

    obj.HandleMessage = photoPlayerHandleMessage

    obj.Pause = photoPlayerPause
    obj.Resume = photoPlayerResume
    obj.Next = photoPlayerNext
    obj.Prev = photoPlayerPrev
    obj.Stop = photoPlayerStop

    obj.playbackTimer = createTimer()
    obj.IsPaused = false

    obj.IsShuffled = shuffled
    obj.SetShuffle = photoPlayerSetShuffle
    if shuffled then
        NowPlayingManager().timelines["photo"].attrs["shuffle"] = "1"
    else
        NowPlayingManager().timelines["photo"].attrs["shuffle"] = "0"
    end if

    return obj
End Function

Function PhotoPlayer()
    ' If the active screen is a slideshow, return it. Otherwise, invalid.
    screen = GetViewController().screens.Peek()
    if type(screen.Screen) = "roSlideShow" then
        return screen
    else
        return invalid
    end if
End Function

Function photoPlayerHandleMessage(msg) As Boolean
    ' We don't actually need to do much of anything, the slideshow pretty much
    ' runs itself.

    handled = false

    if type(msg) = "roSlideShowEvent" then
        handled = true

        if msg.isScreenClosed() then
            ' Send an analytics event
            amountPlayed = m.playbackTimer.GetElapsedSeconds()
            Debug("Sending analytics event, appear to have watched slideshow for " + tostr(amountPlayed) + " seconds")
            AnalyticsTracker().TrackEvent("Playback", firstOf(m.Item.ContentType, "photo"), m.Item.mediaContainerIdentifier, amountPlayed)
            NowPlayingManager().location = "navigation"
            NowPlayingManager().UpdatePlaybackState("photo", invalid, "stopped", 0)

            m.ViewController.PopScreen(m)
        else if msg.isPlaybackPosition() then
            m.CurIndex = msg.GetIndex()
            NowPlayingManager().location = "fullScreenPhoto"
            NowPlayingManager().UpdatePlaybackState("photo", m.Context[m.CurIndex], "playing", 0)
        else if msg.isRequestFailed() then
            Debug("preload failed: " + tostr(msg.GetIndex()))
        else if msg.isRequestInterrupted() then
            Debug("preload interrupted: " + tostr(msg.GetIndex()))
        else if msg.isPaused() then
            Debug("paused")
            m.IsPaused = true
            NowPlayingManager().UpdatePlaybackState("photo", m.Context[m.CurIndex], "paused", 0)
        else if msg.isResumed() then
            Debug("resumed")
            m.IsPaused = false
            NowPlayingManager().UpdatePlaybackState("photo", m.Context[m.CurIndex], "playing", 0)
        end if
    end if

    return handled
End Function

Sub photoPlayerPause()
    if NOT m.IsPaused then
        m.Screen.Pause()

        ' Calling Pause on the screen won't trigger an isPaused event
        m.IsPaused = true
        NowPlayingManager().UpdatePlaybackState("photo", m.Context[m.CurIndex], "paused", 0)
    end if
End Sub

Sub photoPlayerResume()
    if m.IsPaused then
        m.Screen.Resume()

        ' Calling Resume on the screen won't trigger an isResumed event
        m.IsPaused = false
        NowPlayingManager().UpdatePlaybackState("photo", m.Context[m.CurIndex], "playing", 0)
    end if
End Sub

Sub photoPlayerNext()
    maxIndex = m.PhotoCount - 1
    index = m.CurIndex
    newIndex = index

    if index < maxIndex then
        newIndex = index + 1
    else
        newIndex = 0
    end if

    if index <> newIndex then
        m.Screen.SetNext(newIndex, true)
        if m.IsPaused then
            m.Resume()
            m.Pause()
        end if
    end if
End Sub

Sub photoPlayerPrev()
    maxIndex = m.PhotoCount - 1
    index = m.CurIndex
    newIndex = index

    if index > 0 then
        newIndex = index - 1
    else
        newIndex = maxIndex
    end if

    if index <> newIndex then
        m.Screen.SetNext(newIndex, true)
        if m.IsPaused then
            m.Resume()
            m.Pause()
        end if
    end if
End Sub

Sub photoPlayerStop()
    m.Screen.Close()
End Sub

Sub photoPlayerSetShuffle(shuffleVal)
    newVal = (shuffleVal = 1)
    if newVal = m.IsShuffled then return

    m.IsShuffled = newVal
    if m.IsShuffled then
        m.CurIndex = ShuffleArray(m.Context, m.CurIndex)
    else
        m.CurIndex = UnshuffleArray(m.Context, m.CurIndex)
    end if

    m.Screen.SetContentList(m.Context)

    if m.CurIndex < m.PhotoCount - 1 then
        m.Screen.SetNext(m.CurIndex + 1, false)
    else
        m.Screen.SetNext(0, false)
    end if

    NowPlayingManager().timelines["photo"].attrs["shuffle"] = tostr(shuffleVal)
End Sub
