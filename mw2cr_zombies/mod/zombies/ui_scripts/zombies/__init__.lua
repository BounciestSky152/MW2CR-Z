-- MW2CR Zombies: an MW2CR ZOMBIES button on the campaign main menu opening this
-- mod's menu. PLAY loads Wolverines!; scripts/zombies.gsc turns it into the
-- zombies mode in Nate's Sports Bar & Grill.

local function getbest()
    local ok, value = pcall(function() return Engine.GetDvarString("zm_best") end)
    if (ok and value ~= nil and value ~= "") then
        return value
    end
    return "0"
end

local function play()
    -- Same form the game's own level select uses.
    pcall(function() LUI.FlowManager.PushMenuStackToDVar() end)
    if (Engine.StreamingInstallMap) then
        Engine.StreamingInstallMap("invasion", "devmap invasion;")
    else
        Engine.Exec("devmap invasion")
    end
end

local howto = {
    { "THE GOAL", "Survive as many rounds as you can inside Nate's Sports Bar & Grill. Every round brings more, tougher zombies. You can't leave Nate's." },
    { "POINTS", "You start with 500. +10 per hit, +60 per kill, +100 for a headshot kill, +130 for a knife kill." },
    { "STARTING PISTOL", "You start with a pistol that hits half again as hard as normal (the M1911 if the game has one, otherwise the level's M9)." },
    { "THE DINING AREA", "You start in Nate's dining area. A FAL (1250) lies on one of the tables, and Quick Revive is here too." },
    { "THE KITCHEN", "Clearing the barricade in the kitchen doorway costs 3000. The kitchen has three more wall weapons, the ammo crate and the mystery box." },
    { "WALL WEAPONS", "Outlined weapons are for sale: the FAL in the dining area and three in the kitchen. Buying one you already have refills its ammo for half price." },
    { "QUICK REVIVE", "Quick Revive (1500): the hit that would take you down revives you instead, once per purchase." },
    { "AMMO CRATE AND MYSTERY BOX", "The ammo crate (1000) refills every weapon and your grenades. The mystery box (950) gives a random weapon; take it within 10 seconds." },
    { "POWER-UPS", "Killed zombies sometimes drop one: Max Ammo, Double Points, Insta-Kill, Kaboom (kills every zombie) or Bonus Points." },
    { "ZOMBIES", "Walkers at first, faster runners from round 3, and tough brutes from round 6. Three hits and you're down; a brute's hit counts double. Four seconds without a hit and you've recovered." },
}

local function newmenu(a1, title)
    return LUI.MenuTemplate.new(a1, {
        menu_title = string.el(title),
        exclusiveController = 0,
        menu_width = 480,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset,
        showTopRightSmallBar = true,
        uppercase_title = true
    })
end

local function finishmenu(menu)
    menu:AddBackButton(function(a)
        Engine.PlaySound(CoD.SFX.MenuBack)
        LUI.FlowManager.RequestLeaveMenu(a)
    end)
    LUI.Options.InitScrollingList(menu.list, nil)
    menu:CreateBottomDivider()
    menu.optionTextInfo = LUI.Options.AddOptionTextInfo(menu)
    return menu
end

LUI.addmenubutton("main_campaign", {
    index = 1,
    text = string.el("MW2CR ZOMBIES"),
    description = string.el("MW2CR Zombies: survive endless rounds inside Nate's Sports Bar & Grill."),
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_menu")
    end
})

LUI.MenuBuilder.registerType("zm_menu", function(a1)
    local menu = newmenu(a1, "MW2CR ZOMBIES")

    menu:AddButton(string.el("PLAY"), play, nil, true, nil, {
        desc_text = string.el("Start in Nate's Sports Bar & Grill on Wolverines!. Best round so far: " .. getbest())
    })

    menu:AddButton(string.el("SET UP NATE'S AGAIN"), function()
        Engine.Exec("seta zm_layout \"\"")
        play()
    end, nil, true, nil, {
        desc_text = string.el("Pick the FAL's table and the kitchen doorway again, then play.")
    })

    menu:AddButton(string.el("HOW TO PLAY"), function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_howto")
    end, nil, true, nil, {
        desc_text = string.el("Points, wall weapons, Quick Revive, the mystery box, power-ups and zombie types.")
    })

    return finishmenu(menu)
end)

LUI.MenuBuilder.registerType("zm_howto", function(a1)
    local menu = newmenu(a1, "HOW TO PLAY")
    for i = 1, #howto do
        local entry = howto[i]
        menu:AddButton(string.el(entry[1]), function() end, nil, true, nil, {
            desc_text = string.el(entry[2])
        })
    end
    return finishmenu(menu)
end)
