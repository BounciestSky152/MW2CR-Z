-- Nacht der Untoten menu: a button on the campaign main menu that opens a
-- level picker. Picking a level loads it and starts the zombies mode
-- (scripts/nacht.gsc sees nacht_autostart and builds Nacht once you can move).

local levels = {
    { name = "S.S.D.D.", map = "trainer", desc = "The army base. Big, flat and open." },
    { name = "Wolverines!", map = "invasion", desc = "Suburban streets in Virginia." },
    { name = "Contingency", map = "contingency", desc = "Snowy forest outside the sub base." },
    { name = "Loose Ends", map = "estate", desc = "Makarov's safehouse estate." },
    { name = "Exodus", map = "arcadia", desc = "Arcadia's neighbourhood." },
}

local function startlevel(level)
    Engine.SetDvarString("nacht_autostart", "1")
    LUI.FlowManager.PushMenuStackToDVar()
    Engine.StreamingInstallMap(level.map, "set nacht_autostart 1; devmap " .. level.map .. ";")
end

LUI.addmenubutton("main_campaign", {
    index = 1,
    text = string.el("NACHT DER UNTOTEN"),
    description = string.el("Survive the zombies in a Nacht der Untoten replica built from MW2 props."),
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "nacht_menu")
    end
})

LUI.MenuBuilder.registerType("nacht_menu", function(a1)
    local menu = LUI.MenuTemplate.new(a1, {
        menu_title = string.el("NACHT DER UNTOTEN"),
        exclusiveController = 0,
        menu_width = 400,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset,
        showTopRightSmallBar = true,
        uppercase_title = true
    })

    for i = 1, #levels do
        local level = levels[i]
        menu:AddButton(string.el(level.name), function()
            startlevel(level)
        end, nil, true, nil, {
            desc_text = string.el(level.desc .. " Nacht is built where the level starts you.")
        })
    end

    menu:AddBackButton(function(a)
        Engine.PlaySound(CoD.SFX.MenuBack)
        LUI.FlowManager.RequestLeaveMenu(a)
    end)

    LUI.Options.InitScrollingList(menu.list, nil)
    menu:CreateBottomDivider()
    menu.optionTextInfo = LUI.Options.AddOptionTextInfo(menu)

    return menu
end)
