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
-- Allocator for Lua functions ("pseudoprimitives"). It passes variadic
-- arguments (`...`) like \"global" to `token.set_lua`.
local function_table = lua.get_functions_table()
local luafnalloc = 0
function define_lua_command(csname, fn, ...)
    luafnalloc = luafnalloc + 1
    token.set_lua(csname, luafnalloc, ...)
    function_table[luafnalloc] = fn
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
--
-- `\tracingmacros` callback registered.
-- Use `\tracingmacros=3` or `\tracingmacros=4` if you want to see the result.
callback.add_to_callback("input_level_string",
   function(n)
       if tex.tracingmacros > 3 then
          return "[" .. n .. "] "
       elseif tex.tracingmacros > 2 then
          return "~" .. string.rep(".",n)
       end
   end
)
--
-- Handling of color using attributes
--
-- Setting of color in PDF is handled by graphics operators which change the
-- graphics context. Colors for fills/strokes are distinguished, but apart from
-- that, only one color is active at time and is used for all material drawn by
-- following graphics operators, until next color is set. Each PDF content (e.g.
-- page or form XObject) has its own graphics context, that is initialized from
-- zero. Hence natural way of working with color (color settings are not lost
-- by going between pages) have to be handled.
--
-- \TeX/ itself has no concept of color. Color has always been handled by
-- inserting whatsits (either using `\special` for DVI or using
-- `\pdfliteral`/`\pdfcolorstack` for PDF). It is very efficient way of doing
-- it, \TeX/ doesn't have to know anything about colors, it just inserts the
-- relevant literals when doing `\shipout`. However, it is also problematic in
-- many ways:
--
-- \begitems
-- * Due to the asynchronic nature of shipping out pages, the handling of
-- initial color of page (which should be the last color of previous page) is
-- problematic.
-- * In \TeX/ there isn't only contiguous page content, but also headlines,
-- footlines and inserts (including footnotes). They shouldn't just take color
-- from what just happens to be preceding, but should be colored independently.
-- * Whatsit nodes are not really fully transparent to all stages of \TeX/ and
-- just turning on/off color can result in differently typeset documents. See
-- e.g.
--  \begitems
--   * \url{https://tex.stackexchange.com/questions/599165/why-does-color-change-vertical-alignement-in-table-with-fixed-width/}
--   * \url{https://tex.stackexchange.com/questions/599367/strange-vertical-spacing-after-colored-equation/}
--  \enditems
-- * To give a false notion of grouping with whatsits, implementations usually
-- set color and try to restore it with `\aftergroup`, which has its own quirks,
-- e.g:
--\begtt
--\setbox0=\hbox{\Red text}   % bad:  \Black is done after `\setbox`
--\setbox0=\hbox{{\Red text}} % good: \Black is done after group inside the box
--\endtt
-- \enditems
--
-- While the first two issues can be handled using `\pdfcolorstack`, the color
-- handling is still not really natural.
--
-- With \LuaTeX/ different approach is possible. We can set attributes, which
-- are bound to essentially everything \TeX/ creates (characters, rules, glues,
-- \dots) and respect grouping. Their behaviour is similar to that of font
-- setting on characters. In \TeX, every typeset character is internally a
-- char node that carries a font number with itself. This associated font number
-- stays the same and doesn't change on even on boxing/unboxing.
--
-- We can do the same with colors. It is a somewhat radical change, because some
-- coloring idioms may not work like before. But with a different mindset it
-- indeed seems more natural. If we create a box with text in default (black)
-- color, why should it change just because something before it says `\Yellow`?
-- If a footnote is created with color red it should be red regardless on what
-- pages it is typeset at (and what they contain).
--
-- Because \LuaTeX/ doesn't do anything with attributes, we have to add meaning
-- to them. We do this by intercepting \TeX/ just before it ships out a page and
-- inject PDF literals according to attributes.
--
local node_id, node_subtype = node.id, node.subtype
local glyph_id = node_id("glyph")
local rule_id = node_id("rule")
local glue_id = node_id("glue")
local hlist_id = node_id("hlist")
local vlist_id = node_id("vlist")
local whatsit_id = node_id("whatsit")
local pdfliteral_id = node_subtype("pdf_literal")
local pdfsave_id = node_subtype("pdf_save")
local pdfrestore_id = node_subtype("pdf_restore")
local setattribute = tex.setattribute
local tex_shipout = tex.shipout
local tex_setbox = tex.setbox
local token_scanlist = token.scan_list
local token_scanargument = token.scan_argument
local token_scanint = token.scan_int
local token_getmacro = token.get_macro

local direct = node.direct
local todirect = direct.todirect
local tonode = direct.tonode
local getfield = direct.getfield
local setfield = direct.setfield
local getlist = direct.getlist
local setlist = direct.setlist
local getleader = direct.getleader
local getattribute = direct.get_attribute
local insertbefore = direct.insert_before
local copy = direct.copy
local traverse = direct.traverse
local getbox = direct.getbox
local one_bp = tex.sp("1bp")

-- We first allocate an attribute for coloring.
local color_attribute = registernumber("_colorattr")
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
--
-- This is the function that goes through a node list and injects PDF literals
-- according to attributes. Its arguments are the head of the list to be
-- colored and the current color. It is a recursive function – nested
-- horizontal and vertical lists are handled in the same way. Only the
-- attributes of “content” nodes matter, these include most importantly glyph
-- nodes and rule nodes which are colored directly, but also PDF literals and
-- similar, which also participate in coloring.
--
-- Whatsit node with color setting PDF literal is injected only when a
-- different color is needed, hence there shouldn't be any unnecessary
-- consecutive color changes which can happen with use of pdfTeX's color stack.
-- Our injection does not care about boxing levels, but this isn't a problem,
-- since (when placed correctly), PDF literal whatsits just instruct the
-- `\shipout` related procedures to emit the literal now.
--
-- Leaders (represented by glue nodes with leader field) are not handled fully.
-- They are problematic, because their content is repeated more times and it
-- would have to be ensured that the coloring would be right even for e.g.
-- leaders that start and end on a different color. I came to conclusion that
-- this is not worth, hence leaders are handled just opaquely and only the
-- attribute of the glue node itself is checked. For setting different colors
-- inside leaders, raw PDF literals have to be used.
--
-- We use the `node.direct` way of working with nodes. This is less safe, and
-- certainly not idiomatic Lua, but faster and codewise more close to the way
-- \TeX/ works with nodes.
--
local function colorize(head, current)
    for n, id, subtype in traverse(head) do
        if id == hlist_id or id == vlist_id then
            -- nested list, just recurse
            local list = getlist(n)
            list, current = colorize(list, current)
            setlist(n, list)
        elseif id == glyph_id or id == disc_id or id == rule_id
                or (id == glue_id and getleader(n))
                or (id == whatsit_id
                    and (subtype == pdfliteral_id
                        or subtype == pdfsave_id
                        or subtype == pdfrestore_id)) then
            -- color participating node, check if current color has to change
            local new = getattribute(n, color_attribute) or 0
            if new ~= current then
                local color = token_getmacro("_color:"..new)
                head = insertbefore(head, n, pdfliteral(color))
                current = new
            end
        end
    end
    return head, current
end
-- Because it is so easy to use different default/initial color other than
-- black, we allow it. Of course we need to change what `colors` maps to/from
-- `0`. Furthermore we need to note that black is special, because that is what
-- all pages start on. For any other color we need to force an initial color setting in `colorize`,
-- regardless of what color is currently set. This is handled by
-- `initial_color`, the initial value of `colorize`'s `current`. For black it
-- can be `0` (current/initial color is indeed black), but if set to something
-- not equal to any number assigned to color (we use `-1`) initial color is set
-- to color `0` (now most probably non-black).
--
local initial_color = 0
--
-- Now we need to somehow allow \TeX/ to use `colorize` on otherwise finished
-- boxes. We do this by redefining `\_shipout`, which means that our mechanism
-- works almost transparently to the end user. This is sadly not really possible
-- with \pdfxform, which creates PDF form XObjects (very similiar to PDF page
-- content). Redefining the said primitive is not sufficient, because of
-- `\immediate`. Those that want to colorize boxes before transforming them to
-- xforms should use \`\_colorizebox``<boxnum>`.
--
define_lua_command("_shipout", function()
    print("luashipout")
    local list = token_scanlist()
    list = tonode(colorize(todirect(list), initial_color))
    tex_setbox(0, list)
    tex_shipout(0)
end)
--
define_lua_command("_colorizebox", function()
    local boxnum = token_scanint()
    colorize(getbox(boxnum), initial_color)
end)
