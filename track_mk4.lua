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

local function map(n, start1, stop1, start2, stop2)
    return ((n - start1) / (stop1 - start1)) * (stop2 - start2) + start2
end

local mappedSave = 0

-- Map SteerLevel (0-15) to 16-bit pump command
local function mapValue()
    local level = getChannel("SteerLevel")
    if level == nil then level = 0 end
    -- Scale 0-15 to 0-65535

    local mapped = map(level, 10, 0, 10000, 24000)
    if mapped > 65535 then mapped = 65535 end
    if mapped < 0 then mapped = 0 end
	mappedSave = mapped
    return mapped
end

---------------------------------------------------------------------
-- ST2 pump state
---------------------------------------------------------------------
local pumpMsgCount = 0
local pumpAlive = false
local pumpCounter = 0x00
local pumpStartTime = 0

local st2_1 = {0x05, 0x23, 0x08, 0x6F, 0x08, 0x74, 0x00, 0x00}
local st2_2 = {0xA0, 0xDD, 0x04, 0xFF, 0xFF, 0x05, 0x23, 0x00}
local st2_3 = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}

local function resetPumpState()
    pumpMsgCount = 0
    pumpAlive = false
    pumpCounter = 0x00
    st2_3[5] = 0x00
    st2_3[6] = 0x00
    st2_3[7] = 0x00
    st2_3[8] = 0x00
end

local function doPump()
    local now = getUptime();

    local engineRun = getChannel("IgnitionOn")
    if engineRun == nil or engineRun == 0 then
        resetPumpState()
        pumpStartTime = now
        return
    end

    local pumpRunTime = now - pumpStartTime

    local mv = mapValue()

    if pumpRunTime < 5000 then
        mv = map(pumpRunTime, 0, 3000, 0, mv)
    end

    st2_3[5] = bit.band(bit.rshift(mv, 8), 0xFF)
    st2_3[6] = bit.band(mv, 0xFF)

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
		println(mappedSave)
        fuelTickCount = 0
        doFuel()
    end
end

setTickRate(50)
