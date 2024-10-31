local tbug = TBUG or SYSTEMS:GetSystem("merTorchbug")

local strformat = string.format

local ROW_TYPE_HEADER = 6
local ROW_TYPE_PROPERTY = 7
tbug.RowTypes = {
    ROW_TYPE_HEADER =   ROW_TYPE_HEADER,
    ROW_TYPE_PROPERTY = ROW_TYPE_PROPERTY,
}

local isControl = tbug.isControl

local prepareItemLink = tbug.prepareItemLink

tbug.thChildrenId = nil
tbug.tdBuildChildControls = nil

local customKeysForInspectorRows = tbug.customKeysForInspectorRows
local customKey__Object = customKeysForInspectorRows.object

------------------------------------------------------------------------------------------------------------------------
local ColorProperty = {}

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------
local noHeader = false
local currentHeader = 0

local function th(prop)
    noHeader = false
    prop.typ = ROW_TYPE_HEADER
    prop.isHeader = true
    currentHeader = currentHeader + 1
    prop.headerId = currentHeader

    return setmetatable(prop, prop.cls)
end
tbug.th = th


local function td(prop)
    prop.typ = ROW_TYPE_PROPERTY
    prop.isHeader = false
    if not noHeader then
        if not tbug.tdBuildChildControls then
            prop.parentId = currentHeader
        end
    end

    local getFuncName = prop.gets
    if getFuncName then
        local arg = prop.arg
        local idx = prop.idx
        local setFuncName = prop.sets
        if arg ~= nil then
            function prop.get(data, control)
                return (select(idx, control[getFuncName](control, arg)))
            end
            if setFuncName then
                function prop.set(data, control, value)
                    local values = {control[getFuncName](control, arg)}
                    values[idx] = value
                    control[setFuncName](control, arg, unpack(values))
                end
            end
        else
            function prop.get(data, control)
                return (select(idx, control[getFuncName](control)))
            end
            if setFuncName then
                function prop.set(data, control, value)
                    local values = {control[getFuncName](control)}
                    values[idx] = value
                    control[setFuncName](control, unpack(values))
                end
            end
        end
    end
    if prop.cls then
        if prop.cls == ColorProperty then
            prop.isColor = true
        end
    end
    return setmetatable(prop, prop.cls)
end
tbug.td = td

------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------

ColorProperty.__index = ColorProperty


function ColorProperty.getRGBA(data, control)
    local getFuncName = data.prop.getFuncName
    if not getFuncName then
        getFuncName = "Get" .. data.prop.name:gsub("^%l", string.upper, 1)
        data.prop.getFuncName = getFuncName
    end

    local r, g, b, a = control[getFuncName](control)
    return r, g, b, a
end

function ColorProperty.getFormatedRGBA(data, r, g, b, a)
    local s = data.prop.scale or 255
    if a then
        return strformat("rgba(%.0f, %.0f, %.0f, %.2f)",
                         r * s, g * s, b * s, a * s / 255)
    else
        return strformat("rgb(%.0f, %.0f, %.0f)",
                         r * s, g * s, b * s)
    end
end

function ColorProperty.get(data, control)
    local r, g, b, a = ColorProperty.getRGBA(data, control)
    return ColorProperty.getFormatedRGBA(data, r, g, b, a)
end

function ColorProperty.set(data, control, value)
    local setFuncName = data.prop.setFuncName
    if not setFuncName then
        setFuncName = "Set" .. data.prop.name:gsub("^%l", string.upper, 1)
        data.prop.setFuncName = setFuncName
    end

    local color = tbug.parseColorDef(value)
    control[setFuncName](control, color:UnpackRGBA())
end

------------------------------------------------------------------------------------------------------------------------
local AnchorAttribute = {}
AnchorAttribute.__index = AnchorAttribute


function AnchorAttribute.get(data, control)
    local anchorIndex = math.floor(data.prop.idx / 10)
    local valueIndex = data.prop.idx % 10
    return (select(valueIndex, control:GetAnchor(anchorIndex)))
end


function AnchorAttribute.set(data, control, value)
    local anchor0 = {control:GetAnchor(0)}
    local anchor1 = {control:GetAnchor(1)}

    if data.prop.idx < 10 then
        anchor0[data.prop.idx] = value
    else
        anchor1[data.prop.idx % 10] = value
    end

    control:ClearAnchors()

    if anchor0[2] ~= NONE then
        control:SetAnchor(unpack(anchor0, 2))
    end

    if anchor1[2] ~= NONE then
        control:SetAnchor(unpack(anchor1, 2))
    end
end

------------------------------------------------------------------------------------------------------------------------
local DimensionConstraint = {}
DimensionConstraint.__index = DimensionConstraint


function DimensionConstraint.get(data, control)
    return (select(data.prop.idx, control:GetDimensionConstraints()))
end


function DimensionConstraint.set(data, control, value)
    local constraints = {control:GetDimensionConstraints()}
    constraints[data.prop.idx] = value
    control:SetDimensionConstraints(unpack(constraints))
end
------------------------------------------------------------------------------------------------------------------------


local ResizeToFitPadding = {}
ResizeToFitPadding.__index = ResizeToFitPadding

function ResizeToFitPadding.get(data, control)
    return (select(data.prop.idx, control:GetResizeToFitPadding()))
end


function ResizeToFitPadding.set(data, control, value)
    local padding = {control:GetResizeToFitPadding()}
    padding[data.prop.idx] = value
    control:GetResizeToFitPadding(unpack(padding))
end
------------------------------------------------------------------------------------------------------------------------




noHeader = true
local g_commonProperties_parentSubject = {
    --th{name="Metatable invoker control"},
    td { name = customKey__Object, get = function(data, control) --"__Object"
        if control then
            if control.GetName then
                return control:GetName()
            elseif control.name then
                return control.name
            else
                return control
            end
        end
        return
    end },
}

local g_commonProperties = {
    td { name = "name", get = "GetName" },
    td { name = "type", get = "GetType", enum = "CT_names" },
    td { name = "parent", get = "GetParent", set = "SetParent", enum = "CT_names"},
    td { name = "owningWindow", get = "GetOwningWindow", enum = "CT_names"},
    td { name = "hidden", checkFunc = function(control) return isControl(control) end, get = "IsHidden", set = "SetHidden" },
    --Needs the addon ControlOutline in version 1.7 or higher!
    td { name = "outline", checkFunc = function(control) return ControlOutline ~= nil and isControl(control) end,
         get = function(data, control)
             return ControlOutline_IsControlOutlined(control)
         end,
         set = function(data, control)
             ControlOutline_ToggleOutline(control)
         end
    },
    td { name = "__index",
         get = function(data, control, inspectorBase)
             return getmetatable(control).__index
         end,
    },
}

local  g_controlPropListRow =
{
    [CT_BUTTON] =
    {
        th{name="Button properties"},
        td{name="bagId",        get=function(data, control)
                return control.bagId or control.bag
            end, enum = "Bags", --> see glookup.lua -> g_enums["Bags"]
        isSpecial = true},
        td{name="slotIndex",    get=function(data, control)
                return control.slotIndex
            end,
        isSpecial = true},
        td{name="itemLink",    get=function(data, control)
                return prepareItemLink(control, false)
            end,
        isSpecial = true},
        td{name="itemLink plain text",    get=function(data, control)
                return prepareItemLink(control, true)
            end,
        isSpecial = true},
    },
    [CT_CONTROL] =
    {
        th{name="List row data properties"},
        td{name="dataEntry.data",  get=function(data, control)
            return ((control.dataEntry and control.dataEntry.data) or control.dataEntry) or control
        end},
        td{name="bagId",        get=function(data, control)
            if control.dataEntry and control.dataEntry.data then
                return control.dataEntry.data.bagId or control.dataEntry.data.bag
            elseif control.dataEntry then
                return control.dataEntry.bagId or control.dataEntry.bag
            elseif control.bagId or control.bag then
                return control.bagId or control.bag
            else
                local parentCtrl = control:GetParent()
                if parentCtrl.dataEntry and parentCtrl.dataEntry.data then
                    return parentCtrl.dataEntry.data.bagId or parentCtrl.dataEntry.data.bag
                elseif parentCtrl.dataEntry then
                    return parentCtrl.dataEntry.bagId or parentCtrl.dataEntry.bag
                elseif parentCtrl.bagId or parentCtrl.bag then
                    return parentCtrl.bagId or parentCtrl.bag
                end
            end
        end,
        enum = "Bags", --> see glookup.lua -> g_enums["Bags"]
        isSpecial = true},
        td{name="slotIndex",    get=function(data, control)
            if control.dataEntry and control.dataEntry.data then
                return control.dataEntry.data.slotIndex or control.dataEntry.data.index
            elseif control.dataEntry then
                return control.dataEntry.slotIndex or control.dataEntry.index
            elseif control.slotIndex then
                return control.slotIndex
            else
                local parentCtrl = control:GetParent()
                if parentCtrl.dataEntry and parentCtrl.dataEntry.data then
                    return parentCtrl.dataEntry.data.slotIndex or parentCtrl.dataEntry.data.index
                elseif parentCtrl.dataEntry then
                    return parentCtrl.dataEntry.slotIndex or parentCtrl.dataEntry.index
                elseif parentCtrl.slotIndex then
                    return parentCtrl.slotIndex
                end
            end
        end,
        isSpecial = true},
        td{name="itemLink",    get=function(data, control)
                return prepareItemLink(control, false)
            end,
        isSpecial = true},
        td{name="itemLink plain text",    get=function(data, control)
                return prepareItemLink(control, true)
            end,
        isSpecial = true},
    },
}

local g_commonProperties2 = {
    th{name="Anchor #0",        get="GetAnchor"},

    td{ name ="point",              cls = AnchorAttribute, idx =2, enum ="AnchorPosition",  getOrig ="GetAnchor"},
    td{ name ="relativeTo",         cls = AnchorAttribute, idx =3, enum = "CT_names",       getOrig ="GetAnchor"},
    td{ name ="relativePoint",      cls = AnchorAttribute, idx =4, enum ="AnchorPosition",  getOrig ="GetAnchor"},
    td{ name ="offsetX",            cls = AnchorAttribute, idx =5,                          getOrig ="GetAnchor"},
    td{ name ="offsetY",            cls = AnchorAttribute, idx =6,                          getOrig ="GetAnchor"},
    td{ name ="anchorConstrains",   cls = AnchorAttribute, idx =7, enum="AnchorConstrains", getOrig ="GetAnchor"},

    th{name="Anchor #1",        get="GetAnchor"},

    td{ name ="point",              cls = AnchorAttribute, idx =12, enum ="AnchorPosition", getOrig ="GetAnchor"},
    td{ name ="relativeTo",         cls = AnchorAttribute, idx =13, enum = "CT_names",      getOrig ="GetAnchor"},
    td{ name ="relativePoint",      cls = AnchorAttribute, idx =14, enum ="AnchorPosition", getOrig ="GetAnchor"},
    td{ name ="offsetX",            cls = AnchorAttribute, idx =15, getOrig ="GetAnchor"},
    td{ name ="offsetY",            cls = AnchorAttribute, idx =16, getOrig ="GetAnchor"},
    td{ name ="anchorConstrains",   cls = AnchorAttribute, idx =17, enum="AnchorConstrains", getOrig ="GetAnchor"},

    th{name="Dimensions",       get="GetDimensions"},

    td{name="width",            get="GetWidth", set="SetWidth"},
    td{name="height",           get="GetHeight", set="SetHeight"},
    td{name="desiredWidth",     get="GetDesiredWidth"},
    td{name="desiredHeight",    get="GetDesiredHeight"},
    th{name="DimensionConstraints", get="GetDimensionConstraints"},
    td{name="minWidth",         cls=DimensionConstraint, idx=1,                         getOrig="GetDimensionConstraints"},
    td{name="minHeight",        cls=DimensionConstraint, idx=2,                         getOrig="GetDimensionConstraints"},
    td{name="maxWidth",         cls=DimensionConstraint, idx=3,                         getOrig="GetDimensionConstraints"},
    td{name="maxHeight",        cls=DimensionConstraint, idx=4,                         getOrig="GetDimensionConstraints"},
}

local g_specialProperties =
{
    [CT_CONTROL] =
    {
        th{name="Control properties"},

        td{name="alpha",                get="GetAlpha", set="SetAlpha", sliderData={min=0, max=1, step=0.1}},
        td{name="clampedToScreen",      get="GetClampedToScreen", set="SetClampedToScreen"},
        td{name="controlAlpha",         get="GetControlAlpha"},
        td{name="controlHidden",        get="IsControlHidden"},
        td{name="excludeFromResizeToFitExtents",
                                        get="GetExcludeFromResizeToFitExtents",
                                        set="SetExcludeFromResizeToFitExtents"},
        td{name="hidden",               get="IsHidden", set="SetHidden"},
        td{name="inheritAlpha",         get="GetInheritsAlpha", set="SetInheritAlpha"},
        td{name="inheritScale",         get="GetInheritsScale", set="SetInheritScale"},
        td{name="keyboardEnabled",      get="IsKeyboardEnabled", set="SetKeyboardEnabled"},
        td{name="layer", enum="DL_names",     get="GetDrawLayer", set="SetDrawLayer"},
        td{name="level",                get="GetDrawLevel", set="SetDrawLevel", sliderData={min=0, max=100, step=1}},
        td{name="mouseEnabled",         get="IsMouseEnabled", set="SetMouseEnabled"},
        td{name="resizeToFitDescendents",
                                        get="GetResizeToFitDescendents",
                                        set="SetResizeToFitDescendents"},
        td{name="resizeToFitConstrains", enum="AnchorConstrains",
                                        get="GetResizeToFitConstrains",
                                        set="SetResizeToFitConstrains"},
        td{name="resizeToFitPaddingX",  cls=ResizeToFitPadding, idx=1,                    getOrig="GetResizeToFitPadding"},
        td{name="resizeToFitPaddingY",  cls=ResizeToFitPadding, idx=2,                    getOrig="GetResizeToFitPadding"},
        td{name="scale",                get="GetScale", set="SetScale", sliderData={min=0, max=5, step=0.1}},
        td{name="tier",  enum="DT_names",     get="GetDrawTier", set="SetDrawTier"},

        th{name="Children",             get="GetNumChildren", isChildrenHeader = true}, --name will be replaced at controlinspector.lua -> BuildMasterList
    },
    [CT_BACKDROP] =
    {
        th{name="Backdrop properties"},

        td{name="centerColor",          cls=ColorProperty,                  getOrig="GetColor"},
        td{name="pixelRoundingEnabled", get="IsPixelRoundingEnabled",
                                        set="SetPixelRoundingEnabled"},
    },
    [CT_BUTTON] =
    {
        th{name="Button properties"},

        td{name="label",                get="GetLabelControl", enum = "CT_names"},
        td{name="pixelRoundingEnabled", get="IsPixelRoundingEnabled",
                                        set="SetPixelRoundingEnabled"},
        td{name="state", enum="BSTATE", get="GetState", set="SetState"},
    },
    [CT_COLORSELECT] =
    {
        th{name="ColorSelect properties"},

        td{name="colorAsRGB",               cls=ColorProperty,              getOrig="GetColor"},
        td{name="colorWheelTexture",        get="GetColorWheelTextureControl",
                                            set="SetColorWheelTextureControl"},
        td{name="colorWheelThumbTexture",   get="GetColorWheelThumbTextureControl",
                                            set="SetColorWheelThumbTextureControl"},
        td{name="fullValuedColorAsRGB",     get=ColorProperty.get},
        td{name="value",                    get="GetValue", set="SetValue"},
    },
    [CT_COMPASS] =
    {
        th{name="Compass properties"},

        td{name="numCenterOveredPins",  get="GetNumCenterOveredPins"},
    },
    [CT_COOLDOWN] =
    {
        th{name="Cooldown properties"},

        td{name="duration",             get="GetDuration"},
        td{name="percentCompleteFixed", get="GetPercentCompleteFixed",
                                        set="SetPercentCompleteFixed"},
        td{name="timeLeft",             get="GetTimeLeft"},
    },
    [CT_EDITBOX] =
    {
        th{name="Edit properties"},

        td{name="copyEnabled",          get="GetCopyEnabled", set="SetCopyEnabled"},
        td{name="cursorPosition",       get="GetCursorPosition", set="SetCursorPosition"},
        td{name="editEnabled",          get="GetEditEnabled", set="SetEditEnabled"},
        td{name="fontHeight",           get="GetFontHeight"},
        td{name="multiLine",            get="IsMultiLine", set="SetMultiLine"},
        td{name="newLineEnabled",       get="GetNewLineEnabled", set="SetNewLineEnabled"},
        td{name="pasteEnabled",         get="GetPasteEnabled", set="SetPasteEnabled"},
        td{name="scrollExtents",        get="GetScrollExtents"},
        td{name="text",                 get="GetText", set="SetText"},
        td{name="topLineIndex",         get="GetTopLineIndex", set="SetTopLineIndex"},
    },
    [CT_LABEL] =
    {
        th{name="Label properties"},

        td{name="color",                cls=ColorProperty,              getOrig="GetColor"},
        td{name="didLineWrap",          get="DidLineWrap"},
        td{name="fontHeight",           get="GetFontHeight"},
        td{name="horizontalAlignment",  get="GetHorizontalAlignment",
           enum="TEXT_ALIGN_horizontal",set="SetHorizontalAlignment"},
        td{name="modifyTextType",       get="GetModifyTextType",
           enum="MODIFY_TEXT_TYPE",     set="SetModifyTextType"},
        td{name="numLines",             get="GetNumLines"},
        td{name="styleColor",           cls=ColorProperty, scale=1,     getOrig="GetColor"},
        td{name="text",                 get="GetText", set="SetText"},
        td{name="textHeight",           get="GetTextHeight"},
        td{name="textWidth",            get="GetTextWidth"},
        td{name="verticalAlignment",    get="GetVerticalAlignment",
           enum="TEXT_ALIGN_vertical",  set="SetVerticalAlignment"},
        td{name="wasTruncated",         get="WasTruncated"},
    },
    [CT_LINE] =
    {
        th{name="Line properties"},

        td{name="blendMode",            get="GetBlendMode",
           enum="TEX_BLEND_MODE",       set="SetBlendMode"},
        td{name="color",                cls=ColorProperty,              getOrig="GetColor"},
        td{name="desaturation",         get="GetDesaturation",
                                        set="SetDesaturation"},
        td{name="pixelRoundingEnabled", get="IsPixelRoundingEnabled",
                                        set="SetPixelRoundingEnabled"},
        td{name="textureCoords.left",   gets="GetTextureCoords", idx=1,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.right",  gets="GetTextureCoords", idx=2,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.top",    gets="GetTextureCoords", idx=3,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.bottom", gets="GetTextureCoords", idx=4,
                                        sets="SetTextureCoords"},
        td{name="textureFileName",      get="GetTextureFileName",
                                        set="SetTexture"},
        td{name="textureFileWidth",     gets="GetTextureFileDimensions", idx=1},
        td{name="textureFileHeight",    gets="GetTextureFileDimensions", idx=2},
        td{name="textureLoaded",        get="IsTextureLoaded"},
    },
    [CT_MAPDISPLAY] =
    {
        th{name="MapDisplay properties"},

        td{name="zoom",                 get="GetZoom", set="SetZoom"},
    },
    [CT_SCROLL] =
    {
        th{name="Scroll properties"},

        td{name="extents.horizontal",   gets="GetScrollExtents", idx=1},
        td{name="extents.vertical",     gets="GetScrollExtents", idx=2},
        td{name="offsets.horizontal",   gets="GetScrollOffsets", idx=1,
                                        set="SetHorizontalScroll"},
        td{name="offsets.vertical",     gets="GetScrollOffsets", idx=2,
                                        set="SetVerticalScroll"},
    },
    [CT_SLIDER] =
    {
        th{name="Slider properties"},

        td{name="allowDraggingFromThumb",   get="DoesAllowDraggingFromThumb",
                                            set="SetAllowDraggingFromThumb"},
        td{name="enabled",                  get="GetEnabled", set="SetEnabled"},
        td{name="orientation",              get="GetOrientation",
           enum="ORIENTATION",              set="SetOrientation"},
        td{name="thumbTexture",             get="GetThumbTextureControl"},
        td{name="valueMin",          idx=1, gets="GetMinMax", sets="SetMinMax"},
        td{name="value",                    get="GetValue", set="SetValue"},
        td{name="valueMax",          idx=2, gets="GetMinMax", sets="SetMinMax"},
        td{name="valueStep",                get="GetValueStep", set="SetValueStep"},
        td{name="thumbFlushWithExtents",    get="IsThumbFlushWithExtents",
                                            set="SetThumbFlushWithExtents"},
    },
    [CT_STATUSBAR] =
    {
        th{name="StatusBar properties"},

        td{name="valueMin",          idx=1, gets="GetMinMax", sets="SetMinMax"},
        td{name="value",                    get="GetValue", set="SetValue"},
        td{name="valueMax",          idx=2, gets="GetMinMax", sets="SetMinMax"},
    },
    [CT_TEXTBUFFER] =
    {
        th{name="TextBuffer properties"},

        td{name="drawLastEntryIfOutOfRoom", get="GetDrawLastEntryIfOutOfRoom",
                                            set="SetDrawLastEntryIfOutOfRoom"},
        td{name="linkEnabled",              get="GetLinkEnabled",
                                            set="SetLinkEnabled"},
        td{name="maxHistoryLines",          get="GetMaxHistoryLines",
                                            set="SetMaxHistoryLines"},
        td{name="numHistoryLines",          get="GetNumHistoryLines"},
        td{name="numVisibleLines",          get="GetNumVisibleLines"},
        td{name="scrollPosition",           get="GetScrollPosition",
                                            set="SetScrollPosition"},
        td{name="splitLongMessages",        get="IsSplittingLongMessages",
                                            set="SetSplitLongMessages"},
        td{name="timeBeforeLineFadeBegins", gets="GetLineFade", idx=1,
                                            sets="SetLineFade"},
        td{name="timeForLineToFade",        gets="GetLineFade", idx=2,
                                            sets="SetLineFade"},
    },
    [CT_TEXTURE] =
    {
        th{name="Texture properties"},

        td{name="addressMode",          get="GetAddressMode",
           enum="TEX_MODE",             set="SetAddressMode"},
        td{name="blendMode",            get="GetBlendMode",
           enum="TEX_BLEND_MODE",       set="SetBlendMode"},
        td{name="color",                cls=ColorProperty,              getOrig="GetColor"},
        td{name="desaturation",         get="GetDesaturation",
                                        set="SetDesaturation"},
        td{name="pixelRoundingEnabled", get="IsPixelRoundingEnabled",
                                        set="SetPixelRoundingEnabled"},
        td{name="resizeToFitFile",      get="GetResizeToFitFile",
                                        set="SetResizeToFitFile"},
        td{name="textureCoords.left",   gets="GetTextureCoords", idx=1,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.right",  gets="GetTextureCoords", idx=2,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.top",    gets="GetTextureCoords", idx=3,
                                        sets="SetTextureCoords"},
        td{name="textureCoords.bottom", gets="GetTextureCoords", idx=4,
                                        sets="SetTextureCoords"},
        td{name="textureFileName",      get="GetTextureFileName",
                                        set="SetTexture"},
        td{name="textureFileWidth",     gets="GetTextureFileDimensions", idx=1},
        td{name="textureFileHeight",    gets="GetTextureFileDimensions", idx=2},
        td{name="textureLoaded",        get="IsTextureLoaded"},

        td{name="VERTEX_POINTS_BOTTOMLEFT.U",   gets="GetVertexUV", idx=1,
           arg=VERTEX_POINTS_BOTTOMLEFT,        sets="SetVertexUV"},
        td{name="VERTEX_POINTS_BOTTOMLEFT.V",   gets="GetVertexUV", idx=2,
           arg=VERTEX_POINTS_BOTTOMLEFT,        sets="SetVertexUV"},
        td{name="VERTEX_POINTS_BOTTOMRIGHT.U",  gets="GetVertexUV", idx=1,
           arg=VERTEX_POINTS_BOTTOMRIGHT,       sets="SetVertexUV"},
        td{name="VERTEX_POINTS_BOTTOMRIGHT.V",  gets="GetVertexUV", idx=2,
           arg=VERTEX_POINTS_BOTTOMRIGHT,       sets="SetVertexUV"},
        td{name="VERTEX_POINTS_TOPLEFT.U",      gets="GetVertexUV", idx=1,
           arg=VERTEX_POINTS_TOPLEFT,           sets="SetVertexUV"},
        td{name="VERTEX_POINTS_TOPLEFT.V",      gets="GetVertexUV", idx=2,
           arg=VERTEX_POINTS_TOPLEFT,           sets="SetVertexUV"},
        td{name="VERTEX_POINTS_TOPRIGHT.U",     gets="GetVertexUV", idx=1,
           arg=VERTEX_POINTS_TOPRIGHT,          sets="SetVertexUV"},
        td{name="VERTEX_POINTS_TOPRIGHT.V",     gets="GetVertexUV", idx=2,
           arg=VERTEX_POINTS_TOPRIGHT,          sets="SetVertexUV"},
    },
    [CT_TEXTURECOMPOSITE] =
    {
        th{name="TextureComposite properties"},

        td{name="blendMode",            get="GetBlendMode",
           enum="TEX_BLEND_MODE",       set="SetBlendMode"},
        td{name="desaturation",         get="GetDesaturation",
                                        set="SetDesaturation"},
        td{name="numSurfaces",          get="GetNumSurfaces"},
        td{name="pixelRoundingEnabled", get="IsPixelRoundingEnabled",
                                        set="SetPixelRoundingEnabled"},
        td{name="textureFileName",      get="GetTextureFileName",
                                        set="SetTexture"},
        td{name="textureFileWidth",     gets="GetTextureFileDimensions", idx=1},
        td{name="textureFileHeight",    gets="GetTextureFileDimensions", idx=2},
        td{name="textureLoaded",        get="IsTextureLoaded"},
    },
    [CT_TOOLTIP] =
    {
        th{name="Tooltip properties"},

        td{name="owner",                get="GetOwner", enum = "CT_names"},
    },
    [CT_TOPLEVELCONTROL] =
    {
        th{name="TopLevelControl properties"},

        td{name="allowBringToTop",      get="AllowBringToTop",
                                        set="SetAllowBringToTop", enum = "CT_names"},
    },
}


------------------------------------------------------------------------------------------------------------------------
tbug.controlInspectorDataTypes = {
    g_commonProperties_parentSubject =  g_commonProperties_parentSubject,
    g_commonProperties =                g_commonProperties,
    g_controlPropListRow =              g_controlPropListRow,
    g_commonProperties2 =               g_commonProperties2,
    g_specialProperties =               g_specialProperties,
}