local Signal = {}
Signal.__index = Signal

function Signal.new()
    local self = setmetatable({}, Signal)
    self.Listeners = {}
    return self
end

function Signal:Connect(action)
    table.insert(self.Listeners, action)

    return {
        Disconnect = function()
            local index = table.find(self.Listeners, action)

            if index then
                table.remove(self.Listeners, index)
            end
        end
    } 
end

function Signal:Wait()
    local thread = coroutine.running()

    local conn
    conn = self:Connect(function(...)
        conn:Disconnect()
        coroutine.resume(thread, ...)
    end)

    return coroutine.yield()
end

function Signal:Fire(...)
    for _, listener in self.Listeners do
        task.spawn(listener, ...)
    end
end

return Signal