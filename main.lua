-- NYRA — Lightweight UI configuration

local AutoFarmSettings = {
    Enabled = false,
    MovementMode = "Teleport", -- UI preference only
}

local MovementModes = {
    "Teleport",
    "Tween",
}

-- Plain dropdown
local movementDropdown = Instance.new("TextButton")
movementDropdown.Name = "MovementMode"
movementDropdown.Size = UDim2.new(1, 0, 0, 34)
movementDropdown.BackgroundColor3 = Color3.fromRGB(32, 32, 36)
movementDropdown.BorderSizePixel = 0
movementDropdown.Text = "Movement: " .. AutoFarmSettings.MovementMode
movementDropdown.TextColor3 = Color3.fromRGB(220, 220, 225)
movementDropdown.Font = Enum.Font.Gotham
movementDropdown.TextSize = 13
movementDropdown.Parent = autofarmPage

local dropdownOpen = false
local optionFrame

movementDropdown.MouseButton1Click:Connect(function()
    dropdownOpen = not dropdownOpen

    if optionFrame then
        optionFrame:Destroy()
        optionFrame = nil
    end

    if not dropdownOpen then
        return
    end

    optionFrame = Instance.new("Frame")
    optionFrame.Name = "MovementOptions"
    optionFrame.Size = UDim2.new(1, 0, 0, #MovementModes * 30)
    optionFrame.Position = UDim2.new(0, 0, 1, 4)
    optionFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
    optionFrame.BorderSizePixel = 0
    optionFrame.ZIndex = 20
    optionFrame.Parent = movementDropdown

    for index, mode in ipairs(MovementModes) do
        local option = Instance.new("TextButton")
        option.Size = UDim2.new(1, 0, 0, 30)
        option.Position = UDim2.new(0, 0, 0, (index - 1) * 30)
        option.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
        option.BorderSizePixel = 0
        option.Text = mode
        option.TextColor3 = Color3.fromRGB(205, 205, 210)
        option.Font = Enum.Font.Gotham
        option.TextSize = 12
        option.ZIndex = 21
        option.Parent = optionFrame

        option.MouseButton1Click:Connect(function()
            AutoFarmSettings.MovementMode = mode
            movementDropdown.Text = "Movement: " .. mode

            optionFrame:Destroy()
            optionFrame = nil
            dropdownOpen = false
        end)
    end
end)
