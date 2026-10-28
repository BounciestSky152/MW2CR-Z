-- Wolverines! Zombies: a ZOMBIES button on the campaign main menu opening this
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
    { "WALL WEAPONS", "Four weapons hang on Nate's walls for 200, 600, 1200 and 1200 points. Buying one you already have refills its ammo for half price." },
    { "PERKS", "Juggernog (2500): 2.5x health. Stamin-Up (2000): move faster. Double Tap (2000): more damage. Quick Revive (1500): survive one killing hit." },
    { "AMMO CRATE AND MYSTERY BOX", "The ammo crate (1000) refills every weapon and your grenades. The mystery box (950) gives a random weapon; take it within 10 seconds." },
    { "POWER-UPS", "Killed zombies sometimes drop one: Max Ammo, Double Points, Insta-Kill, Kaboom (kills every zombie) or Bonus Points." },
    { "ZOMBIES", "Walkers at first, faster runners from round 3, and tough, hard-hitting brutes from round 6. They only hurt you up close." },
    { "FIRST GAME", "The first time, walk into Nate's and hold Use for 2 seconds where you want to start. After that you always start there." },
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
    text = string.el("ZOMBIES"),
    description = string.el("Wolverines! Zombies: survive endless rounds inside Nate's Sports Bar & Grill."),
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_menu")
    end
})

LUI.MenuBuilder.registerType("zm_menu", function(a1)
    local menu = newmenu(a1, "WOLVERINES! ZOMBIES")

    menu:AddButton(string.el("PLAY"), play, nil, true, nil, {
        desc_text = string.el("Start in Nate's Sports Bar & Grill on Wolverines!. Best round so far: " .. getbest())
    })

    menu:AddButton(string.el("HOW TO PLAY"), function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_howto")
    end, nil, true, nil, {
        desc_text = string.el("Points, wall weapons, perks, the mystery box, power-ups and zombie types.")
    })

    menu:AddButton(string.el("RESET START SPOT"), function()
        Engine.Exec("seta zm_nates \"\"")
    end, nil, true, nil, {
        desc_text = string.el("Next game, walk into Nate's and pick your start spot again.")
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
