#version 2

local TOOL_ID = "smokegrenadephysics"
local GRENADE_COOLDOWN = 0.3
local SMOKE_DURATION = 60.0
local HEAT_SCAN_INTERVAL = 0.15
local MAX_ACTIVE_GRENADES = 4
local MAX_INVENTORY = 3

local playerData = {}

function server.init()
    RegisterTool(TOOL_ID, "Smoke Grenade", "MOD/prefab/tool.xml", 1)
    SetBool("game.tool." .. TOOL_ID .. ".enabled", true)
    SetString("game.tool." .. TOOL_ID .. ".ammo.display", " ")

    server.lastFireTime = {}
    server.grenades = {}
    server.nextGrenadeId = 1
    server.lastHeatScan = 0

    for p in Players() do
        server.lastFireTime[p] = 0
        playerData[p] = { count = MAX_INVENTORY }
        SetToolAmmo(TOOL_ID, MAX_INVENTORY, p)
    end
end

function server.tick(dt)
    local currentTime = GetTime()

    local activeGenerators = {}
    for _, g in ipairs(server.grenades) do
        if g.active and g.generating then
            table.insert(activeGenerators, g)
        end
    end
    
    if #activeGenerators > MAX_ACTIVE_GRENADES then
        local toDisable = #activeGenerators - MAX_ACTIVE_GRENADES
        for i = 1, toDisable do
            if activeGenerators[i] then
                activeGenerators[i].generating = false
            end
        end
    end

    for p in Players() do
        if not server.lastFireTime[p] then
            server.lastFireTime[p] = 0
        end
        if not playerData[p] then
            playerData[p] = { count = MAX_INVENTORY }
            SetToolAmmo(TOOL_ID, MAX_INVENTORY, p)
        end

        local data = playerData[p]
        if not data then data = { count = 0 } end
        shared[tostring(p)] = { count = data.count, max = MAX_INVENTORY }

        if GetPlayerTool(p) == TOOL_ID then
            if InputDown("usetool", p) then
                if currentTime - server.lastFireTime[p] >= GRENADE_COOLDOWN then
                    if data.count > 0 then
                        server.lastFireTime[p] = currentTime
                        data.count = data.count - 1
                        SetToolAmmo(TOOL_ID, data.count, p)

                        if data.count == 0 then
                            SetToolEnabled(TOOL_ID, false, p)
                            SetPlayerTool("empty", p)
                        end

                        local camTransform = GetPlayerCameraTransform(p)
                        local startPos = camTransform.pos
                        local aimDir = TransformToParentVec(camTransform, Vec(0, 0, -1))

                        local throwPos = VecAdd(startPos, VecScale(aimDir, 1.0))

                        local spawned = Spawn("MOD/prefab/throwable.xml", Transform(throwPos, QuatEuler(0, 0, 0)))

                        local body = nil
                        if spawned and #spawned > 0 then
                            for _, ent in ipairs(spawned) do
                                if GetEntityType(ent) == "body" then
                                    body = ent
                                    break
                                elseif GetEntityType(ent) == "shape" then
                                    body = GetShapeBody(ent)
                                    break
                                end
                            end
                        end

                        if body then
                            local throwVel = VecScale(aimDir, 20)
                            SetBodyVelocity(body, throwVel)

                            table.insert(server.grenades, {
                                id = server.nextGrenadeId,
                                body = body,
                                spawnTime = currentTime,
                                active = true,
                                generating = true
                            })

                            server.nextGrenadeId = server.nextGrenadeId + 1
                        end
                    end
                end
            end

            if InputPressed("q", p) and data.count > 0 then
                local eye = GetPlayerEyeTransform(p)
                local dropPos = TransformToParentPoint(eye, Vec(0.3, -0.2, 0.5))

                local spawned = Spawn("MOD/prefab/tool_dropped.xml", Transform(dropPos, eye.rot))
                local spawnedBody = nil
                if spawned and #spawned > 0 then
                    for _, ent in ipairs(spawned) do
                        if GetEntityType(ent) == "body" then
                            spawnedBody = ent
                            break
                        elseif GetEntityType(ent) == "shape" then
                            local body = GetShapeBody(ent)
                            if body then
                                spawnedBody = body
                            end
                            break
                        end
                    end
                end

                if spawnedBody then
                    SetTag(spawnedBody, "smoke_count", "1")

                    local fwd = TransformToParentVec(eye, Vec(0, -0.2, -1))
                    local playerVel = GetPlayerVelocity(p)
                    local dropVel = VecAdd(playerVel, VecScale(fwd, 10.0))
                    SetBodyVelocity(spawnedBody, dropVel)
                    SetBodyAngularVelocity(spawnedBody, Vec(8.0, 4.0, 2.0))

                    data.count = data.count - 1
                    SetToolAmmo(TOOL_ID, data.count, p)
                    if data.count == 0 then
                        SetToolEnabled(TOOL_ID, false, p)
                        SetPlayerTool("empty", p)
                    end
                end
            end
        end

        if InputPressed("interact", p) then
            local body = GetPlayerInteractBody(p)
            if body ~= 0 and HasTag(body, "pickUpGun") and HasTag(body, "smoke_count") then
                if data.count < MAX_INVENTORY then
                    data.count = data.count + 1
                    SetToolAmmo(TOOL_ID, data.count, p)
                    if GetPlayerTool(p) ~= TOOL_ID then
                        SetToolEnabled(TOOL_ID, true, p)
                        SetPlayerTool(TOOL_ID, p)
                    end
                    Delete(body)
                end
            end
        end
    end
end

function server.update(dt)
    local currentTime = GetTime()

    if currentTime - server.lastHeatScan > HEAT_SCAN_INTERVAL then
        server.lastHeatScan = currentTime
        server.heatSources = {}
        
        local fireShapes = FindShapes("fire", true)
        for _, s in ipairs(fireShapes) do
            if IsHandleValid(s) then
                local t = GetShapeWorldTransform(s)
                if t then
                    table.insert(server.heatSources, {
                        pos = t.pos,
                        type = "fire"
                    })
                end
            end
        end
        
        local explosionShapes = FindShapes("explosion", true)
        for _, s in ipairs(explosionShapes) do
            if IsHandleValid(s) then
                local t = GetShapeWorldTransform(s)
                if t then
                    table.insert(server.heatSources, {
                        pos = t.pos,
                        type = "explosion"
                    })
                end
            end
        end
        
        local bombShapes = FindShapes("bomb", true)
        for _, s in ipairs(bombShapes) do
            if IsHandleValid(s) then
                local t = GetShapeWorldTransform(s)
                if t then
                    table.insert(server.heatSources, {
                        pos = t.pos,
                        type = "explosion"
                    })
                end
            end
        end
        
        local dynamiteShapes = FindShapes("dynamite", true)
        for _, s in ipairs(dynamiteShapes) do
            if IsHandleValid(s) then
                local t = GetShapeWorldTransform(s)
                if t then
                    table.insert(server.heatSources, {
                        pos = t.pos,
                        type = "explosion"
                    })
                end
            end
        end
    end

    for _, grenade in ipairs(server.grenades) do
        if grenade.active and grenade.body then
            if not IsHandleValid(grenade.body) then
                grenade.active = false
            else
                local elapsed = currentTime - grenade.spawnTime

                if elapsed > 0.5 and grenade.generating then
                    local bodyPos = GetBodyTransform(grenade.body).pos

                    for j = 1, 3 do
                        local offset = Vec(
                            (math.random() - 0.5) * 0.3,
                            0.2 + math.random() * 0.3,
                            (math.random() - 0.5) * 0.3
                        )
                        local smokePos = VecAdd(bodyPos, offset)

                        ParticleReset()
                        ParticleType("smoke")
                        ParticleAlpha(0.6, 0, "easeout")
                        if j % 3 == 0 then ParticleColor(0.75, 0.75, 0.75) else ParticleColor(0.65, 0.65, 0.65) end
                        ParticleRadius(0.5, 1.1, "easeout")
                        ParticleDrag(3.0)
                        ParticleGravity(-0.5)
                        ParticleCollide(0, 0.1)
                        ParticleSticky(0.02)

                        local velocity = Vec(
                            (math.random() - 0.5) * 2.0,
                            (math.random() - 0.1) * 2.5,
                            (math.random() - 0.5) * 2.0
                        )
                        
                        local affectedByExplosion = false
                        
                        if server.heatSources then
                            for _, heat in ipairs(server.heatSources) do
                                local dist = VecLength(VecSub(bodyPos, heat.pos))
                                if dist < 8.0 then
                                    local strength = (8.0 - dist) / 8.0
                                    if heat.type == "explosion" then
                                        affectedByExplosion = true
                                        local pushDir = VecNormalize(VecSub(bodyPos, heat.pos))
                                        pushDir = VecAdd(pushDir, Vec(0, 0.3, 0))
                                        velocity = VecAdd(velocity, VecScale(pushDir, strength * 18.0))
                                    else
                                        velocity = VecAdd(velocity, Vec(0, strength * 4.0, 0))
                                    end
                                end
                            end
                        end
                        
                        if affectedByExplosion then
                            ParticleDrag(0.2)
                            ParticleGravity(0.8)
                        end
                        
                        SpawnParticle(smokePos, velocity, 30)
                    end
                end

                if elapsed > SMOKE_DURATION then
                    if IsHandleValid(grenade.body) then
                        Delete(grenade.body)
                    end
                    grenade.active = false
                    grenade.generating = false
                end
            end
        end
    end
    
    local toRemove = {}
    for idx, grenade in ipairs(server.grenades) do
        if not grenade.active then
            table.insert(toRemove, idx)
        end
    end

    for i = #toRemove, 1, -1 do
        table.remove(server.grenades, toRemove[i])
    end
end

function client.tick(dt)
    local localPlayer = GetLocalPlayer()
    if localPlayer ~= 0 and GetPlayerTool(localPlayer) == TOOL_ID then
        SetToolTransform(Transform(Vec(0.3, -0.2, -0.5), QuatEuler(0, 0, 0)))
    end
end

function client.draw()
    local localPlayer = GetLocalPlayer()
    if not localPlayer or localPlayer == 0 then return end

    local currentTool = GetPlayerTool(localPlayer)
    if currentTool ~= TOOL_ID then return end

    local s = shared[tostring(localPlayer)]
    local count = s and s.count or 0
    local maxCount = s and s.max or MAX_INVENTORY

    local w = UiWidth()
    local h = UiHeight()

    UiPush()
        UiTranslate(w - 300, h - 110)

        UiColor(0, 0, 0, 0.6)
        UiRect(280, 90)

        UiTranslate(10, 10)
        UiColor(0.7, 0.7, 0.7)
        UiFont("bold.ttf", 22)
        UiText("SMOKE GRENADE")

        UiTranslate(0, 25)
        UiFont("bold.ttf", 20)
        UiColor(1, 1, 1)
        UiText(count .. "/" .. maxCount)

        UiTranslate(0, 25)
        UiFont("regular.ttf", 16)
        UiColor(0.8, 0.8, 0.8)
        UiText("LMB- throw | Q- drop")

    UiPop()
end

function Players()
    local allPlayers = GetAllPlayers()
    local i = 0
    return function()
        i = i + 1
        if i <= #allPlayers then
            return allPlayers[i]
        end
    end
end