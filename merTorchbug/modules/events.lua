local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

--Event tracking code was spyed and copied from the addon Zgoo! All credits go to the authors.
--Authors: Errc, SinusPi, merlight, Rhyono

------------------------------------------------------------------------------------------------------------------------
local tbEvents = {}
tbug.Events = tbEvents

------------------------------------------------------------------------------------------------------------------------
--The possible events of the game
tbEvents.eventList = {}
--Lookup table with key&value reversed
tbEvents.eventListLookup = {}

------------------------------------------------------------------------------------------------------------------------
--The events currently tracked/fired list
tbEvents.eventsTable = {}
tbEvents.eventsTableInternal = {}
tbEvents.eventsTableIncluded = {}
tbEvents.eventsTableExcluded = {}

tbEvents.IsEventTracking = false
tbEvents.AreAllEventsRegistered = false

------------------------------------------------------------------------------------------------------------------------
--Local helper pointers
local tinsert, type = table.insert, type

local eventsInspectorControl
local globalInspector

local throttledCall = tbug.throttledCall

------------------------------------------------------------------------------------------------------------------------
--Local helper functions
local l_globalprefixes = function(prefix)
	local strfind = string.find
	local l_safeglobalnext = function(tab,index)
		for k, v in zo_insecureNext, tab, index do
			if type(k) == "string" and strfind(k, prefix, 1, true) == 1 then
				return k, v
			end
		end
	end
	return l_safeglobalnext,_G,nil
end

local function getEventsTrackerInspectorControl()
    if eventsInspectorControl ~= nil then return eventsInspectorControl end
    --Start the event tracking by registering all events
    globalInspector = globalInspector or tbug.getGlobalInspector()
    if not globalInspector then return end
    eventsInspectorControl = globalInspector.panels and globalInspector.panels.events and globalInspector.panels.events.control
    return eventsInspectorControl
end
tbEvents.getEventsTrackerInspectorControl = getEventsTrackerInspectorControl

local function scrollScrollBarToIndex(list, index, animateInstantly)
    if not list then return end
    local onScrollCompleteCallback = function() end
    animateInstantly = animateInstantly or false
    ZO_ScrollList_ScrollDataIntoView(list, index, onScrollCompleteCallback, animateInstantly)
end

local function updateEventTrackerLines()
    --Is the events panel currently visible?
    local eventsPanel = globalInspector.panels.events
    local eventsPanelControl = eventsPanel.control
    if not eventsPanel or (eventsPanel and eventsPanelControl and eventsPanelControl:IsHidden() == true) then return end

    --Add the event to the masterlist of the outpt table
    -->Already called via eventsPanel:refreshData -> BuildMasterList
    --tbug.RefreshTrackedEventsList()

    --Update the visual ZO_ScrollList
    eventsPanel:refreshData()

    --Scroll to the bottom, if scrollbar is needed/shown
    local eventsListOutput = eventsPanel.list
    local numEventsInList = #eventsListOutput.data
    if numEventsInList <= 0 then return end

    local scrollbar = eventsListOutput.scrollbar
    if scrollbar and not scrollbar:IsHidden() then
        scrollScrollBarToIndex(eventsListOutput, numEventsInList, true)
    end

    --Add context menu to each row in the events table
end

------------------------------------------------------------------------------------------------------------------------


--The events tracker functions
function tbEvents.EventHandler(eventId, ...)
    if not tbEvents.IsEventTracking == true then return end

	local lookupEventName = tbEvents.eventList
    local timeStampAdded = GetTimeStamp()
    local frameTime = GetFrameTimeMilliseconds()
    local eventParametersOriginal = {...}
    local eventTab = {}
    eventTab._timeStamp     = timeStampAdded
    eventTab._frameTime     = frameTime
    eventTab._eventName     = lookupEventName[eventId] or "? UNKNOWN EVENT ?"
    eventTab._eventId       = eventId
    for eventParamNo, eventParamValue in ipairs(eventParametersOriginal) do
        eventTab["param" .. tostring(eventParamNo)] = eventParamValue
    end

	local tabPosAdded = tinsert(tbEvents.eventsTableInternal, eventTab)

	--Add the added line to the output list as well, if the list is currently visible!
    throttledCall("UpdateTBUGEventsList", 100, updateEventTrackerLines)
end

--Fill the masterlist of the events output ZO_SortFilterList with the tracked events data rows
function tbug.RefreshTrackedEventsList()
    tbEvents.eventsTable = {}
    local intEventTable = tbEvents.eventsTableInternal
    if intEventTable == nil or #intEventTable == 0 then return end

    for numEventAdded, eventDataTable in ipairs(intEventTable) do
        tbEvents.eventsTable[numEventAdded] = eventDataTable
    end
end

function tbEvents.RegisterAllEvents(inspectorControl, override)
    if not inspectorControl then return end
    override = override or false
    --Event tracking is enabled?
    if not override == true and not tbEvents.IsEventTracking then return end
    --No need to register all events multiple times!
    if tbEvents.AreAllEventsRegistered == true then return end

    for id, _ in pairs(tbEvents.eventList) do
        inspectorControl:RegisterForEvent(id, tbEvents.EventHandler)
    end
    tbEvents.AreAllEventsRegistered = true
end

function tbEvents.UnRegisterAllEvents(inspectorControl, excludedEventsFromUnregisterTable, override)
    if not inspectorControl then return end
    override = override or false
    local keepEventsRegistered = (excludedEventsFromUnregisterTable ~= nil and type(excludedEventsFromUnregisterTable) == "table") or false
    if not keepEventsRegistered then
        if not override == true and tbEvents.IsEventTracking == true then return end
        if not tbEvents.AreAllEventsRegistered then return end
        for id, _ in pairs(tbEvents.eventList) do
            inspectorControl:UnregisterForEvent(id)
        end
        tbEvents.AreAllEventsRegistered = false
    else
        if not override == true and not tbEvents.IsEventTracking == true then return end
        for id, _ in pairs(tbEvents.eventList) do
            inspectorControl:UnregisterForEvent(id)
        end
        for _, eventId in ipairs(excludedEventsFromUnregisterTable) do
            tbEvents.RegisterSingleEvent(inspectorControl, eventId)
        end
    end
end

function tbEvents.UnRegisterSingleEvent(inspectorControl, eventId)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    if not tbEvents.IsEventTracking == true then return end
    inspectorControl:UnregisterForEvent(eventId)
end

function tbEvents.RegisterSingleEvent(inspectorControl, eventId)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    if not tbEvents.IsEventTracking == true then return end
    inspectorControl:RegisterForEvent(eventId, tbEvents.EventHandler)
end

function tbEvents.ReRegisterAllEvents(inspectorControl)
    if not inspectorControl then return end
    --Event tracking is not enabled?
    tbug.Events.eventsTableIncluded = {}
    tbug.Events.eventsTableExcluded = {}
    tbEvents.UnRegisterAllEvents(inspectorControl, nil, true)
    tbEvents.RegisterAllEvents(inspectorControl, true)
end

function tbug.StartEventTracking()
    --Start the event tracking by registering either all events, or if any are excluded/included respect those
    if tbEvents.IsEventTracking == true then return end
    tbEvents.IsEventTracking = true

    eventsInspectorControl = eventsInspectorControl or getEventsTrackerInspectorControl()
    if not eventsInspectorControl then
        tbEvents.IsEventTracking = false
        return
    end
    --Any included "only" to show?
    if #tbEvents.eventsTableIncluded > 0 then
        tbEvents.UnRegisterAllEvents(eventsInspectorControl, nil)
        for _, eventId in ipairs(tbEvents.eventsTableIncluded) do
             tbEvents.RegisterSingleEvent(eventsInspectorControl, eventId)
        end

    --Any excluded to "not" show?
    elseif #tbEvents.eventsTableExcluded > 0 then
        tbEvents.RegisterAllEvents(eventsInspectorControl)
        for _, eventId in ipairs(tbEvents.eventsTableExcluded) do
             tbEvents.UnRegisterSingleEvent(eventsInspectorControl, eventId)
        end

    --Else: Register all events
    else
        tbEvents.RegisterAllEvents(eventsInspectorControl)
    end

    --Show the UI/activate the events tab
    tbug.slashCommandEvents()
end

function tbug.StopEventTracking()
    if not tbEvents.IsEventTracking == true then return false end
    tbEvents.IsEventTracking = false

    eventsInspectorControl = eventsInspectorControl or getEventsTrackerInspectorControl()
    if not eventsInspectorControl then return end
    tbEvents.UnRegisterAllEvents(eventsInspectorControl)

    --if the events panel is shown update it one time to show the last incoming events properly
    if not eventsInspectorControl:IsHidden() then
        zo_callLater(function()
            updateEventTrackerLines()
        end, 1500)
    end
end


--Add the possible events of the game (from _G table) to the eventsList
for k,v in l_globalprefixes("EVENT_") do
	if type(v)=="number"
	 and k~="EVENT_GLOBAL_MOUSE_DOWN"
	 and k~="EVENT_GLOBAL_MOUSE_UP"
	 then tbEvents.eventList[v]=k
	end
end
setmetatable(tbEvents.eventList,{__index = "-NO EVENT-"})

--Build the reversed lookup table
for k,v in pairs(tbEvents.eventList) do
    tbEvents.eventListLookup[v]=k
end