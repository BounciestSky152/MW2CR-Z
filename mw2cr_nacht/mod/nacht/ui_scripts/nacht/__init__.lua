-- Burger Town Zombies: a button on the campaign main menu opens this mod's
-- menu screen. PLAY loads Wolverines! and starts zombies in Burger Town
-- (scripts/nacht.gsc sees nacht_autostart 2).

local savedspot = "nacht_arena_invasion"

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
    text = string.el("BURGER TOWN ZOMBIES"),
    description = string.el("Survive endless rounds of zombies inside Burger Town on Wolverines!"),
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "nacht_menu")
    end
})

LUI.MenuBuilder.registerType("nacht_menu", function(a1)
    local menu = LUI.MenuTemplate.new(a1, {
        menu_title = string.el("BURGER TOWN ZOMBIES"),
        exclusiveController = 0,
        menu_width = 400,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset,
        showTopRightSmallBar = true,
        uppercase_title = true
    })

    menu:AddButton(string.el("PLAY"), playburgertown, nil, true, nil, {
        desc_text = string.el("Loads Wolverines! with the level emptied. The first time, walk into Burger Town and hold Use for 2 seconds; after that you start there.")
    })

    menu:AddButton(string.el("FORGET SAVED SPOT"), function()
        Engine.Exec("seta " .. savedspot .. " \"\"")
    end, nil, true, nil, {
        desc_text = string.el("Next PLAY lets you walk to Burger Town and pick the spot again.")
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
