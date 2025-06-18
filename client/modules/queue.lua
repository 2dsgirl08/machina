local Queue = {}
Queue.__index = Queue

function Queue.new()
	return setmetatable({
		length = 0
	}, Queue)
end

function Queue:put(object)
	local pointer = {
		left = self.last,
		value = object
	}
	
	if self.last then
		self.last.right = pointer
	else
		self.first = pointer
	end

	self.last = pointer
	self.length += 1
end

function Queue:get()
	local first = self.first

	if first then
		self.first = first.right

		if not self.first then
			self.last = nil
		end

		self.length -= 1

		return first.value
	end

	return nil
end

function Queue:peek()
	return self.first and self.first.value or nil
end

function Queue:tableize()
	local newTable = {}
	local node = self.first
	
	while node do
		table.insert(newTable, node.value)
		node = self.right
	end

	return newTable
end

function Queue:clear()
	self.first = nil
end

function Queue:isEmpty()
	return self.first == nil
end

return Queue
