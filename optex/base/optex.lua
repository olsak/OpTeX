-- This is part of the OpTeX project, see http://petr.olsak.net/optex

-- The basic lua functions and declarations used in \OpTeX/ are here

-- GENERAL

-- Error function used by following functions for critical errors.
local function err(message)
    error("\nerror: "..message.."\n")
end
--
-- For a `\chardef`'d, `\countdef`'d, etc., csname return corresponding register
-- number. The responsibility of providing a `\XXdef`'d name is on the caller.
function registernumber(name)
    return token.create(name).index
end
--
-- ALLOCATORS
alloc = alloc or {}
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
-- `provides_module` is needed by older version of luaotfload
provides_module = function() end
--
-- CALLBACKS
callback = callback or {}
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
        assert(callback_register(name, function(...)
            return callback.call_callback(name, ...)
        end))
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
    local new_head = callback.call_callback("pre_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end
    -- mlist_to_hlist means either added functions or standard luatex behavior
    -- of node.mlist_to_hlist (handled by default function)
    head = callback.call_callback("mlist_to_hlist", head, ...)
    -- post_mlist_to_hlist_filter
    new_head = callback.call_callback("post_mlist_to_hlist_filter", head, ...)
    if new_head == false then
        node.flush_list(head)
        return nil
    elseif new_head ~= true then
        head = new_head
    end
    return head
end)
--
-- Compatibility with \LaTeX/ through luatexbase namespace. Needed for
-- luaotfload.
luatexbase = {
    registernumber = registernumber,
    attributes = attributes,
    provides_module = provides_module,
    new_attribute = alloc.new_attribute,
    callback_descriptions = callback.callback_descriptions,
    create_callback = callback.create_callback,
    add_to_callback = callback.add_to_callback,
    remove_from_callback = callback.remove_from_callback,
    call_callback = callback.call_callback,
    callbacktypes = {}
}
