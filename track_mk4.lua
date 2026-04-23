-- tank holds 54kg
local fuelCapacity = 54

local lastLapNumber = 1
local lastFuelConsumed = 0
local lastFuelRolling = 0
local fuelUseRollover = 0
local fuelTickCount = 0

local chFuelUsed = addChannel("FuelUsed", 1, 2, 0, 100, "L")
local chLapFuel = addChannel("LastLapFuel", 1, 2, 0, 2, "L")
local chLapsRemaining = addChannel("Remain", 1, 0, 0, 50)

setChannel(chLapFuel, 0)
setChannel(chLapsRemaining, 0)

local crc_table = {}
for i = 0, 255 do
    local crc = i
    for _ = 1, 8 do
        if bit.band(crc, 0x80) ~= 0 then
            crc = bit.band(bit.bxor(bit.lshift(crc, 1), 0x07), 0xFF)
        else
            crc = bit.band(bit.lshift(crc, 1), 0xFF)
        end
    end
    crc_table[i] = crc
end

local function crc8(data, len)
    local crc = 0x00
    for i = 1, len do
        crc = crc_table[bit.bxor(crc, data[i])]
    end
    return crc
end

-- Map SteerLevel (0-15) to 16-bit pump command
local function mapValue()
    local level = getChannel("SteerLevel")
    if level == nil then level = 0 end
    -- Scale 0-15 to 0-65535
    local mapped = math.floor((level / 15) * 65535)
    if mapped > 65535 then mapped = 65535 end
    if mapped < 0 then mapped = 0 end
    return mapped
end

---------------------------------------------------------------------
-- ST2 pump state
---------------------------------------------------------------------
local pumpMsgCount = 0
local pumpStartDone = false
local pumpAlive = false
local pumpCounter = 0x00
local lastPumpRxTime = 0

local st2_1 = {0x05, 0x23, 0x08, 0x6F, 0x08, 0x74, 0x00, 0x00}
local st2_2 = {0xA0, 0xDD, 0x04, 0xFF, 0xFF, 0x05, 0x23, 0x00}
local st2_3 = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}

local function resetPumpState()
    pumpMsgCount = 0
    pumpStartDone = false
    pumpAlive = false
    pumpCounter = 0x00
    lastPumpRxTime = 0
    st2_3[5] = 0x00
    st2_3[6] = 0x00
    st2_3[7] = 0x00
    st2_3[8] = 0x00
end

local function checkPumpHeartbeat()
    local now = getUptime()
    while true do
        local id, ext, data = rxCAN(0, 0)
        if id == nil then break end
        if id == 0x12C then
            lastPumpRxTime = now
            pumpAlive = true
        end
    end
    if pumpAlive and (now - lastPumpRxTime) > 1000 then
        println("Pump heartbeat lost - resetting")
        resetPumpState()
    end
end

local function doPump()
    checkPumpHeartbeat()

    local engineRun = getChannel("EngineRun")
    if engineRun == nil or engineRun == 0 then
        if pumpStartDone or pumpMsgCount > 0 then
            resetPumpState()
        end
        return
    end

    if not pumpAlive then
        return
    end

    if not pumpStartDone then
        pumpMsgCount = pumpMsgCount + 1
        if pumpMsgCount >= 20 then
            pumpStartDone = true
        end
    end

    if pumpStartDone then
        local mv = mapValue()
        st2_3[5] = bit.band(bit.rshift(mv, 8), 0xFF)
        st2_3[6] = bit.band(mv, 0xFF)
    else
        st2_3[5] = 0x00
        st2_3[6] = 0x00
    end

    st2_1[7] = pumpCounter
    st2_3[7] = pumpCounter

    st2_1[8] = crc8(st2_1, 7)
    st2_3[8] = crc8(st2_3, 7)

    txCAN(0, 0x11C, 0, st2_3)
    txCAN(0, 0x108, 0, st2_1)
    txCAN(0, 0x144, 0, st2_2)

    if pumpCounter >= 0xF0 then
        pumpCounter = 0x00
    else
        pumpCounter = pumpCounter + 0x10
    end
end

local function resetFuelToFull()
    println("Fuel reset to full")
    lastFuelConsumed = 0
    lastFuelRolling = 0
    fuelUseRollover = 0
    setChannel(chFuelUsed, 0)
    setChannel(chLapFuel, 0)
    setChannel(chLapsRemaining, 0)
    resetLapStats()
end

local function processFuelReset()
    -- Fuel reset button: rising edge triggers reset to full
    local resetBtn = getChannel("FuelReset")
    if resetBtn == nil then resetBtn = 0 end
    if resetBtn ~= 0 then
        resetFuelToFull()
    end
end

local function doFuel()
    processFuelReset()
    local currentLapNumber = getLapCount()

    local currentFuelRolling = getChannel('FuelUseRoll')
    if currentFuelRolling == nil then return end

    if currentFuelRolling < lastFuelRolling then
        -- Either the ECU rebooted or used >2 liters of fuel
        -- Log the old rolling qty as used
        fuelUseRollover = fuelUseRollover + lastFuelRolling
    end
    lastFuelRolling = currentFuelRolling

    local fuelConsumed = fuelUseRollover + currentFuelRolling
    setChannel(chFuelUsed, fuelConsumed)

    if currentLapNumber ~= lastLapNumber then
        -- We've just crossed start/finish line, update stats
        local lapFuel = fuelConsumed - lastFuelConsumed
        lastFuelConsumed = fuelConsumed

        setChannel(chLapFuel, lapFuel)

        -- Estimate how many laps left to consume 54kg
        local fuelRemaining = fuelCapacity - fuelConsumed
        local lapsRemain = fuelRemaining / lapFuel

        -- grrr sometimes math goes haywire
        if lapsRemain > 1000 then lapsRemain = 0 end

        setChannel(chLapsRemaining, lapsRemain)

        lastLapNumber = currentLapNumber
    end
end

function onTick()
    collectgarbage()

    -- Pump runs every tick (50Hz)
    doPump()

    -- Fuel tracking runs every 10th tick (~5Hz)
    fuelTickCount = fuelTickCount + 1
    if fuelTickCount >= 10 then
        fuelTickCount = 0
        doFuel()
    end
end

setTickRate(50)
