#version 2

local TOOL_ID = "smokegrenade"
local GRENADE_COOLDOWN = 0.3
local SMOKE_DURATION = 60.0

function server.init()
    RegisterTool(TOOL_ID, "Smoke Grenade", "MOD/prefab/tool.xml", 1)
    SetBool("game.tool." .. TOOL_ID .. ".enabled", true)

    server.lastFireTime = {}
    server.grenades = {}
    server.nextGrenadeId = 1

    for p in Players() do
        server.lastFireTime[p] = 0
    end
end

function server.tick(dt)
    for p in Players() do
        if not server.lastFireTime[p] then
            server.lastFireTime[p] = 0
        end

        if GetPlayerTool(p) == TOOL_ID then
            local currentTime = GetTime()

            if InputDown("usetool", p) then
                if currentTime - server.lastFireTime[p] >= GRENADE_COOLDOWN then
                    server.lastFireTime[p] = currentTime

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
                            active = true
                        })

                        server.nextGrenadeId = server.nextGrenadeId + 1
                    end
                end
            end
        end
    end
end

function server.update(dt)
    local currentTime = GetTime()

    for _, grenade in ipairs(server.grenades) do
        if grenade.active and grenade.body then
            if not IsHandleValid(grenade.body) then
                grenade.active = false
            else
                local elapsed = currentTime - grenade.spawnTime

                if elapsed > 0.5 then
                    local bodyPos = GetBodyTransform(grenade.body).pos

                    for j = 1, 2 do
                        local offset = Vec(
                            (math.random() - 0.5) * 0.3,
                            0.2 + math.random() * 0.3,
                            (math.random() - 0.5) * 0.3
                        )
                        local smokePos = VecAdd(bodyPos, offset)

                        ParticleReset()
                        ParticleType("smoke")
                        ParticleAlpha(0.8, 0, "easeout")
                        if j % 3 == 0 then ParticleColor(0.75, 0.75, 0.75) else ParticleColor(0.65, 0.65, 0.65) end
                        ParticleRadius(1.2, 1.5, "easeout")
                        ParticleDrag(2.0)
                        ParticleGravity(-1.5)
                        ParticleCollide(0, 0.5)
                        ParticleSticky(0.2)

                        local velocity = Vec(
                            (math.random() - 0.5) * 0.5,
                            (math.random() - 0.3) * 0.8,
                            (math.random() - 0.5) * 0.5
                        )
                        SpawnParticle(smokePos, velocity, 10)
                    end
                end

                if elapsed > SMOKE_DURATION then
                    if IsHandleValid(grenade.body) then
                        Delete(grenade.body)
                    end
                    grenade.active = false
                end
            end
        end
    end

    local toRemove = {}
    for idx, grenade in ipairs(server.grenades) do
        if not grenade.active or (grenade.body and not IsHandleValid(grenade.body)) then
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

    local w = UiWidth()
    local h = UiHeight()

    UiPush()
        UiTranslate(w - 280, h - 80)

        UiColor(0, 0, 0, 0.6)
        UiRect(260, 60)

        UiTranslate(10, 10)
        UiColor(0.7, 0.7, 0.7)
        UiFont("bold.ttf", 24)
        UiText("SMOKE GRENADE")

        UiTranslate(0, 30)
        UiFont("regular.ttf", 18)
        UiColor(1, 1, 1)
        UiText("LMB to spawn - Grab and throw")

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