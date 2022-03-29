-- tank holds 30kg
local fuelCapacity = 30

local lastLapNumber = 1
local lastFuelConsumed = 0

local chLapFuel = addChannel("LastLapFuel", 1, 2, 0, 2, "kg")
local chLapsRemaining = addChannel("LapsRemaining", 1, 0, 0, 50)

function onTick()
    local currentLapNumber = getLapCount()

    if currentLapNumber ~= lastLapNumber then
        -- We've just crossed start/finish line, update stats
        local fuelConsumed = getChannel("FuelUsed") -- TODO channel name
        local lapFuel = fuelConsumed - lastFuelConsumed
        lastFuelConsumed = fuelConsumed

        setChannel(chLapFuel, lapFuel)

        -- Estimate how many laps left to consume 30kg
        local fuelRemaining = fuelCapacity - fuelConsumed
        setChannel(chLapsRemaining, fuelRemaining / lapFuel)

        lastLapNumber = currentLapNumber
    end
end

setTickRate(10)
