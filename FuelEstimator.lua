-- tank holds 54kg
local fuelCapacity = 54

local lastLapNumber = 1
local lastFuelConsumed = 0

local chFuelUsed = addChannel("FuelUsed", 1, 2, 0, 100, "L")
local chLapFuel = addChannel("LastLapFuel", 1, 2, 0, 2, "L")
local chLapsRemaining = addChannel("Remain", 1, 0, 0, 50)

setChannel(chLapFuel, 0)
setChannel(chLapsRemaining, 0)

local lastFuelRolling = 0
local fuelUseRollover = 0

function onTick()
    local currentLapNumber = getLapCount()

    local currentFuelRolling = getChannel('FuelUseRoll')
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

setTickRate(5)