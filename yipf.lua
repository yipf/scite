local info = debug.getinfo(1, "S") -- 第二个参数 "S" 表示仅返回 source,short_src等字段， 其他还可以 "n", "f", "I", "L"等 返回不同的字段信息  
local dir = string.match(info.source , "^@(.*)/") -- 捕获最后一个 "/" 之前的部分 就是我们最终要的目录部分  
package.path=dir.."/?.lua;"..package.path

require "utils"

local get_active_pane=utils.get_active_pane
local make_factory=utils.make_factory
local suggest=utils.suggest
local search_text_by_pattern=utils.search_text_by_pattern
local message=utils.message
local gen_keys=utils.gen_keys
local run_shell=utils.run_shell
-- onchar
local matchers={["("]=")",["["]="]",["{"]="}",["\""]="\""}  
OnChar=function(ch)
	local pane=get_active_pane()
	local m=matchers[ch]
	if m then
		pane:InsertText(-1,m)
		return true
	end
	return false
end

-- lexer
local format=string.format
lexers=make_factory(function(lang,lexer)
	lang=format("script_%s",lang)
	local props=props
	if type(lexer.exts)=="table" then 
		for i,ext in ipairs(lexer.exts) do
			props[format("lexer.*.%s;",ext)]=lang
		end
	end
	if type(lexer.styles)=="table" then 
		local id=0;
		local styles=lexer.styles
		for k,v in pairs(styles) do
			id=id+1
			styles[k]=id
			props[format("style.%s.%d",lang,id)]=v
		end
	end
	if type(lexer.etc)=="table" then 
		for k,v in pairs(lexer.etc) do
			props[k]=v
		end
	end
	return lang,lexer
end)
OnStyle=function(styler)
	local lexer=lexers(props["Language"])
	if lexer then
		lexer.render(lexer.styles,styler,editor,31)
	end
end

-- hooks
hooks=make_factory()
make_self_hook=function(func)
	local hook
	hook=function()
		func()
		return hook
	end
	return hook
end
try_execute_hook=function()
	local hook=buffer.hook;
	if type(hook)=="function" then
		buffer.hook=hook(pos)
		return true;
	end
	return false
end

-- smart tab
-- http://www.scintilla.org/CommandValues.html
local smart_tab=function()
	if try_execute_hook() then return true end
	local pane=get_active_pane()
	if pane.SelectionEmpty then 
		local pos=pane.CurrentPos
		local line_start=pane:PositionFromLine(pane:LineFromPosition(pos))
		if pos==line_start then 
			scite.MenuCommand(IDM_EXPAND)
			return true
		end
		local str=pane:textrange(line_start,pos)
		local dir,sub=string.match(str,"^.-([^\":%s]*/)(%S-)$")
		if dir then -- try expand this path
			if string.sub(dir,1,1)~="/" then 
				dir=props["FileDir"].."/"..dir
			end
			suggest(pane,string.len(sub),run_shell(string.format("ls -1 -p %q",dir)),"\n")
			return true
		elseif string.match(str,"%S$") then -- try expand abbrev
			scite.MenuCommand(IDM_ABBREV)
			return true
		end
	end
	return pane:Tab()
end

-- user list
user_list_hooks=make_factory()
local user_list_base=11
local new_user_list=function(func)
	user_list_base=user_list_base+1
	user_list_hooks(user_list_base,func)
	return user_list_base
end
make_user_list_processor=function(trigger,handler,message)
	user_list_base=user_list_base+1
	local id=user_list_base
	user_list_hooks(id,handler)
	message=message or ""
	return function()
		local result,sep=trigger(editor)
		if result then 
			output:GrabFocus()
			output:Clear()
			print(message)
			sep=sep or "\n"
			output.AutoCSeparator=string.byte(sep)
			output:UserListShow(id,result)
		end
	end
end
OnUserListSelection=function(typeid,selected)
	local hook=user_list_hooks(typeid)
	if type(hook)=="function" then 
		editor:GrabFocus()
		return hook(selected,editor)
	end
	return false
end
local keys=false

-- user list to process hook selector
local keys=nil
toggle_hook=make_user_list_processor(function(pane)
	if buffer.hook then -- cancel previous hook
		buffer.hook=false
	end
	return keys or gen_keys(hooks(),"\n","%s0:%s"),"\n"
end,
function(selected,pane)
	buffer.hook=hooks(string.match(selected,"^.-:(.*)$"))
	return try_execute_hook() 	
end,
"Choose a hook:")

-- key binding
make_bind_function=function(base,namefmt,lang)
	base= base or 0
	func_name_format=func_name_format or "_%d"
	lang=lang and "*."..lang or "*"
	local format=string.format
	return function(key,des,action)
		local subsystem,name=1,action
		base=base+1
		if type(action)=="function" then 
			subsystem=3
			name=format(func_name_format,base)
			_G[name]=action
		end
		local tail=format("%d.%s",base,lang)
		props[format("command.name.%s",tail)]=des or name
		props[format("command.%s",tail)]=name
		props[format("command.subsystem.%s",tail)]=subsystem
		props[format("command.mode.%s",tail)]="savebefore:no"
		props[format("command.shortcut.%s",tail)]=key
	end
end
-- user  user customize
user_binding=make_bind_function(0,"user_function_%d")

user_binding("Alt+x","Toggle Hook",toggle_hook)
user_binding("Tab","Smart Tab",smart_tab)
user_binding("Alt+d","Dictionary","sdcv -n $(CurrentWord)")

user_binding("Escape","Cancel",function()
	if buffer.hook then -- cancel previous hook
		buffer.hook=false
	end
	get_active_pane():Cancel()
	editor:GrabFocus()
end)

--~ functions can accessed both by shortcut and toggle hook
local suggest_word=function(pane)
	local word=pane:GetSelText()
	local list=run_shell(string.format("echo %q | aspell -a",word)):match("\n&.-:%s*(%w.*%w)")
	if list then 
		message("%q is wrong!",pane:GetSelText())
		if pane.CurrentPos~=pane.SelectionEnd then pane:SwapMainAnchorCaret() end
		suggest(pane,pane.SelectionEnd-pane.SelectionStart,list:gsub("%s*",""),",")
	end
	return list
end

user_binding("Alt+s","Spell check",hooks("spell_check",function()
	local pane=editor
	editor:WordPartLeft()
	editor:WordRightEndExtend()
	if not suggest_word(pane) then
		message("%q is right!",pane:GetSelText())
	end
end))

hooks("spell_check_rest",make_self_hook(function()
	local pane=editor
	local pos
	repeat
		pos=search_text_by_pattern(pane,"\\w+")
	until pos<0 or suggest_word(pane)
end))

user_binding("Alt+p","Select paragraph",hooks("select_paragraph",function()
	local pane=get_active_pane()
	pane:ParaUp()
	pane:ParaDownExtend()
end))

user_binding("Alt+f","Select fold",hooks("select_folder",function()
	local pane=get_active_pane()
	local parentline=pane.FoldParent[pane:LineFromPosition(pane.CurrentPos)]
	if parentline>=0 then 
		pane:GotoLine(parentline)
		pane:SetSel(pane:PositionFromLine(parentline),pane.LineEndPosition[pane:GetLastChild(parentline, pane.FoldLevel[parentline])])
	else
		print("Current line is not in any fold!")
	end
end))

local maxmin=function(a,b)
	if a>b then return b,a end
	return a,b
end
user_binding("Alt+b","select brace",hooks("select_brace",function()
	local pane=get_active_pane()
	local pos=pane.CurrentPos
	local maybe=search_text_by_pattern(pane,"[\\[\\{\\(]",true)
	local s,e
	while maybe and maybe>=0 do
		scite.MenuCommand(IDM_SELECTTOBRACE)
		s,e=maxmin(pane.SelectionStart,pane.SelectionEnd)
		if pos>s and pos<e then 
			pane:SetSel(s+1,e-1)
			return 
		end
		maybe=search_text_by_pattern(pane,"[\\[\\{\\(]",true)
	end
	pane:GotoPos(pos)
	print("Current position is not in any brace!")
end))

user_binding("Alt+[","select prev brace",hooks("select_brace",function()
	local pane=get_active_pane()
	local s,e=maxmin(pane.SelectionStart,pane.SelectionEnd)
	pane:GotoPos(s)
	local maybe=search_text_by_pattern(pane,"[\\[\\{\\(]",true)
	if maybe and maybe>0 then 
		s,e=maxmin(pane.SelectionStart,pane.SelectionEnd)
		pane:GotoPos(s)
		scite.MenuCommand(IDM_SELECTTOBRACE)
		return 
	end
	print("No prev brace exist!")
end))

user_binding("Alt+]","select next brace",hooks("select_brace",function()
	local pane=get_active_pane()
	local s,e=maxmin(pane.SelectionStart,pane.SelectionEnd)
	pane:GotoPos(e)
	local maybe=search_text_by_pattern(pane,"[\\]\\}\\)]")
	if maybe and maybe>0 then 
		s,e=maxmin(pane.SelectionStart,pane.SelectionEnd)
		pane:GotoPos(e)
		scite.MenuCommand(IDM_SELECTTOBRACE)
		return 
	end
	print("No next brace exist!")
end))

user_binding("Alt+l","select line",hooks("select_line",function()
	local pane=get_active_pane()
	pane:Home()
	pane:LineEndExtend()
end))
 
user_binding("Alt+m","Mark all folders",hooks("mark_folders",function()
	output:Clear()
	local format=string.format
	local filepath=props["FilePath"]
	local trim=utils.trim
	for i=0,editor.LineCount-1 do
		if editor.FoldLevel[i]>SC_FOLDLEVELHEADERFLAG then  
			print(format("%s:%d:\t%s",filepath,i+1,trim(editor:GetLine(i))))
		end
	end
end))

require "blocks/core"
