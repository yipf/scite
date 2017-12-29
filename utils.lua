module("utils",package.seeall)

local id=function(...)
	return ...
end
-- general functions
make_factory=function(preprocessor)
	local factory={}
	local rawget,rawset=rawget,rawset
	if type(preprocessor)~="function" then 
		preprocessor=id
	end
	return function(key,value)
		if not key then return factory end
		if not value then return rawget(factory,key) end
		key,value=preprocessor(key,value)
		rawset(factory,key,value)
		return value
	end
end

props2factory=function(props,preprocessor)
	local f=make_factory(preprocessor)
	if type(props)=="table" then 
		for k,v in pairs(props) do
			f(k,v)
		end
	end
	return f
end

get_value=function(ref,key,...)
	local tp=type(ref)
	if tp=="table" then 
		return rawget(ref,key)
	elseif tp=="function" then
		return ref(key,...)
	end
end

-- scite specific functions
suggest=function(pane,len,str,sep)
	pane.AutoCSeparator=string.byte(sep or "\n")
	pane.AutoCAutoHide=false
	pane:AutoCShow(len,str)
end

get_active_pane=function()
	return editor.Focus and editor or output.Focus and output
end

get_text=function(pane,s,e,keep_selection)
	local old_s,old_e=pane.SelectionStart ,pane.SelectionEnd 
	pane:SetSel(s,e)
	local text=pane:GetSelText()
	if not keep_selection then
		pane:SetSel(old_s,old_e)
	end
	return text
end

run_shell=function(cmd,body)
	if body then 
		cmd=cmd.." <<EOF\n"..body.."\nEOF"
	end
	return io.popen(cmd):read("*a")
end

local format=string.format
message=function(...)
	return print(format(...))
end

search_text_by_pattern=function(pane,pat,prev)
	if prev then 
		pane:GotoPos(pane.SelectionStart)
		pane:SearchAnchor()
		return pane:SearchPrev(SCFIND_REGEXP,pat)
	else
		pane:GotoPos(pane.SelectionEnd)
		pane:SearchAnchor()
		return pane:SearchNext(SCFIND_REGEXP,pat)
	end
end

local results={}
local append=function(element,index)
	results[index]=element
	return index+1
end
fetch=function(source,pattern,sep)
	local index=1
	for w in string.gmatch(source,pattern) do
		index=append(w,index)
	end
	return index>0 and table.concat(results,sep,1,index) or ""
end

gen_keys=function(tbl,sep,hotkey_format)
	local all={}
	local push=table.insert
	for k,v in pairs(tbl) do
		push(all,k)
	end
	if hotkey_format then 
		local replace=string.gsub
		for i,v in ipairs(all) do
			all[i]=format(hotkey_format,replace(all[i],"(%w)[a-z0-9]*_*","%1"),all[i])
		end
	end
	table.sort(all)
	return table.concat(all,sep)
end

split=function(str,pattern)
	local s,e=1,string.len(str)
	local sub=string.sub
	local results={}
	local push=table.insert
	for ss,ee in string.gmatch(str,"()"..pattern.."()") do
		push(results,ss>s and sub(str,s,ss-1) or "")
		s=ee
	end
	if s<e then push(results,sub(str,s+1,e)) end
	return results
end

str2file=function(str,path)
	local f=io.open(path,"w")
	if f then 
		f:write(str)
		f:close()
		return path
	end
end

file2str=function(path)
	local f=io.open(path)
	if f then 
		local s=f:read("*a")
		f:close()
		return s
	end
end

local push=table.insert

local object2str_
object2str_=function(object)
	local tp=type(object)
	if tp=="table" then 
		local t={}
		for i,v in ipairs(object) do
			t[i]=object2str_(v)
		end
		for k,v in pairs(object) do
			if t[k]==nil then 
				push(t,format("[%s]=%s",object2str_(k),object2str_(v)))
			end
		end
		return format("{%s}",table.concat(t,","))
	elseif tp=="string" then
		return format("%q",object)
--~ 	elseif tp=="function" then
--~ 		return format("load(%q)",string.dump(object))
	else
		return tostring(object)
	end
end

object2str=object2str_

local match=string.match
trim=function(str)
	return match(str,"^%s*(.-)%s*$")
end

