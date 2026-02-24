-- HelloWorld.lua

local greeting = "Hello, World!"
local count = 5
local total = 0
local i = 0

function PrintBanner(msg)
    print("--- " .. msg .. " ---")
end

function Add(a, b)
    return a + b
end

greeting = "Hello, World!"
count = 5

PrintBanner(greeting)

total = Add(10, 32)
print("10 + 32 = " .. total)

if total > 40 then
    print("Total is greater than 40")
else
    print("Total is 40 or less")
end

print("Counting to " .. count .. ":")
for i = 1, count do
    print("  Step " .. i)
end

i = 0
while i < 3 do
    print("While pass: " .. (i + 1))
    i = i + 1
end
