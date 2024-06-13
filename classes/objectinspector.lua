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
local isControl = tbug.isControl
local hideContextMenus = tbug.HideContextMenus

local tbug_isSliderEnabledByRowKey = tbug.isSliderEnabledByRowKey
local valueEdit_CancelThrottled = tbug.valueEdit_CancelThrottled
local valueSlider_CancelThrottled = tbug.valueSlider_CancelThrottled

local RT= tbug.RT
local editConfirmAllowedTypes = {
    [RT.SCRIPTHISTORY_TABLE] = true,
    [RT.SAVEDINSPECTORS_TABLE] = true,
}

--------------------------------
local function roundDecimalToPlace(decimal, place)
    return tonumber(string.format("%." .. tos(place) .. "f", decimal))
end

local function clampValue(value, min, max)
    return math.max(math.min(value, max), min)
end

local function updateTabBreadCrumbs(tabControl, tabControlCurrentlyActive, isMOC, useInspectorTitel)
    isMOC = isMOC or false
    useInspectorTitel = useInspectorTitel or false
--d("[TB]updateTabBreadCrumbs-tabControlCurrentlyActive: " ..tos(tabControlCurrentlyActive) .. ", isMOC: " ..tos(isMOC))
    tbug_glookup = tbug_glookup or tbug.glookup

    local parentSubject = tabControl.parentSubject
    local parentSubjectName = (parentSubject ~= nil and tabControl.parentSubjectName) or nil
    if parentSubject ~= nil and parentSubjectName == nil then
        parentSubjectName = getRelevantNameForCall(parentSubject)
        tabControl.parentSubjectName = parentSubjectName
    end
--d(">parentSubjectName: " ..tos(tabControl.parentSubjectName))
    local subject = tabControl.subject
    if subject == nil then return end

    local controlName = (tabControl.controlName ~= nil and tabControl.controlName) or getControlName(subject)
    if controlName ~= nil then
        tabControl.controlName = controlName
    end
--d(">controlName: " ..tos(tabControl.controlName))

    local subjectName = (tabControl.subjectName ~= nil and tabControl.subjectName) or tbug_glookup(subject)
    if subjectName ~= nil then
        tabControl.subjectName = subjectName
    end
--d(">subjectName: " ..tos(tabControl.subjectName))

    --Get the currently active tab's breadcrumbs, to keep them in the total breadcrumbs list of the new tab
    if tabControlCurrentlyActive ~= nil and not isMOC then
        if tabControlCurrentlyActive.breadCrumbs ~= nil then
            tabControl.breadCrumbs = ZO_ShallowTableCopy(tabControlCurrentlyActive.breadCrumbs)
--d(">>copied currentlyActive breadcrumbs to tabControl.breadCrumbs")
        end
    end
    --Add new tab's breadcrumbs
    if tabControl.breadCrumbs == nil or isMOC == true then
        tabControl.breadCrumbs = {}
--d(">>>created new empty tabControl.breadCrumbs")
    end

    --Save the values in case the tabControl get's closed -> references would be removed too
    local pKeyStr =     tabControl.pKeyStr
    local titleClean =  tabControl.titleClean
    local childName =   tabControl.childName
    if useInspectorTitel == true and tabControl.inspectorTitle ~= nil and titleClean ~= tabControl.inspectorTitle then
        titleClean = tabControl.inspectorTitle
    end

    local newTabsBreadCrumbData = {
        _tabControl =       tabControl,
        controlName =       controlName,
        subject =           subject,
        subjectName =       subjectName,
        parentSubject =     parentSubject,
        parentSubjectName = parentSubjectName,
        pKeyStr =           pKeyStr,
        titleClean =        titleClean,
        childName =         childName
    }
--d(">>>>adding breadCrumbs - newTabsBreadCrumbData")
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
    --2040603 Fix LibScrollableMenu clicked entry having upInside = false -> maybe because the focus of the editbox is lost and then the scrolllist updates and the contextmenu closes?
    --Delay it a bit so the context menu can work properly
    -->This throttledCall should get overwritten from context menu's: tbug.setChatEditTextFromContextMenu
    valueEdit_CancelThrottled(editBox, 75)
end


local function valueEdit_OnTextChanged(editBox)
    editBox.panel:valueEditUpdate(editBox)
end

local function valueSlider_OnEnter(sliderCtrl)
d("valueSlider_OnEnter")
    return sliderCtrl.panel:valueSliderConfirm(sliderCtrl)
end


local function valueSlider_OnFocusLost(sliderCtrl)
d("valueSlider_OnFocusLost")
    valueSlider_CancelThrottled(sliderCtrl, 75)
    --sliderCtrl.panel:valueSliderCancel(sliderCtrl)
end


local function valueSlider_OnValueChanged(sliderCtrl)
d("valueSlider_OnValueChanged")
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
    editBox:SetHandler("OnFocusLost",   valueEdit_OnFocusLost)
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
d("[tbug]ObjectInspectorPanel:valueEditCancel - editBox: " ..tos(editBox:GetText()))
    --hideContextMenus()
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
    hideContextMenus()
    local expr = editBox:GetText()
df("tbug: edit confirm: %s", expr)
    if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
        if self.editData and self.editData.dataEntry and editConfirmAllowedTypes[self.editData.dataEntry.typeId] then
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
--d("[tbug]]ObjectInspectorPanel:valueEditStart - editBoxActive: " ..tos(self.editBoxActive))
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
        --todo 20240603 - Why is the 2nd right clicked row's text hiding?
        if self.editBoxActive then
            --self:valueSliderCancel(sliderCtrl)
            valueEdit_CancelThrottled(editBox, 0)
        end

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
                    --self:valueSliderCancel(sliderCtrl)
                    valueSlider_CancelThrottled(sliderCtrl, 0)
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

            --Normal editbox
            if not self.sliderCtrlActive == true then
                self.editBoxActive = true
                editBox.updatedColumn = cValRow
                editBox.updatedColumnIndex = columnIndex
--d(">cValRow:GetText(): " ..tos(cValRow:GetText()))
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
d("[tbug]ObjectInspectorPanel:valueEditUpdate - editBox: " ..tos(editBox:GetText()))
    hideContextMenus()

    local expr = editBox:GetText()
    if editBox.updatedColumn ~= nil and editBox.updatedColumnIndex ~= nil then
        if self.editData and self.editData.dataEntry and editConfirmAllowedTypes[self.editData.dataEntry.typeId] then
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
    self.sliderCancelButton:SetHandler("OnMouseUp", function(sliderCancelButtonCtrl, mouseButton, upInside, shift, ctrl, alt, command)
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
d("[tbug]ObjectInspectorPanel:valueSliderConfirm")
    if not self.sliderCtrlActive then return end
    hideContextMenus()
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
d("[tbug]ObjectInspectorPanel:valueSliderUpdate")
    if not self.sliderCtrlActive then return end
    hideContextMenus()
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
d("[tbug]ObjectInspectorPanel:valueSliderCancel")
    if not self.sliderCtrlActive then return end
--d("tbug: slider cancel")
    local sliderData = self.sliderData
    if sliderData then
        self.sliderData = nil
        ZO_ScrollList_RefreshVisible(self.list, sliderData)
        --hideContextMenus()
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

function ObjectInspector:openTabFor(object, title, inspectorTitle, useInspectorTitel, data, isMOC, openedFromExistingInspector)
    useInspectorTitel = useInspectorTitel or false
    openedFromExistingInspector = openedFromExistingInspector or false
    local newTabIndex = 0
    local panel, tabControl

    --Only for debugging:
    local parentSubjectFound = (data ~= nil and data._parentSubject ~= nil and true) or false
    local childNameFound = (data ~= nil and data.childName ~= nil and true) or false
    if tbug.doDebug then d("[tbug:openTabFor]title: " ..tos(title) .. ", inspectorTitle: " ..tos(inspectorTitle) .. ", useInspectorTitel: " ..tos(useInspectorTitel) .. ", _parentSubject: " ..tos(parentSubjectFound) .. ", childNameFound: " .. tos(childNameFound) ..", isMOC: " ..tos(isMOC) .. ", openedFromExistingInspector: " .. tos(openedFromExistingInspector)) end

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

    --Get timestamp when this tab should be opened
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

    local titleClean = title --for the breadCrumbs, without any "[]" suffix etc.
    if type(object) == "table" then
        --d(">table")
        title = tbug_glookup(object) or title or tos(object)
        titleClean = title --for the breadCrumbs
        if title and title ~= "" and not endsWith(title, "[]") then
            title = title .. "[]"
        end
        panel = self:acquirePanel(classes.TableInspectorPanel)
    elseif isControl(object) then
        --d(">control")
        title = title or getControlName(object)
        titleClean = title --for the breadCrumbs
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
        tabControl.titleClean = titleClean
        tabControl.inspectorTitle = inspectorTitle
        local childName = (data ~= nil and data.childName) or nil
        panel.childName = childName
        tabControl.childName = childName
        self.childName = nil -- reset at the inspector again!

        --Add the breadCrumbs for an easier navigation and to show the order of clicked controls/tables/data at each tab's title
        -->Only do that if opened tab is not a MOC and it was opened from clicking any opened inspector's table/control/etc.
        ---> Else they start with an empty breadCrumbs list
        local isNotOpenedFromExistingInspector = ((isMOC == true or not openedFromExistingInspector) and true) or false
        updateTabBreadCrumbs(tabControl, self.activeTab, isNotOpenedFromExistingInspector, useInspectorTitel)

        --self.subjectsToPanel = self.subjectsToPanel or {}
        --self.subjectsToPanel[panel.subject] = panel
        panel:refreshData()
        self:selectTab(tabControl, isMOC)
    end

    return tabControl
end


function ObjectInspector:refresh(isMOC, openedFromExistingInspector, wasClickedAtGlobalInspector)
    --df("tbug: refreshing %s (%s / %s)", tos(self.subject), tos(self.subjectName), tos(self.titleName))
    --d("[tbug]ObjectInspector:refresh")
    --self:removeAllTabs() --do not remove all tabs as this will clear the current inspectors tabs if you click something
    --in the global inspector e.g.-> Always happened if tbug.inspect was called, and not inspector:openTabFor!
    local data = {}
    data._parentSubject = self._parentSubject
    data.childName = self.childName
    self:openTabFor(self.subject, self.subjectName, self.titleName, wasClickedAtGlobalInspector, data, isMOC, openedFromExistingInspector)
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
