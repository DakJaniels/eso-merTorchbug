local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")
local cm = CALLBACK_MANAGER
local wm = WINDOW_MANAGER

local tos = tostring
local tins = table.insert

local BLUE = ZO_ColorDef:New(0.8, 0.8, 1.0)
local RED  = ZO_ColorDef:New(1.0, 0.2, 0.2)

local endsWith = tbug.endsWith
local tbug_glookup = tbug.glookup
local getRelevantNameForCall = tbug.getRelevantNameForCall
local getControlName = tbug.getControlName

local tbug_isSliderEnabledByRowKey = tbug.isSliderEnabledByRowKey


--------------------------------
local function roundDecimalToPlace(decimal, place)
    return tonumber(string.format("%." .. tos(place) .. "f", decimal))
end

local function clampValue(value, min, max)
    return math.max(math.min(value, max), min)
end

local function updateTabBreadCrumbs(tabControl, tabControlCurrentlyActive)
d("[TB]updateTabBreadCrumbs-tabControlCurrentlyActive: " ..tos(tabControlCurrentlyActive))
    tbug_glookup = tbug_glookup or tbug.glookup

    local parentSubject = tabControl.parentSubject
    local parentSubjectName = (parentSubject ~= nil and tabControl.parentSubjectName) or nil
    if parentSubject ~= nil and parentSubjectName == nil then
        parentSubjectName = getRelevantNameForCall(parentSubject)
        tabControl.parentSubjectName = parentSubjectName
    end
d(">parentSubjectName: " ..tos(tabControl.parentSubjectName))
    local subject = tabControl.subject
    if subject == nil then return end

    local controlName = (tabControl.controlName ~= nil and tabControl.controlName) or getControlName(subject)
    if controlName ~= nil then
        tabControl.controlName = controlName
    end
d(">controlName: " ..tos(tabControl.controlName))

    local subjectName = (tabControl.subjectName ~= nil and tabControl.subjectName) or tbug_glookup(subject)
    if subjectName ~= nil then
        tabControl.subjectName = subjectName
    end
d(">subjectName: " ..tos(tabControl.subjectName))

    --Get the currently active tab's breadcrumbs, to keep them in the total breadcrumbs list of the new tab
    if tabControlCurrentlyActive ~= nil then
        if tabControlCurrentlyActive.breadCrumbs ~= nil then
            tabControl.breadCrumbs = ZO_ShallowTableCopy(tabControlCurrentlyActive.breadCrumbs)
d(">>copied currentlyActive breadcrumbs to tabControl.breadCrumbs")
        end
    end
    --Add new tab's breadcrumbs
    if tabControl.breadCrumbs == nil then
        tabControl.breadCrumbs = {}
d(">>>created new empty tabControl.breadCrumbs")
    end

    local newTabsBreadCrumbData = {
        _tabControl = tabControl,
        controlName = controlName,
        subjectName = subjectName,
        parentSubjectName = parentSubjectName,
        pKeyStr = tabControl.pKeyStr,
    }
d(">>>>adding breadCrumbs - newTabsBreadCrumbData")
    tins(tabControl.breadCrumbs, newTabsBreadCrumbData)
end

--------------------------------
-- class ObjectInspectorPanel --
local classes = tbug.classes
local BasicInspectorPanel = classes.BasicInspectorPanel
local ObjectInspectorPanel = classes.ObjectInspectorPanel .. BasicInspectorPanel

--Update the table tbug.panelClassNames with the ObjectInspectorPanel class
tbug.panelClassNames["objectInspector"] = ObjectInspectorPanel


local function valueEdit_OnEnter(editBox)
    editBox.panel:valueEditConfirm(editBox)
end


local function valueEdit_OnFocusLost(editBox)
    editBox.panel:valueEditCancel(editBox)
end


local function valueEdit_OnTextChanged(editBox)
    editBox.panel:valueEditUpdate(editBox)
end

local function valueSlider_OnEnter(sliderCtrl)
--d("valueSlider_OnEnter")
    return sliderCtrl.panel:valueSliderConfirm(sliderCtrl)
end


local function valueSlider_OnFocusLost(sliderCtrl)
--d("valueSlider_OnFocusLost")
    sliderCtrl.panel:valueSliderCancel(sliderCtrl)
end


local function valueSlider_OnValueChanged(sliderCtrl)
--d("valueSlider_OnValueChanged")
    sliderCtrl.panel:valueSliderUpdate(sliderCtrl)
end


function ObjectInspectorPanel:__init__(control, ...)
    BasicInspectorPanel.__init__(self, control, ...)

    self:initScrollList(control)
    local contentsOfList = self.list.contents
    self:createValueEditBox(contentsOfList)
    self:createValueSliderControl(contentsOfList)

    cm:RegisterCallback("tbugChanged:typeColor", function() self:refreshVisible() end)
end


--Edit box control
function ObjectInspectorPanel:createValueEditBox(parent)
    local editBox = wm:CreateControlFromVirtual("$(parent)ValueEdit", parent,
                                                "ZO_DefaultEdit")
    self.editBox = editBox
    self.editData = nil
    self.editBoxActive = nil
    editBox.panel = self

    editBox:SetDrawLevel(10)
    editBox:SetMaxInputChars(1024) -- hard limit in ESO 2.1.7
    editBox:SetFont("ZoFontGameSmall")
    editBox:SetHandler("OnEnter", valueEdit_OnEnter)
    editBox:SetHandler("OnFocusLost", valueEdit_OnFocusLost)
    editBox:SetHandler("OnTextChanged", valueEdit_OnTextChanged)
end

function ObjectInspectorPanel:anchorEditBoxToListCell(editBox, listCell)
    editBox:ClearAnchors()
    editBox:SetAnchor(TOPRIGHT, listCell, TOPRIGHT, 0, 4)
    editBox:SetAnchor(BOTTOMLEFT, listCell, BOTTOMLEFT, 0, -3)
    listCell:SetHidden(true)
    self.sliderCtrlActive = false
end

function ObjectInspectorPanel:valueEditCancel(editBox)
    ClearMenu()
    local editData = self.editData
    if editData then
        self.editData = nil
        ZO_ScrollList_RefreshVisible(self.list, editData)
    end
    editBox:SetHidden(true)
    editBox.updatedColumn = nil
    editBox.updatedColumnIndex = nil
    self.editBoxActive = false
end


function ObjectInspectorPanel:valueEditConfirm(editBox)
    ClearMenu()
    local expr = editBox:GetText()
--df("tbug: edit confirm: %s", expr)
    if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
        if self.editData and self.editData.dataEntry and self.editData.dataEntry.typeId == tbug.RT.SCRIPTHISTORY_TABLE then
            self:valueEditConfirmed(editBox, expr)
            return
        end
    end

    local func, err = zo_loadstring("return " .. expr)
    if not func then
        df("|c%stbug: %s", RED:ToHex(), err)
        return
    end

    local ok, evalResult = pcall(setfenv(func, tbug.env))
    if not ok then
        df("|c%stbug: %s", RED:ToHex(), evalResult)
        return
    end

    local err = self:valueEditConfirmed(editBox, evalResult)
    if err then
        df("|c%stbug: %s", RED:ToHex(), err)
    end
end


function ObjectInspectorPanel:valueEditConfirmed(editBox, evalResult)
    return "valueEditConfirmed: intended to be overridden"
end


function ObjectInspectorPanel:valueEditStart(editBox, row, data, cValRow, columnIndex)
--[[
tbug._clickedRow = {
    self = self,
    editBox = editBox,
    row = row,
    data = data,
    slider = self.sliderControl,
}
]]
    if self.editData ~= data then
        editBox.updatedColumn = nil
        editBox.updatedColumnIndex = nil
        editBox:LoseFocus()

        --df("tbug: edit start")
        if MouseIsOver(row.cVal) then
            cValRow = row.cVal
            columnIndex = 1
        elseif MouseIsOver(row.cVal2) then
            cValRow = row.cVal2
            columnIndex = 2
        end
        if cValRow ~= nil then
            local prop = data.prop
            local key = data.key
            local sliderData = (prop ~= nil and prop.sliderData) or nil
            if sliderData == nil then sliderData = (key ~= nil and tbug_isSliderEnabledByRowKey[data.key]) or nil end
            --The row should show a number slider to change the values?
            if (sliderData ~= nil and self.sliderData ~= data) then
                --Slider is currently active? Cancel it
                local sliderCtrl = self.sliderControl
                if self.sliderCtrlActive then
                    self:valueSliderCancel(sliderCtrl)
                end

                --sliderData={min=0, max=1, step=0.1}
                self.sliderSetupData = sliderData
                local sliderSetupData = self.sliderSetupData
                --d(">slider should show: " ..tos(sliderData.min) .."-"..tos(sliderData.max) .. ", step: " ..tos(sliderData.step))
                sliderCtrl.updatedColumn = cValRow
                sliderCtrl.updatedColumnIndex = columnIndex
                --sliderCtrl:SetValue(roundDecimalToPlace(2, tonumber(cValRow:GetText())))
                local currentValue = tonumber(cValRow:GetText())
                --d(">currentValue: " ..tos(currentValue))
                local currentValueClamped = clampValue(currentValue, tonumber(sliderSetupData.min), tonumber(sliderSetupData.max))
                --d(">currentValueClamped: " ..tos(currentValue))
                local currentValueRounded = roundDecimalToPlace(currentValueClamped, 2)
                --d(">currentValueRounded: " ..tos(currentValue))
                sliderCtrl:SetMinMax(tonumber(sliderSetupData.min), tonumber(sliderSetupData.max))
                sliderCtrl:SetValueStep(tonumber(sliderSetupData.step))
                sliderCtrl:SetValue(tonumber(currentValueRounded))
                self:anchorSliderControlToListCell(sliderCtrl, cValRow)
                self.sliderData = data
            end
            if not self.sliderCtrlActive == true then
                editBox.updatedColumn = cValRow
                editBox.updatedColumnIndex = columnIndex
                editBox:SetText(cValRow:GetText())
                editBox:SetHidden(false)
                editBox:TakeFocus()
                self:anchorEditBoxToListCell(editBox, cValRow)
                self.editData = data
            end
        end
    end
    return self.sliderCtrlActive
end


function ObjectInspectorPanel:valueEditUpdate(editBox)
    ClearMenu()
    local expr = editBox:GetText()
    if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
        if self.editData and self.editData.dataEntry and self.editData.dataEntry.typeId == tbug.RT.SCRIPTHISTORY_TABLE then
            return
        end
    end
    local func, err = zo_loadstring("return " .. expr)
    -- syntax check only, no evaluation yet
    if func then
        editBox:SetColor(BLUE:UnpackRGBA())
    else
        editBox:SetColor(RED:UnpackRGBA())
    end
end


--Slider control
function ObjectInspectorPanel:createValueSliderControl(parent)
    local sliderControl = wm:CreateControlFromVirtual("$(parent)ValueSlider", parent,
                                                "tbugValueSlider")
    self.sliderControl = sliderControl
    self.sliderSetupData = nil
    self.sliderData = nil
    self.sliderCtrlActive = nil
    sliderControl.panel = self
    self.sliderSaveButton = GetControl(sliderControl, "SaveButton")
    self.sliderSaveButton:SetHandler("OnMouseUp", function(sliderSaveButtonControl, mouseButton, upInside, shift, ctrl, alt, command)
        if mouseButton == MOUSE_BUTTON_INDEX_LEFT and upInside then
            local sliderRowPanel = sliderControl.panel
            --Save the current chosen value of the slider
            --Update the value to the row label
            local wasConfirmed = valueSlider_OnEnter(sliderControl)
            if wasConfirmed == true then
                valueSlider_OnFocusLost(sliderControl)
            end
        end
    end)
    self.sliderCancelButton = GetControl(sliderControl, "CancelButton")
    self.sliderCancelButton:SetHandler("OnMouseUp", function(sliderSaveButtonControl, mouseButton, upInside, shift, ctrl, alt, command)
        --Cancel teh value slider update
        if mouseButton == MOUSE_BUTTON_INDEX_LEFT and upInside then
            valueSlider_OnFocusLost(sliderControl)
        end
    end)


    sliderControl:SetDrawLevel(10)
    sliderControl:SetHandler("OnEnter", valueSlider_OnEnter)
    sliderControl:SetHandler("OnValueChanged", valueSlider_OnValueChanged)
end

function ObjectInspectorPanel:anchorSliderControlToListCell(sliderControl, listCell)
--d("tbug: anchorSliderControlToListCell")
    sliderControl:ClearAnchors()
    sliderControl:SetAnchor(TOPRIGHT, listCell, TOPRIGHT, -80, 4)
    sliderControl:SetAnchor(BOTTOMLEFT, listCell, BOTTOMLEFT, 100, -3) --anchor offset 100 pixel to the right to see the original value
    --listCell:SetHidden(true)
    sliderControl:SetHidden(false)
    self.sliderCtrlActive = true
end

function ObjectInspectorPanel:valueSliderConfirm(sliderCtrl)
    if not self.sliderCtrlActive then return end
    ClearMenu()
    local expr = tos(sliderCtrl:GetValue())
    local sliderSetupData = self.sliderSetupData
    expr = clampValue(expr, sliderSetupData.min, sliderSetupData.max)
    expr = roundDecimalToPlace(expr, 2)
--df("tbug: slider confirm: %s", expr)
    --[[
    if sliderCtrl.updatedColumn ~= nil and sliderCtrl.updatedColumnIndex ~= nil then
        if self.sliderData  then
            --self:valueSliderConfirmed(sliderCtrl, expr)
            return
        end
    end
    ]]

    local func, err = zo_loadstring("return " .. expr)
    if not func then
        df("|c%stbug: %s", RED:ToHex(), err)
        return
    end
--d(tos(func()))
    local ok, evalResult = pcall(setfenv(func, tbug.env))
    if not ok then
        df("|c%stbug: %s", RED:ToHex(), evalResult)
        return
    end
--d(">evalResult: " .. tos(evalResult))
    local err = self:valueSliderConfirmed(sliderCtrl, evalResult)
    if err then
        df("|c%stbug: %s", RED:ToHex(), err)
    else
        return true
    end
end


function ObjectInspectorPanel:valueSliderUpdate(sliderCtrl)
    if not self.sliderCtrlActive then return end
    ClearMenu()
    ZO_Tooltips_HideTextTooltip()
    local expr = tos(sliderCtrl:GetValue())
    local sliderSetupData = self.sliderSetupData
    expr = clampValue(expr, sliderSetupData.min, sliderSetupData.max)
    expr = roundDecimalToPlace(expr, 2)
--d("tbug: slider update - value: " ..tos(expr))
    --[[
        if sliderCtrl.updatedColumn ~= nil and sliderCtrl.updatedColumnIndex ~= nil then
            if self.sliderData  then
                return
            end
        end
    ]]
    --Show a tooltip at the slider
    ZO_Tooltips_ShowTextTooltip(sliderCtrl, TOP, tos(expr))

    local func, err = zo_loadstring("return " .. expr)
    -- syntax check only, no evaluation yet
    if func then
        sliderCtrl:SetColor(BLUE:UnpackRGBA())
    else
        sliderCtrl:SetColor(RED:UnpackRGBA())
    end
end

function ObjectInspectorPanel:valueSliderConfirmed(sliderControl, evalResult)
    if not self.sliderCtrlActive then return end
--d("tbug: slider confirmed")
    return "valueSliderConfirmed: intended to be overridden"
end

function ObjectInspectorPanel:valueSliderCancel(sliderCtrl)
    if not self.sliderCtrlActive then return end
--d("tbug: slider cancel")
    ClearMenu()
    local sliderData = self.sliderData
    if sliderData then
        self.sliderData = nil
        ZO_ScrollList_RefreshVisible(self.list, sliderData)
    end
    sliderCtrl:SetHidden(true)
    sliderCtrl.updatedColumn = nil
    sliderCtrl.updatedColumnIndex = nil
    self.sliderCtrlActive = false
end



function ObjectInspectorPanel:reset()
    tbug.truncate(self.masterList, 0)
    ZO_ScrollList_Clear(self.list)
    self:commitScrollList()
    self.control:SetHidden(true)
    self.control:ClearAnchors()
    self.subject = nil
end


function ObjectInspectorPanel:setupRow(row, data)
    BasicInspectorPanel.setupRow(self, row, data)

    if self.editData == data then
        self:anchorEditBoxToListCell(self.editBox, row.cVal)
    else
        if row.cVal then
            row.cVal:SetHidden(false)
        end
        if row.cVal2 then
            row.cVal2:SetHidden(false)
        end
    end
end


---------------------------
-- class ObjectInspector --
local BasicInspector = classes.BasicInspector
local ObjectInspector = classes.ObjectInspector .. BasicInspector

ObjectInspector._activeObjects = {}
ObjectInspector._inactiveObjects = {}
ObjectInspector._nextObjectId = 1
ObjectInspector._templateName = "tbugTabWindow"


function ObjectInspector.acquire(Class, subject, name, recycleActive, titleName, data)
    --local lastActive = (Class ~= nil and Class._lastActive ~= nil and true) or false
    --local lastActiveSubject = (lastActive == true and Class._lastActive.subject ~= nil and true) or false
--d("[TBUG]ObjectInspector.acquire-name: " ..tos(name) .. ", recycleActive: " ..tos(recycleActive) .. ", titleName: " ..tos(titleName) .. ", lastActive: " ..tos(lastActive) .. ", lastActiveSubject: " ..tos(lastActiveSubject))
    local inspector = Class._activeObjects[subject]
    if not inspector then
        if recycleActive and Class._lastActive and Class._lastActive.subject then
            inspector = Class._lastActive
            Class._activeObjects[inspector.subject] = nil
        else
            inspector = table.remove(Class._inactiveObjects)
            if not inspector then
                local id = Class._nextObjectId
                local templateName = Class._templateName
--d(">templateName: " ..tos(templateName))
                local controlName = templateName .. id
                local control = wm:CreateControlFromVirtual(controlName, nil,
                                                            templateName)
                Class._nextObjectId = id + 1
                inspector = Class(id, control)
            end
            if Class._lastActive then
                Class._lastActive.titleIcon:SetDesaturation(0)
            end
            Class._lastActive = inspector
            Class._lastActive.titleIcon:SetDesaturation(1)
        end
        Class._activeObjects[subject] = inspector
        inspector.subject = subject
        inspector._parentSubject = (data ~= nil and data._parentSubject) or nil
        inspector.subjectName = name
        inspector.titleName = titleName
    end
    return inspector
end


function ObjectInspector:__init__(id, control)
    BasicInspector.__init__(self, id, control)

    self.conf = tbug.savedTable("objectInspector" .. id)
    self:configure(self.conf)

    --self.subjectsToPanel = {}
end

function ObjectInspector:openTabFor(object, title, inspectorTitle, useInspectorTitel, data, isMOC)
    useInspectorTitel = useInspectorTitel or false
    local newTabIndex = 0
    local panel, tabControl
    --local parentSubjectFound = (data ~= nil and data._parentSubject ~= nil and true) or false
--d("[tbug:openTabFor]title: " ..tos(title) .. ", inspectorTitle: " ..tos(inspectorTitle) .. ", useInspectorTitel: " ..tos(useInspectorTitel) .. ", data._parentSubject: " ..tos(parentSubjectFound) .. ", isMOC: " ..tos(isMOC))
    -- the global table should only be viewed in GlobalInspector
    if rawequal(object, _G) then
        local inspector = tbug.getGlobalInspector()
        if inspector.control:IsHidden() then
            inspector.control:SetHidden(false)
            inspector:refresh()
        end
        inspector.control:BringWindowToTop()
        return
    end

    --Get timestanp when this tab should be opened
    -->Will be added to the tabControl if the tab is created NEW (not updated)
    local timeStamp = GetTimeStamp()

    -- try to find an existing tab inspecting the given object
    for tabIndex, tabControlLoop in ipairs(self.tabs) do
        if rawequal(tabControlLoop.panel.subject, object) then
--d(">found existing tab by object -> Selecting it now")
            self:selectTab(tabControlLoop, isMOC)
            return tabControlLoop
        elseif tabControlLoop == self.activeTab then
            newTabIndex = tabIndex + 1
        end
    end

--df("[ObjectInspector:openTabFor]object %s, title: %s, inspectorTitle: %s, newTabIndex: %s", tos(object), tos(title), tos(inspectorTitle), tos(newTabIndex))


    if type(object) == "table" then
--d(">table")
        title = tbug_glookup(object) or title or tos(object)
        if title and title ~= "" and not endsWith(title, "[]") then
            title = title .. "[]"
        end
        panel = self:acquirePanel(classes.TableInspectorPanel)
    elseif tbug.isControl(object) then
--d(">control")
        title = title or getControlName(object)
        panel = self:acquirePanel(classes.ControlInspectorPanel)
    end

    if panel ~= nil then
--d(">>panel found")
        local newAddedData = {
            timeStamp =     timeStamp,
            --timeStampStr =  nil,
        }

        --Add a new tab to the horizontal tab scrollbar
        tabControl = self:insertTab(title, panel, newTabIndex, inspectorTitle, useInspectorTitel, nil, isMOC, newAddedData)
--d(">>insertTab was done")
        --Add the currently inspected control/object as subject to the panel
        panel.subject = object
        --Add the data to the tab too
        tabControl.subject = object
        local parentSubject = (data ~= nil and data._parentSubject) or nil
        panel._parentSubject = parentSubject
        tabControl.parentSubject = parentSubject

        --Add the breadCrumbs for an easier navigation and to show the order of clicked controls/tables/data at each tab's title

--todo: 20230122 Breadcrumbs of 2nd MOC tab will be adding 1st MOC tab's breadcrumbs?
--todo: I guess one needs to check if the tab opened was opened from MOC or not, and do not add breadcrumbs if it was MOC, as this counts as a "new" inspector process then
--todo: only opened from clicking tabs/controls/etc. in the inspectors should update the breadcrumbs!
        updateTabBreadCrumbs(tabControl, self.activeTab)

        --self.subjectsToPanel = self.subjectsToPanel or {}
        --self.subjectsToPanel[panel.subject] = panel
        panel:refreshData()
        self:selectTab(tabControl, isMOC)
    end

    return tabControl
end


function ObjectInspector:refresh(isMOC)
    --df("tbug: refreshing %s (%s / %s)", tos(self.subject), tos(self.subjectName), tos(self.titleName))
    --d("[tbug]ObjectInspector:refresh")
    self:removeAllTabs()
    local data = {}
    data._parentSubject = self._parentSubject
    self:openTabFor(self.subject, self.subjectName, self.titleName, nil, data, isMOC)
end


function ObjectInspector:release()
    --d("[tbug]ObjectInspector:release")
    if self.subject then
        self._activeObjects[self.subject] = nil
        --self.subjectsToPanel[self.subject] = nil
        self.subject = nil
        tins(self._inactiveObjects, self)
    end
    self._parentSubject = nil
    self.control:SetHidden(true)
    self:removeAllTabs()
end
