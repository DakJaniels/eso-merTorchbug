local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

local tsort = table.sort

local classes = tbug.classes
local BasicInspector = classes.BasicInspector
local GlobalInspector = classes.GlobalInspector .. BasicInspector

local panelClassName2panelClass = tbug.panelClassNames
local panelNames = tbug.panelNames
local getTBUGGlobalInspectorPanelIdByName = tbug.getTBUGGlobalInspectorPanelIdByName

local checkIfItemLinkFunc = tbug.checkIfItemLinkFunc
local sortItemLinkFunctions = tbug.sortItemLinkFunctions

--------------------------------

function tbug.getGlobalInspector(doNotCreate)
    doNotCreate = doNotCreate or false
    local inspector = tbug.globalInspector
    if not inspector and doNotCreate == false then
        inspector = GlobalInspector(1, tbugGlobalInspector)
        tbug.globalInspector = inspector
    end
    return inspector
end

--------------------------------
-- class GlobalInspectorPanel --
local TableInspectorPanel = classes.TableInspectorPanel
local GlobalInspectorPanel = classes.GlobalInspectorPanel .. TableInspectorPanel

GlobalInspectorPanel.CONTROL_PREFIX = "$(parent)PanelG"
GlobalInspectorPanel.TEMPLATE_NAME = "tbugTableInspectorPanel"

--Update the table tbug.panelClassNames with the GlobalInspectorPanel class
tbug.panelClassNames["globalInspector"] = GlobalInspectorPanel


local RT = tbug.RT


function GlobalInspectorPanel:buildMasterList()
d("[TBug]GlobalInspector:buildMasterList")
    self:buildMasterListSpecial()
end


---------------------------
-- class GlobalInspector --

function GlobalInspector:__init__(id, control)
    control.isGlobalInspector = true
    BasicInspector.__init__(self, id, control)

    self.conf = tbug.savedTable("globalInspector" .. id)
    self:configure(self.conf)

    self.title:SetText("GLOBALS")

    self.panels = {}
    self:connectPanels(nil, false, false, nil)
    self:selectTab(1)
end


function GlobalInspector:connectFilterComboboxToPanel(tabIndex)
--d("[TBUG]GlobalInspector:connectFilterComboboxToPanel-tabIndex: " ..tostring(tabIndex))
    --Prepare the combobox filters at the panel
    local comboBoxCtrl = self.filterComboBox
    local comboBox = ZO_ComboBox_ObjectFromContainer(comboBoxCtrl)
    --local dropdown = self.filterComboBoxDropdown
    --Clear the combobox/dropdown
    --dropdown:HideDropdownInternal()
    comboBox:ClearAllSelections()
    comboBox:ClearItems()
    self:SetSelectedFilterText()
    comboBoxCtrl:SetHidden(true)
    comboBox.filterMode = nil

    if not tabIndex then return end
    local tabIndexType = type(tabIndex)
    if tabIndexType == "number" then
        --All okay
    elseif tabIndexType == "string" then
        --Get pael's tabIndex number
        tabIndex = getTBUGGlobalInspectorPanelIdByName(tabIndex)
    else
        --Error
        return
    end
    comboBox.filterMode = tabIndex

    local panelData = panelNames[tabIndex]
    if not panelData then return end

    if panelData.comboBoxFilters == true then
        --Get the filter data to add to the combobox - TOOD: Different filters, by panel!
        local filterDataToAdd = tbug.filterComboboxFilterTypesPerPanel[tabIndex]
--TBUG._filterDataToAdd = filterDataToAdd
        --Add the filter data to the combobox's dropdown
        for controlType, controlTypeName in pairs(filterDataToAdd) do
            if type(controlType) == "number" and controlType > -1 then
                local entry = comboBox:CreateItemEntry(controlTypeName)
                entry.filterType = controlType
                comboBox:AddItem(entry)
            end
        end
        --Update the (last) selected entries (if any filtered before)
        local panelOfComboboxFilter = self.panels[panelData.key] --Get the panel of the tab with tabIndex
        local dropdownFiltersSelected = panelOfComboboxFilter.dropdownFiltersSelected
        local ignoreCallback = true
        if not ZO_IsTableEmpty(dropdownFiltersSelected) then
            for selectedFilterType, wasSelected in pairs(dropdownFiltersSelected) do
                if wasSelected then
--d(">selected comboboxFilter filterType before: " ..tostring(selectedFilterType))
                    comboBox:SetSelectedItemByEval(function(item) return item.filterType == selectedFilterType end, ignoreCallback)
                end
            end
        end
        comboBoxCtrl:SetHidden(false)
    end
end


------------------------ Other functions of the class
function GlobalInspector:makePanel(title, panelData)
    local panelClass = GlobalInspectorPanel
    local panelClassName
    if panelData ~= nil then
        panelClassName = panelData.panelClassName
        if panelClassName ~= nil and panelClassName ~= "" then
            panelClass = panelClassName2panelClass[panelClassName]
            if panelClass == nil then
                panelClass = GlobalInspectorPanel --fallback: GlobalInspectorPanel
            end
        end
    end
--d("[TB]makePanel-title: " ..tostring(title) .. ", panelClass: " ..tostring(panelClass) .. ", panelClassName: " ..tostring(panelClassName))

    local panel = self:acquirePanel(panelClass)
    --local tabControl = self:insertTab(title, panel, 0)
    self:insertTab(title, panel, 0, nil, nil, true, false)
    return panel
end

function GlobalInspector:connectPanels(panelName, rebuildMasterList, releaseAllTabs, tabIndex)
d("[TBug]GlobalInspector:connectPanels - panelName: " .. tostring(panelName) ..", rebuildMasterList: " .. tostring(rebuildMasterList))
    rebuildMasterList = rebuildMasterList or false
    releaseAllTabs = releaseAllTabs or false
    if not self.panels then return end
    if releaseAllTabs == true then
        self:removeAllTabs()
    end
    for idx,v in ipairs(panelNames) do
        if releaseAllTabs == true then
            self.panels[v.key]:release()
        end
        --Use the fixed tabIndex instead of the name? For e.g. tabs where the text on the tab does not match the key (sv <-> SV, or Sv entered as slash command /tbug sv to re-create the tab)
        if tabIndex ~= nil and idx == tabIndex then
            --d(">connectPanels-panelName: " ..tos(panelName) .. ", tabIndex: " ..tos(tabIndex))
            --d(">>make panel for v.key: " ..tos(v.key) .. ", v.name: " ..tos(v.name))
            self.panels[v.key] = self:makePanel(v.name, v)
            --[[
            --Do not refresh ALL panels in the loop each time!
            if rebuildMasterList == true then
                self:refresh()
            end
            ]]
        --Use the tab's name / or at creation of all tabs -> we will get here
        else
            if panelName and panelName ~= "" then
                if v.name == panelName then
                    self.panels[v.key] = self:makePanel(v.name, v)
                    --[[
                    --Do not refresh ALL panels here. They should be refreshed either way as their tab gets selected?!
                    if rebuildMasterList == true then
                        self:refresh()
                    end
                    ]]
                    return
                end
            else
                --Create all the tabs
                self.panels[v.key] = self:makePanel(v.name, v)
            end
        end
    end

    if rebuildMasterList == true then
d(">[TBug]GlobalInspector:connectPanels -> Calling refresh of all tabs!")
        self:refresh()
    end
end

local function pushToMasterlist(masterList, dataType, key, value)
    local data = {key = key, value = value}
    local n = #masterList + 1
    masterList[n] = ZO_ScrollList_CreateDataEntry(dataType, data)
end

function GlobalInspector:refresh()
d("[TBug]GlobalInspector:refresh")

    local panels       = self.panels
    local panelClasses = panels.classes:clearMasterList(_G) --Set's the subject to _G
    local controls     = panels.controls:clearMasterList(_G)  --Set's the subject to _G
    local fonts = panels.fonts:clearMasterList(_G)  --Set's the subject to _G
    local functions = panels.functions:clearMasterList(_G)  --Set's the subject to _G
    local objects = panels.objects:clearMasterList(_G)  --Set's the subject to _G
    local constants = panels.constants:clearMasterList(_G)  --Set's the subject to _G

    local itemLinkFunctionsUpdated = false

    --Refresh ALL tab's data!
    for k, v in zo_insecureNext, _G do
        local tv = type(v)
        if tv == "userdata" then
            if v.IsControlHidden then
                pushToMasterlist(controls, RT.GENERIC, k, v)
            elseif v.GetFontInfo then
                pushToMasterlist(fonts, RT.FONT_OBJECT, k, v)
            else
                pushToMasterlist(objects, RT.GENERIC, k, v)
            end
        elseif tv == "table" then
            if rawget(v, "__index") then
                pushToMasterlist(panelClasses, RT.GENERIC, k, v)
            else
                pushToMasterlist(objects, RT.GENERIC, k, v)
            end
        elseif tv == "function" then
            pushToMasterlist(functions, RT.GENERIC, k, v)
            --Check if functionName is starting with IsItemLink or GetItemLink or CheckItemLink or *Itemlink*
            --and add them to the itemLinkFunctions table for later context menu usage
            -->Will add it to tbug.functionsItemLink
            local l_updated = checkIfItemLinkFunc(k, v) --> Should have been filled in glookup.lua already while parsing the _G table. Only adding missing ones here
            if l_updated == true then itemLinkFunctionsUpdated = true end
        elseif tv ~= "string" or type(k) ~= "string" then
            pushToMasterlist(constants, RT.GENERIC, k, v)
        elseif IsPrivateFunction(k) then
            pushToMasterlist(functions, RT.GENERIC, k, "function: private")
        elseif IsProtectedFunction(k) then
            pushToMasterlist(functions, RT.GENERIC, k, "function: protected")
        else
            pushToMasterlist(constants, RT.GENERIC, k, v)
        end
    end

    if itemLinkFunctionsUpdated == true then
        sortItemLinkFunctions()
    end


    --Also check TableInspectorPanel:buildMasterListSpecial() for the special types of masterLists!
    panels.dialogs:bindMasterList(_G.ESO_Dialogs, RT.GENERIC)
    panels.strings:bindMasterList(_G.EsoStrings, RT.LOCAL_STRING)
    panels.sounds:bindMasterList(_G.SOUNDS, RT.SOUND_STRING)

    tbug.refreshScenes()
    panels.scenes:bindMasterList(tbug.ScenesOutput, RT.SCENES_TABLE) --_G.SCENE_MANAGER.scenes
    panels.fragments:bindMasterList(tbug.FragmentsOutput, RT.FRAGMENTS_TABLE)

    panels.libs:bindMasterList(tbug.LibrariesOutput, RT.LIB_TABLE)
    panels.addons:bindMasterList(tbug.AddOnsOutput, RT.ADDONS_TABLE)

    tbug.refreshScripts()
    panels.scriptHistory:bindMasterList(tbug.ScriptsData, RT.SCRIPTHISTORY_TABLE)
    tbug.RefreshTrackedEventsList()
    panels.events:bindMasterList(tbug.Events.eventsTable, RT.EVENTS_TABLE)

    panels.sv:bindMasterList(tbug.SavedVariablesOutput, RT.SAVEDVARIABLES_TABLE)

    tbug.refreshSavedInspectors()
    panels.savedInsp:bindMasterList(tbug.SavedInspectorsData, RT.SAVEDINSPECTORS_TABLE)

    for _, panel in next, panels do
        panel:refreshData()
    end
end


function GlobalInspector:release()
    -- do not release anything
    self.control:SetHidden(true)
end