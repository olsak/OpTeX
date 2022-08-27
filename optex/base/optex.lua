-- This is part of the OpTeX project, see http://petr.olsak.net/optex

-- The basic lua functions and declarations used in \OpTeX/ are here

local fmt = string.format

-- \medskip\secc General^^M
--
-- Define namespace where some \OpTeX/ functions will be added.

local optex = _ENV.optex or {}
_ENV.optex = optex

-- Error function used by following functions for critical errors.
local function err(message)
    error("\nerror: "..message.."\n")
end
--
-- For a `\chardef`'d, `\countdef`'d, etc., csname return corresponding register
-- number. The responsibility of providing a `\XXdef`'d name is on the caller.
local function registernumber(name)
    return token.create(name).index
end
_ENV.registernumber = registernumber
optex.registernumber = registernumber
--
-- MD5 hash of given file.
function optex.mdfive(file)
    local fh = io.open(file, "rb")
    if fh then
        local data = fh:read("*a")
        fh:close()
        tex.print(md5.sumhexa(data))
   end
end
--
-- \medskip\secc[lua-alloc] Allocators^^M
local alloc = _ENV.alloc or {}
_ENV.alloc = alloc
--
-- An attribute allocator in Lua that cooperates with normal \OpTeX/ allocator.
local attributes = {}
function alloc.new_attribute(name)
    local cnt = tex.count["_attributealloc"] + 1
    if cnt > 65534 then
        tex.error("No room for a new attribute")
    else
        tex.setcount("global", "_attributealloc", cnt)
        texio.write_nl("log", '"'..name..'"=\\attribute'..tostring(cnt))
        attributes[name] = cnt
        return cnt
    end
end
--
-- Allocator for Lua functions ("pseudoprimitives"). It passes variadic
-- arguments (\"`...`") like `"global"` to `token.set_lua`.
local function_table = lua.get_functions_table()
local function define_lua_command(csname, fn, ...)
    local luafnalloc = #function_table + 1
    token.set_lua(csname, luafnalloc, ...) -- WARNING: needs LuaTeX 1.08 (2019) or newer
    function_table[luafnalloc] = fn
end
_ENV.define_lua_command = define_lua_command
optex.define_lua_command = define_lua_command
--
-- \medskip\secc[callbacks] Callbacks^^M
local callback = _ENV.callback or {}
_ENV.callback = callback
--
-- Save `callback.register` function for internal use.
local callback_register = callback.register
function callback.register(name, fn)
    err("direct registering of callbacks is forbidden, use 'callback.add_to_callback'")
end
--
-- Table with lists of functions for different callbacks.
local callback_functions = {}
-- Table that maps callback name to a list of descriptions of its added
-- functions. The order corresponds with `callback_functions`.
local callback_description = {}
--
-- Table used to differentiate user callbacks from standard callbacks. Contains
-- user callbacks as keys.
local user_callbacks = {}
-- Table containing default functions for callbacks, which are called if either
-- a user created callback is defined, but doesn't have added functions or for
-- standard callbacks that are \"extended" (see `mlist_to_hlist` and its pre/post
-- filters below).
local default_functions = {}
--
-- Table that maps standard (and later user) callback names to their types.
local callback_types = {
    -- file discovery
    find_read_file     = "exclusive",
    find_write_file    = "exclusive",
    find_font_file     = "data",
    find_output_file   = "data",
    find_format_file   = "data",
    find_vf_file       = "data",
    find_map_file      = "data",
    find_enc_file      = "data",
    find_pk_file       = "data",
    find_data_file     = "data",
    find_opentype_file = "data",
    find_truetype_file = "data",
    find_type1_file    = "data",
    find_image_file    = "data",

    open_read_file     = "exclusive",
    read_font_file     = "exclusive",
    read_vf_file       = "exclusive",
    read_map_file      = "exclusive",
    read_enc_file      = "exclusive",
    read_pk_file       = "exclusive",
    read_data_file     = "exclusive",
    read_truetype_file = "exclusive",
    read_type1_file    = "exclusive",
    read_opentype_file = "exclusive",

    -- data processing
    process_input_buffer  = "data",
    process_output_buffer = "data",
    process_jobname       = "data",
    input_level_string    = "data",

    -- node list processing
    contribute_filter      = "simple",
    buildpage_filter       = "simple",
    build_page_insert      = "exclusive",
    pre_linebreak_filter   = "list",
    linebreak_filter       = "exclusive",
    append_to_vlist_filter = "exclusive",
    post_linebreak_filter  = "reverselist",
    hpack_filter           = "list",
    vpack_filter           = "list",
    hpack_quality          = "list",
    vpack_quality          = "list",
    process_rule           = "exclusive",
    pre_output_filter      = "list",
    hyphenate              = "simple",
    ligaturing             = "simple",
    kerning                = "simple",
    insert_local_par       = "simple",
    mlist_to_hlist         = "exclusive",

    -- information reporting
    pre_dump             = "simple",
    start_run            = "simple",
    stop_run             = "simple",
    start_page_number    = "simple",
    stop_page_number     = "simple",
    show_error_hook      = "simple",
    show_error_message   = "simple",
    show_lua_error_hook  = "simple",
    start_file           = "simple",
    stop_file            = "simple",
    call_edit            = "simple",
    finish_synctex       = "simple",
    wrapup_run           = "simple",

    -- pdf related
    finish_pdffile            = "data",
    finish_pdfpage            = "data",
    page_order_index          = "data",
    process_pdf_image_content = "data",

    -- font related
    define_font     = "exclusive",
    glyph_not_found = "exclusive",
    glyph_info      = "exclusive",

    -- undocumented
    glyph_stream_provider = "exclusive",
    provide_charproc_data = "exclusive",
}
--
-- Return a list containing descriptions of added callback functions for
-- specific callback.
function callback.callback_descriptions(name)
    return callback_description[name] or {}
end

local valid_callback_types = {
    exclusive = true,
    simple = true,
    data = true,
    list = true,
    reverselist = true,
}
--
-- Create a user callback that can only be called manually using
-- `call_callback`. A default function is only needed by "exclusive" callbacks.
function callback.create_callback(name, cbtype, default)
    if callback_types[name] then
        err("cannot create callback '"..name.."' - it already exists")
    elseif not valid_callback_types[cbtype] then
        err("cannot create callback '"..name.. "' with invalid callback type '"..cbtype.."'")
    elseif ctype == "exclusive" and not default then
        err("unable to create exclusive callback '"..name.."', default function is required")
    end

    callback_types[name] = cbtype
    default_functions[name] = default or nil
    user_callbacks[name] = true
end
--
-- Add a function to the list of functions executed when callback is called.
-- For standard luatex callback a proxy function that calls our machinery is
-- registered as the real callback function. This doesn't happen for user
-- callbacks, that are called manually by user using `call_callback` or for
-- standard callbacks that have default functions -- like `mlist_to_hlist` (see
-- below).
local call_callback
function callback.add_to_callback(name, fn, description)
    if user_callbacks[name] or callback_functions[name] or default_functions[name] then
        -- either:
        --  a) user callback - no need to register anything
        --  b) standard callback that has already been registered
        --  c) standard callback with default function registered separately
        --     (mlist_to_hlist)
    elseif callback_types[name] then
        -- This is a standard luatex callback with first function being added,
        -- register a proxy function as a real callback. Assert, so we know
        -- when things break, like when callbacks get redefined by future
        -- luatex.
        callback_register(name, function(...)
            return call_callback(name, ...)
        end)
    else
        err("cannot add to callback '"..name.."' - no such callback exists")
    end

    -- add function to callback list for this callback
    callback_functions[name] = callback_functions[name] or {}
    table.insert(callback_functions[name], fn)

    -- add description to description list
    callback_description[name] = callback_description[name] or {}
    table.insert(callback_description[name], description)
end
--
-- Remove a function from the list of functions executed when callback is
-- called. If last function in the list is removed delete the list entirely.
function callback.remove_from_callback(name, description)
    local descriptions = callback_description[name]
    local index
    for i, desc in ipairs(descriptions) do
        if desc == description then
            index = i
            break
        end
    end

    table.remove(descriptions, index)
    local fn = table.remove(callback_functions[name], index)

    if #descriptions == 0 then
        -- Delete the list entirely to allow easy checking of "truthiness".
        callback_functions[name] = nil

        if not user_callbacks[name] and not default_functions[name] then
            -- this is a standard callback with no added functions and no
            -- default function (i.e. not mlist_to_hlist), restore standard
            -- behaviour by unregistering.
            callback_register(name, nil)
        end
    end

    return fn, description
end
--
-- helper iterator generator for iterating over reverselist callback functions
local function reverse_ipairs(t)
    local i, n = #t + 1, 1
    return function()
        i = i - 1
        if i >= n then
            return i, t[i]
        end
    end
end
--
-- Call all functions added to callback. This function handles standard
-- callbacks as well as user created callbacks. It can happen that this
-- function is called when no functions were added to callback -- like for user
-- created callbacks or `mlist_to_hlist` (see below), these are handled either
-- by a default function (like for `mlist_to_hlist` and those user created
-- callbacks that set a default function) or by doing nothing for empty
-- function list.
function callback.call_callback(name, ...)
    local cbtype = callback_types[name]
    -- either take added functions or the default function if there is one
    local functions = callback_functions[name] or {default_functions[name]}

    if cbtype == nil then
        err("cannot call callback '"..name.."' - no such callback exists")
    elseif cbtype == "exclusive" then
        -- only one function, atleast default function is guaranteed by
        -- create_callback
        return functions[1](...)
    elseif cbtype == "simple" then
        -- call all functions one after another, no passing of data
        for _, fn in ipairs(functions) do
            fn(...)
        end
        return
    elseif cbtype == "data" then
        -- pass data (first argument) from one function to other, while keeping
        -- other arguments
        local data = (...)
        for _, fn in ipairs(functions) do
            data = fn(data, select(2, ...))
        end
        return data
    end

    -- list and reverselist are like data, but "true" keeps data (head node)
    -- unchanged and "false" ends the chain immediately
    local iter
    if cbtype == "list" then
        iter = ipairs
    elseif cbtype == "reverselist" then
        iter = reverse_ipairs
    end

    local head = (...)
    local new_head
    local changed = false
    for _, fn in iter(functions) do
        new_head = fn(head, select(2, ...))
        if new_head == false then
            return false
        elseif new_head ~= true then
            head = new_head
            changed = true
        end
    end
    return not changed or head
end
call_callback = callback.call_callback
--
-- Create \"virtual" callbacks `pre/post_mlist_to_hlist_filter` by setting
-- `mlist_to_hlist` callback. The default behaviour of `mlist_to_hlist` is kept by
-- using a default function, but it can still be overriden by using
-- `add_to_callback`.
default_functions["mlist_to_hlist"] = node.mlist_to_hlist
callback.create_callback("pre_mlist_to_hlist_filter", "list")
callback.create_callback("post_mlist_to_hlist_filter", "reverselist")
callback_register("mlist_to_hlist", function(head, ...)
    -- pre_mlist_to_hlist_filter
    local new_head = call_callback("pre_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end
    -- mlist_to_hlist means either added functions or standard luatex behavior
    -- of node.mlist_to_hlist (handled by default function)
    head = call_callback("mlist_to_hlist", head, ...)
    -- post_mlist_to_hlist_filter
    new_head = call_callback("post_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end
    return head
end)
--
-- For preprocessing boxes just before shipout we define custom callback. This
-- is used for coloring based on attributes.
-- There is however a challenge - how to call this callback? We could redefine
-- `\shipout` and `\pdfxform` (which both run `ship_out` procedure internally),
-- but they would lose their primtive meaning – i.e. `\immediate` wouldn't work
-- with `\pdfxform`. The compromise is to require anyone to run
-- \`\_preshipout``<destination box number><box specification>` just before
-- `\shipout` or `\pdfxform` if they want to call `pre_shipout_filter` (and
-- achieve colors and possibly more).
callback.create_callback("pre_shipout_filter", "list")

local tex_setbox = tex.setbox
local token_scanint = token.scan_int
local token_scanlist = token.scan_list
define_lua_command("_preshipout", function()
    local boxnum = token_scanint()
    local head = token_scanlist()
    head = call_callback("pre_shipout_filter", head)
    tex_setbox(boxnum, head)
end)
--
-- Compatibility with \LaTeX/ through luatexbase namespace. Needed for
-- luaotfload.
_ENV.luatexbase = {
    registernumber = registernumber,
    attributes = attributes,
    -- `provides_module` is needed by older version of luaotfload
    provides_module = function() end,
    new_attribute = alloc.new_attribute,
    callback_descriptions = callback.callback_descriptions,
    create_callback = callback.create_callback,
    add_to_callback = callback.add_to_callback,
    remove_from_callback = callback.remove_from_callback,
    call_callback = callback.call_callback,
    callbacktypes = {},
}
--
-- `\tracingmacros` callback registered.
-- Use `\tracingmacros=3` or `\tracingmacros=4` if you want to see the result.
callback.add_to_callback("input_level_string", function(n)
    if tex.tracingmacros > 3 then
        return "[" .. n .. "] "
    elseif tex.tracingmacros > 2 then
        return "~" .. string.rep(".",n)
    else
        return ""
    end
end, "_tracingmacros")
-- \medskip\secc[lua-pdf-resources] Management of PDF page resources^^M
--
-- Traditionally, pdf\TeX/ allowed managing PDF page resources (graphics
-- states, patterns, shadings, etc.) using a single toks register,
-- `\pdfpageresources`. This is insufficient due to the expected PDF object
-- structer and also because many \"packages" want to add page resources and
-- thus fight for the access to that register. We add a finer alternative,
-- which allows adding different kinds of resources to a global page resources
-- dictionary. Note that some resource types (fonts and XObjects) are already
-- managed by \LuaTeX/ and shouldn't be added!
--
-- XObject forms can also use resources, but there are several ways to make
-- \LuaTeX/ reference resources from forms. It is hence left up to the user to
-- insert page resources managed by us, if they need them. For that, use
-- `pdf.get_page_resources()`, or the below \TeX/ alternative for that.
--
local pdfdict_mt = {
    __tostring = function(dict)
        local out = {"<<"}
        for k, v in pairs(dict) do
            out[#out+1] = fmt("/%s %s", tostring(k), tostring(v))
        end
        out[#out+1] = ">>"
        return table.concat(out, "\n")
    end,
}
local function pdf_dict(t)
    return setmetatable(t or {}, pdfdict_mt)
end
optex.pdf_dict = pdf_dict
--
local resource_dict_objects = {}
local page_resources = {}
function pdf.add_page_resource(type, name, value)
    local resources = page_resources[type]
    if not resources then
        local obj = pdf.reserveobj()
        pdf.setpageresources(fmt("%s /%s %d 0 R", pdf.get_page_resources(), type, obj))
        resource_dict_objects[type] = obj
        resources = pdf_dict()
        page_resources[type] = resources
    end
    page_resources[type][name] = value
end
function pdf.get_page_resources()
    return pdf.getpageresources() or ""
end
--
-- New \"pseudo" primitives are introduced.
-- \`\_addpageresource``{<type>}{<PDF name>}{<PDF dict>}` adds more reources
-- of given resource <type> to our data structure.
-- \`\_pageresources` expands to the saved <type>s and object numbers.
define_lua_command("_addpageresource", function()
    pdf.add_page_resource(token.scan_string(), token.scan_string(), token.scan_string())
end)
define_lua_command("_pageresources", function()
    tex.print(pdf.get_page_resources())
end)
--
-- We write the objects with resources to the PDF file in the `finish_pdffile`
-- callback.
callback.add_to_callback("finish_pdffile", function()
    for type, dict in pairs(page_resources) do
        local obj = resource_dict_objects[type]
        pdf.immediateobj(obj, tostring(dict))
    end
end)
--
-- \medskip\secc[lua-colors] Handling of colors and transparency using attributes^^M
--
-- Because \LuaTeX/ doesn't do anything with attributes, we have to add meaning
-- to them. We do this by intercepting \TeX/ just before it ships out a page and
-- inject PDF literals according to attributes.
--
local node_id = node.id
local node_subtype = node.subtype
local glyph_id = node_id("glyph")
local rule_id = node_id("rule")
local glue_id = node_id("glue")
local hlist_id = node_id("hlist")
local vlist_id = node_id("vlist")
local disc_id = node_id("disc")
local whatsit_id = node_id("whatsit")
local pdfliteral_id = node_subtype("pdf_literal")
local pdfsave_id = node_subtype("pdf_save")
local pdfrestore_id = node_subtype("pdf_restore")
local token_getmacro = token.get_macro

local direct = node.direct
local todirect = direct.todirect
local tonode = direct.tonode
local getfield = direct.getfield
local setfield = direct.setfield
local getwhd = direct.getwhd
local getid = direct.getid
local getlist = direct.getlist
local setlist = direct.setlist
local getleader = direct.getleader
local getattribute = direct.get_attribute
local insertbefore = direct.insert_before
local copy = direct.copy
local traverse = direct.traverse
local one_bp = tex.sp("1bp")
--
-- The attribute for coloring is allocated in `colors.opm`
local color_attribute = registernumber("_colorattr")
local transp_attribute = registernumber("_transpattr")
--
-- Now we define function which creates whatsit nodes with PDF literals. We do
-- this by creating a base literal, which we then copy and customize.
--
local pdf_base_literal = direct.new("whatsit", "pdf_literal")
setfield(pdf_base_literal, "mode", 2) -- direct mode
local function pdfliteral(str)
    local literal = copy(pdf_base_literal)
    setfield(literal, "data", str)
    return literal
end
optex.directpdfliteral = pdfliteral
--
-- The function {\Red`colorize`}`(head, current, current_stroke, current_tr)`
-- goes through a node list and injects PDF literals according to attributes.
-- Its arguments are the head of the list to be colored and the current color
-- for fills and strokes and the current trasparency attribute.
-- It is a recursive function – nested
-- horizontal and vertical lists are handled in the same way. Only the
-- attributes of “content” nodes (glyphs, rules, etc.) matter. Users drawing
-- with PDF literals have to set color themselves.
--
-- Whatsit node with color setting PDF literal is injected only when a different
-- color or transparency is needed. Our injection does not care about boxing levels,
-- but this isn't a problem, since PDF literal whatsits just instruct the
-- `\shipout` related procedures to emit the literal.
--
-- We also set the stroke and non-stroke colors separately. This is because
-- stroke color is not always needed – \LuaTeX/ itself only uses it for rules
-- whose one dimension is less than or equal to 1 bp and for fonts whose `mode`
-- is set to 1 (outline) or 2 (outline and fill). Catching these cases is a
-- little bit involved. For example rules are problematic, because at this
-- point their dimensions can still be running ($-2^{30}$) – they may or may
-- not be below the one big point limit. Also the text direction is involved.
-- Because of the negative value for running dimensions the simplistic check,
-- while not fully correct, should produce the right results. We currently
-- don't check for the font mode at all.
--
-- Leaders (represented by glue nodes with leader field) are not handled fully.
-- They are problematic, because their content is repeated more times and it
-- would have to be ensured that the coloring would be right even for e.g.
-- leaders that start and end on a different color. We came to conclusion that
-- this is not worth, hence leaders are handled just opaquely and only the
-- attribute of the glue node itself is checked. For setting different colors
-- inside leaders, raw PDF literals have to be used.
--
-- We use the `node.direct` way of working with nodes. This is less safe, and
-- certainly not idiomatic Lua, but faster and codewise more close to the way
-- \TeX/ works with nodes.
local function is_color_needed(head, n, id, subtype) -- returns fill, stroke color needed
    if id == glyph_id then
        return true, false
    elseif id == glue_id then
        n = getleader(n)
        if n then
            return true, true
        end
    elseif id == rule_id then
        local width, height, depth = getwhd(n)
        if width <= one_bp or height + depth <= one_bp then
            -- running (-2^30) may need both
            return true, true
        end
        return true, false
    elseif id == whatsit_id and (subtype == pdfliteral_id
                or subtype == pdfsave_id
                or subtype == pdfrestore_id) then
        return true, true
    end
    return false, false
end

local function colorize(head, current, current_stroke, current_tr)
    for n, id, subtype in traverse(head) do
        if id == hlist_id or id == vlist_id then
            -- nested list, just recurse
            local list = getlist(n)
            list, current, current_stroke, current_tr =
               colorize(list, current, current_stroke, current_tr)
            setlist(n, list)
        elseif id == disc_id then
            -- at this point only no-break (replace) list is of any interest
            local replace = getfield(n, "replace")
            if replace then
                replace, current, current_stroke, current_tr =
                    colorize(replace, current, current_stroke, current_tr)
                setfield(n, "replace", replace)
            end
        else
            local fill_needed, stroke_needed = is_color_needed(head, n, id, subtype)
            local new = getattribute(n, color_attribute) or 0
            local newtr = getattribute(n, transp_attribute) or 0
            local newliteral = nil
            if current ~= new and fill_needed then
                newliteral = token_getmacro("_color:"..new)
                current = new
            end
            if current_stroke ~= new and stroke_needed then
                local stroke_color = token_getmacro("_color-s:"..current)
                if stroke_color then
                    if newliteral then
                        newliteral = fmt("%s %s", newliteral, stroke_color)
                    else
                        newliteral = stroke_color
                    end
                    current_stroke = new
                end
            end
            if newtr ~= current_tr and fill_needed then -- (fill_ or stroke_needed) = fill_neded
                if newliteral ~= nil then
                    newliteral = fmt("%s /tr%d gs", newliteral, newtr)
                else
                    newliteral = fmt("/tr%d gs", newtr)
                end
                current_tr = newtr
            end
            if newliteral then
                head = insertbefore(head, n, pdfliteral(newliteral))
            end
        end
    end
    return head, current, current_stroke, current_tr
end
--
-- Colorization should be run just before shipout. We use our custom callback
-- for this. See the definition of `pre_shipout_filter` for details on
-- limitations.
callback.add_to_callback("pre_shipout_filter", function(list)
    -- By setting initial color to -1 we force initial setting of color on
    -- every page. This is useful for transparently supporting other default
    -- colors than black (although it has a price for each normal document).
    local list = colorize(todirect(list), -1, -1, 0)
    return tonode(list)
end, "_colors")
--
-- We also hook into `luaotfload`'s handling of color and transparency. Instead
-- of the default behavior (inserting colorstack whatsits) we set our own
-- attribute. On top of that, we take care of transparency resources ourselves.
--
-- The hook has to be registered {\em after} `luaotfload` is loaded.
local setattribute = direct.set_attribute
local token_setmacro = token.set_macro
local color_count = registernumber("_colorcnt")
local tex_getcount, tex_setcount = tex.getcount, tex.setcount
--
local function set_node_color(n, color) -- "1 0 0 rg" or "0 g", etc.
    local attr = tonumber(token_getmacro("_color::"..color))
    if not attr then
        attr = tex_getcount(color_count)
        tex_setcount(color_count, attr + 1)
        local strattr = tostring(attr)
        token_setmacro("_color::"..color, strattr)
        token_setmacro("_color:"..strattr, color)
        token_setmacro("_color-s:"..strattr, string.upper(color))
    end
    setattribute(todirect(n), color_attribute, attr)
end
optex.set_node_color = set_node_color
--
function optex.hook_into_luaotfload()
    -- color support for luaotfload v3.13+, otherwise broken
    pcall(luaotfload.set_colorhandler, function(head, n, rgbcolor) -- rgbcolor = "1 0 0 rg"
        set_node_color(n, rgbcolor)
        return head, n
    end)

    -- transparency support for luaotfload v3.22+, otherwise broken
    pcall(function()
        luatexbase.add_to_callback("luaotfload.parse_transparent", function(input) -- from "00" to "FF"
            -- in luaotfload: 0 = transparent, 255 = opaque
            -- in optex:      0 = opaque,      255 = transparent
            local alpha = tonumber(input, 16)
            if not alpha then
                tex.error("Invalid transparency specification passed to font")
                return nil
            elseif alpha == 255 then
                return nil -- this allows luaotfload to skip calling us for opaque style
            end
            local transp = 255 - alpha
            local transpv = fmt("%.3f", alpha / 255)
            pdf.add_page_resource("ExtGState", fmt("tr%d", transp), pdf_dict{ca = transpv, CA = transpv})
            pdf.add_page_resource("ExtGState", "tr0", pdf_dict{ca = 1, CA = 1})
            return transp -- will be passed to the below function
        end, "optex")

        luaotfload.set_transparenthandler(function(head, n, transp)
            setattribute(n, transp_attribute, transp)
            return head, n
        end)
    end)
end

   -- History:
   -- 2022-08-25 expose some useful functions in `optex` namespace
   -- 2022-08-24 luaotfload transparency with attributes added
   -- 2022-03-07 transparency in the colorize() function, current_tr added
   -- 2022-03-05 resources management added
   -- 2021-07-16 support for colors via attributes added
   -- 2020-11-11 optex.lua released
