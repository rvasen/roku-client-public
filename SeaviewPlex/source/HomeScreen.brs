'*****************************************************************
'**  Home screen: the entry display of the application
'**
'*****************************************************************

Function createHomeScreen(viewController) As Object
    ' At the end of the day, the home screen is just a grid with a custom loader.
    ' So create a regular grid screen and override/extend as necessary.
    obj = createGridScreen(viewController, "flat-square", "stop")

    obj.Screen.SetDisplayMode("photo-fit")
    obj.Loader = createHomeScreenDataLoader(obj)

    obj.Refresh = refreshHomeScreen
    obj.OnTimerExpired = homeScreenOnTimerExpired
    obj.SuperActivate = obj.Activate
    obj.Activate = homeScreenActivate

    obj.clockTimer = createTimer()
    obj.clockTimer.Name = "clock"
    obj.clockTimer.SetDuration(20000, true) ' A little lag is fine here
    viewController.AddTimer(obj.clockTimer, obj)

    return obj
End Function

Sub refreshHomeScreen(changes)
    PrintAA(changes)

    ' If myPlex state changed, we need to update the queue, shared sections,
    ' and any owned servers that were discovered through myPlex.
    if changes.DoesExist("myplex") then
        m.Loader.OnMyPlexChange()
    end if

    ' If a server was added or removed, we need to update the sections,
    ' channels, and channel directories.
    if changes.DoesExist("servers") then
        for each server in PlexMediaServers()
            if server.machineID <> invalid AND GetPlexMediaServer(server.machineID) = invalid then
                PutPlexMediaServer(server)
            end if
        next

        servers = changes["servers"]
        didRemove = false
        for each machineID in servers
            Debug("Server " + tostr(machineID) + " was " + tostr(servers[machineID]))
            if servers[machineID] = "removed" then
                DeletePlexMediaServer(machineID)
                didRemove = true
            else
                server = GetPlexMediaServer(machineID)
                if server <> invalid then
                    m.Loader.CreateServerRequests(server, true, false)
                end if
            end if
        next

        if didRemove then
            m.Loader.RemoveInvalidServers()
        end if
    end if

    ' Recompute our capabilities
    Capabilities(true)
End Sub

Sub homeScreenOnTimerExpired(timer)
    if timer.Name = "clock" AND m.ViewController.IsActiveScreen(m) then
        m.Screen.SetBreadcrumbText("", CurrentTimeAsString())
    end if
End Sub

Sub homeScreenActivate(priorScreen)
    m.clockTimer.Active = (RegRead("home_clock_display", "preferences", "12h") <> "off")
    m.Screen.SetBreadcrumbText("", CurrentTimeAsString())
    m.SuperActivate(priorScreen)
End Sub
