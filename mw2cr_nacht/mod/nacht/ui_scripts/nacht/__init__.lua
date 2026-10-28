-- Wolverines! Zombies: a button on the campaign main menu opens this mod's
-- menu screen. PLAY loads Wolverines! and starts zombies in Nate's Sports Bar
-- & Grill (scripts/nacht.gsc sees nacht_autostart 2).

local savedsetup = "nacht_setup_invasion"

local function playburgertown()
    -- Same form the game's own level select uses: commands run as the level starts.
    local cmd = "set nacht_autostart 2; devmap invasion;"
    pcall(function() LUI.FlowManager.PushMenuStackToDVar() end)
    if (Engine.StreamingInstallMap) then
        Engine.StreamingInstallMap("invasion", cmd)
    else
        Engine.Exec(cmd)
    end
end

LUI.addmenubutton("main_campaign", {
    index = 1,
    text = string.el("WOLVERINES! ZOMBIES"),
    description = string.el("Survive endless rounds of zombies in Nate's Sports Bar & Grill and CRB Financial on Wolverines!"),
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "nacht_menu")
    end
})

LUI.MenuBuilder.registerType("nacht_menu", function(a1)
    local menu = LUI.MenuTemplate.new(a1, {
        menu_title = string.el("WOLVERINES! ZOMBIES"),
        exclusiveController = 0,
        menu_width = 400,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset,
        showTopRightSmallBar = true,
        uppercase_title = true
    })

    menu:AddButton(string.el("PLAY"), playburgertown, nil, true, nil, {
        desc_text = string.el("Start inside Nate's Sports Bar & Grill on Wolverines!. The first time you pick the start spot and walk the route to CRB Financial.")
    })

    menu:AddButton(string.el("SET UP AGAIN"), function()
        Engine.Exec("seta " .. savedsetup .. " \"\"")
    end, nil, true, nil, {
        desc_text = string.el("Next PLAY lets you pick the start spot in Nate's and walk the route to CRB Financial again.")
    })

    menu:AddBackButton(function(a)
        Engine.PlaySound(CoD.SFX.MenuBack)
        LUI.FlowManager.RequestLeaveMenu(a)
    end)

    LUI.Options.InitScrollingList(menu.list, nil)
    menu:CreateBottomDivider()
    menu.optionTextInfo = LUI.Options.AddOptionTextInfo(menu)

    return menu
end)
