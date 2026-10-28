-- MW2CR Zombies menus. On the campaign main menu, MW2CR ZOMBIES opens PLAY,
-- BUILD MODE and HOW TO PLAY; both start Wolverines!, which
-- scripts/zombies.gsc turns into the zombies mode in Nate's Sports Bar &
-- Grill. In game, the pause menu gets BUILD MENU: pick a weapon or a barrier
-- and its price, and the script places it where you aim (picks go to the
-- script through the zm_cmd dvar).

local function getdvar(name)
    local ok, value = pcall(function() return Engine.GetDvarString(name) end)
    if (ok and value ~= nil) then
        return value
    end
    return ""
end

local function getbest()
    local best = getdvar("zm_best")
    if (best == "") then
        return "0"
    end
    return best
end

-- Back on the main menu, the campaign gets its loading videos again.
if (Engine.InFrontend()) then
    Engine.Exec("set cl_disableMapMovies 0; set cl_enableCustomLoadscreen 0")
end

local function play(build)
    Engine.Exec("set zm_build_mode " .. (build and "1" or "0"))
    -- No Wolverines! loading video (or its sound): h2-mod's plain loading
    -- screen instead, and the level starts by itself once loaded.
    Engine.Exec("set cl_disableMapMovies 1; set cl_enableCustomLoadscreen 1")
    Engine.Exec("set cl_loadscreenTitle \"MW2CR ZOMBIES\"; set cl_loadscreenDesc \"Nate's Sports Bar & Grill\"; set cl_loadscreenObj \"\"; set cl_loadscreenImage \"\"")
    -- Same form the game's own level select uses.
    pcall(function() LUI.FlowManager.PushMenuStackToDVar() end)
    if (Engine.StreamingInstallMap) then
        Engine.StreamingInstallMap("invasion", "devmap invasion;")
    else
        Engine.Exec("devmap invasion")
    end
end

local placehelp = "Then aim where it goes: a live preview follows your aim. Fire or Use places it, Aim turns it, Melee cancels."

local howto = {
    { "THE GOAL", "Survive as many rounds as you can inside Nate's Sports Bar & Grill. Every round brings more, tougher zombies. You can't leave Nate's." },
    { "POINTS", "You start with 500. +10 per hit, +60 per kill, +100 for a headshot kill, +130 for a knife kill." },
    { "BUILDING", "Nothing is for sale until you place it. In game, press Esc and pick BUILD MENU: choose a weapon or a barrier and its price. " .. placehelp .. " Everything you place is remembered for next time." },
    { "WALL WEAPONS", "Aim at a wall to hang a weapon on it, or at a table or the floor to lay it there. Weapons for sale are outlined; buying one you already have refills its ammo for half price." },
    { "BARRIERS", "Aim through a doorway and the barrier spans it. Once the zombies are on, you can't get past a barrier until you buy it, and whatever is behind it opens up." },
    { "MYSTERY BOX", "Place one with the build menu. It gives a random weapon from the level; take it within 10 seconds." },
    { "BUILD MODE", "Starts Nate's without zombies so you can place things in peace. Pick START ZOMBIES in the build menu when you're ready." },
    { "STARTING PISTOL", "You start with the M9." },
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

local function button(menu, text, desc, callback)
    menu:AddButton(string.el(text), callback, nil, true, nil, {
        desc_text = string.el(desc)
    })
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
    button(menu, "PLAY", "Start in Nate's Sports Bar & Grill on Wolverines!. Best round so far: " .. getbest(), function()
        play(false)
    end)
    button(menu, "BUILD MODE", "Start in Nate's without zombies and place wall weapons and barriers (Esc, then BUILD MENU).", function()
        play(true)
    end)
    button(menu, "HOW TO PLAY", "Points, building, wall weapons, barriers, power-ups and zombie types.", function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_howto")
    end)
    return finishmenu(menu)
end)

LUI.MenuBuilder.registerType("zm_howto", function(a1)
    local menu = newmenu(a1, "HOW TO PLAY")
    for i = 1, #howto do
        button(menu, howto[i][1], howto[i][2], function() end)
    end
    return finishmenu(menu)
end)

-- In game: the build menu.

local prices = { 250, 500, 750, 1000, 1250, 1500, 1750, 2000, 2500, 3000, 4000, 5000 }
local pending = {}

-- The weapons the level has loaded, as the script lists them:
-- "name=what players call it=class;...".
local function weapons()
    local list = {}
    local seen = {}
    for entry in string.gmatch(getdvar("zm_weapons"), "[^;]+") do
        local name, label, class = string.match(entry, "^([^=]+)=([^=]*)=?(.*)$")
        if (name) then
            table.insert(list, { name = name, label = label, class = class })
            seen[label] = (seen[label] or 0) + 1
        end
    end
    for _, w in ipairs(list) do
        if (seen[w.label] > 1) then
            w.label = w.label .. " (" .. w.name .. ")"
        end
    end
    return list
end

-- Hands the pick to the script and goes back to the game.
local function send(menu, cmd)
    Engine.Exec("set zm_cmd \"" .. cmd .. "\"")
    if (not pcall(function() LUI.FlowManager.RequestCloseAllMenus(menu) end)) then
        pcall(function() LUI.FlowManager.RequestLeaveMenu(menu) end)
    end
end

LUI.MenuBuilder.registerType("zm_build", function(a1)
    local menu = newmenu(a1, "BUILD MENU")
    button(menu, "PLACE A WEAPON", "Pick a weapon and its price. " .. placehelp, function()
        pending = { kind = "weapon" }
        LUI.FlowManager.RequestAddMenu(nil, "zm_build_weapons")
    end)
    button(menu, "PLACE A BARRIER", "Pick its price, then aim through a doorway: the barrier spans it. Once the zombies are on, nobody gets past it until it's bought.", function()
        pending = { kind = "barrier", label = "Barrier" }
        LUI.FlowManager.RequestAddMenu(nil, "zm_build_price")
    end)
    button(menu, "PLACE A MYSTERY BOX", "Pick its price, then aim at the floor or a table where it goes. It gives a random weapon; take it within 10 seconds. " .. placehelp, function()
        pending = { kind = "box", label = "Mystery Box" }
        LUI.FlowManager.RequestAddMenu(nil, "zm_build_price")
    end)
    button(menu, "MOVE SOMETHING", "Aim at something you placed and press Fire or Use to pick it up, then place it again.", function()
        send(menu, "move")
    end)
    button(menu, "REMOVE SOMETHING", "Aim at something you placed and press Fire or Use to remove it.", function()
        send(menu, "remove")
    end)
    button(menu, "REMOVE EVERYTHING", "Take away every weapon and barrier you placed.", function()
        LUI.FlowManager.RequestAddMenu(nil, "zm_build_clear")
    end)
    if (getdvar("zm_build_mode") == "1") then
        button(menu, "START ZOMBIES", "Done building: here they come.", function()
            send(menu, "start")
        end)
    end
    return finishmenu(menu)
end)

LUI.MenuBuilder.registerType("zm_build_weapons", function(a1)
    local menu = newmenu(a1, "PLACE A WEAPON")
    local list = weapons()
    if (#list == 0) then
        button(menu, "NO WEAPONS FOUND", "The level hasn't listed its weapons yet; try again in a moment.", function() end)
    end
    for i = 1, #list do
        local w = list[i]
        button(menu, string.upper(w.label), w.label .. " - " .. w.name .. " (" .. w.class .. ")", function()
            pending = { kind = "weapon", name = w.name, label = w.label }
            LUI.FlowManager.RequestAddMenu(nil, "zm_build_price")
        end)
    end
    return finishmenu(menu)
end)

LUI.MenuBuilder.registerType("zm_build_price", function(a1)
    local menu = newmenu(a1, "PRICE: " .. string.upper(pending.label or ""))
    for i = 1, #prices do
        local price = prices[i]
        button(menu, tostring(price), placehelp, function()
            if (pending.kind == "barrier") then
                send(menu, "barrier " .. price)
            elseif (pending.kind == "box") then
                send(menu, "box " .. price)
            else
                send(menu, "weapon " .. pending.name .. " " .. price)
            end
        end)
    end
    return finishmenu(menu)
end)

LUI.MenuBuilder.registerType("zm_build_clear", function(a1)
    local menu = newmenu(a1, "REMOVE EVERYTHING?")
    button(menu, "YES, REMOVE EVERYTHING", "Every weapon and barrier you placed goes. This can't be undone.", function()
        send(menu, "clear")
    end)
    return finishmenu(menu)
end)

-- BUILD MENU in the pause menu, the way h2-mod adds its own pause buttons.
if (not Engine.InFrontend()) then
    LUI.onmenuopen("sp_pause_menu", function(element)
        if (getdvar("mapname") ~= "invasion" or getdvar("zm_off") == "1") then
            return
        end
        local menu = element:getFirstChild()
        local entry = menu:AddButton(string.el("BUILD MENU"), function()
            LUI.FlowManager.RequestAddMenu(nil, "zm_build")
        end)
        menu.list:removeElement(entry)
        menu.list:insertElement(entry, 2)
    end)
end
