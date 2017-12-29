
--~ module("org",package.seeall)
require "utils"

local register_blocks=function(str,blocks)
	str=string.gsub("\n"..str,"\n<<(.*)>>=\n(.-)\n@([^\n]*)",function(name,source,option)
		local nonumbered,typename,caption=string.match(option,"^%s*(%*?)(%S+)%s*(.-)%s*$")
		blocks[name]={source=source,typename=typename or "source", caption=caption or name, name=name, numbered= nonumbered~="*"}
		return ""
	end)
	return str
end

local make_toc_func=function(tocs)
	local counters={}
	local update_id=function(key)
		local id=counters[key] or 0
		id=id+1
		counters[key]=id
		return id
	end
	local push=table.insert
	local gen_id=function(typename,level)
		if typename=="section" then 
			for i=level+1,#counters do
				counters[i]=0
			end
			update_id(level)
			return table.concat(counters,".",1,level)
		else
			return update_id(typename)
		end
	end
	return function(block)
		push(tocs, block)
		block.id= block.numbered and gen_id(block.typename, block.level) or ""
		return block
	end
end

local expand_source, get_block_content
expand_source=function(source, blocks, exporter, level, preprocess)
	source=string.gsub("\n"..source,"<<(.-)>>",function(name)
		local current_level=level+1
		local block=blocks[name]
		if not block then 
			block=utils.file2str(name)
			assert(block,string.format("Invalid block name %q",name))
			block={name=name, source=register_blocks(block,blocks), typename="source"}
			blocks[name]=block
		end
		-- get  hook from exporter
		local typename=block.typename
		if typename=="source" then 	
			return block.source 
		elseif typename=="section" then 
			typename=typename..current_level
		end
		local hook=exporter[typename]
		assert(hook,string.format("Invalid exproter %q",typename))
		if not block.content then 
			block.content=expand_source(block.source, blocks, exporter, current_level, preprocess)
		end
		block.level=current_level
		return hook(preprocess(block))
	end)
	return source
end

local exporters={}

local load_exporter=function(document_type,dst)
	local src=document_type and exporters[document_type]
	dst=dst or {}
	if src then
		for k,v in pairs(src) do
			dst[k]=v
		end
		if not dst.ext then dst.ext=document_type end
	end
	return dst
end

blocks_export=function(path)
	local blocks={}
	local tocs={}
	output:SetText(string.format("Loading blocks from file %q ... ", path))
	doc=register_blocks(utils.file2str(path), blocks)
	output:AppendText("Done!")
	local current_exporter=load_exporter("html")
	current_exporter.options=function(block)
		local options={}
		block=string.gsub("\n"..block.source,"\n:(%S+)([^\n]*)",function(key,value)
			options[key]=string.match(value,"^%s*(.-)%s$")
		end)
		current_exporter=load_exporter(options["document-type"],current_exporter)
		current_exporter.options=options
		return ""
	end
	output:AppendText("\nProcessing blocks ... ")
	doc=expand_source(doc, blocks, current_exporter,-1, make_toc_func(tocs))
	output:AppendText("Done!")
	output:AppendText("\nProcessing inline blocks ... ")
	-- inline blocks, to be implemented
	output:AppendText("Done!")
	local output_file=path.."."..(current_exporter.ext)
	output:AppendText(string.format("\nExporting to %q ... ", output_file))
	utils.str2file(doc,output_file)
	return output:AppendText("Done!")
end

----------------------------------------------------------------------------------------------------------------------------------------------
-- editor relative
----------------------------------------------------------------------------------------------------------------------------------------------

------------------------------------------------------
-- short-cuts
------------------------------------------------------

local blocks_bind=make_bind_function(20,"__blocks_function_%d","org")

blocks_bind("Alt+g","Go to header",make_user_list_processor(
function(pane)
	local headers,text={}
	local push,format,match=table.insert,string.format,string.match
	local level
	for i=0,pane.LineCount-1 do
		level,text=match(pane:GetLine(i),header_pattern)
		if text then  
			push(headers,format("%s\t:level %d\t@%d",text,level,i))
		end
	end
	return table.concat(headers),"\n"
end,
function(text,pane)
	pane:GotoLine(string.match(text,"(%d+)$"))
end,
"Go to header:"
))

blocks_bind("Alt+r","insert crossref",make_user_list_processor(
function(pane)
	local refs,text={}
	local push,format,match=table.insert,string.format,string.match
	for i=0,pane.LineCount-1 do
		text=match(pane:GetLine(i),"^#%+LABEL:%s*(.-%S)%s*$")
		if text then  
			push(refs,format("%s\t:%d",text,i))
		end
	end
	table.sort(refs)
	return table.concat(refs,"\n"),"\n"
end,
function(text,pane)
	pane:ReplaceSel(string.format("[ref:%s]",string.match(text,"^%s*(.-)%s*:%d+$")))
end,
"Go to header:"
))

------------------------------------------------------
-- lexers
------------------------------------------------------
local header_level=SC_FOLDLEVELHEADERFLAG+SC_FOLDLEVELBASE

local in_block=function(pane,line)
	local parent_line=pane.FoldParent[line]
	return parent_line and pane.FoldLevel[line]<header_level and  pane.FoldLevel[parent_line]== block_level
end

local lexer_temp_target={}
lexers("org",{
render=function(styles,styler,pane,default_style)
	local S=pane:LineFromPosition(styler.startPos)
	local E=pane:LineFromPosition(styler.startPos + styler.lengthDoc)
	pane:StartStyling(styler.startPos, default_style)
	local find,sub,match=string.find,string.sub, string.match
	for line=S,E do
		s,e=pane:PositionFromLine(line),pane:PositionFromLine(line+1)
		text=pane:GetLine(line)
		if not text then return end
		if match(text,"^<<(.*)>>=") then
			styler:SetLevelAt(line, header_level)
			pane:SetStyling(e-s, styles["block-begin"] or default_style) 
		elseif match(text,"^@") then
			styler:SetLevelAt(line, 1+header_level)
			pane:SetStyling(e-s, styles["block-end"] or default_style) 
		else
			s,e=1,e-s+1
			for ss,ee in string.gmatch(text,"()%b[]()") do
				if ss>s then pane:SetStyling(ss-s, default_style)  end
				pane:SetStyling(ee-ss, styles[sub(text,ss+1,ss+1)] or styles["link"] or default_style)
				s=ee
			end
			if s<e then pane:SetStyling(e-s, default_style) end
			styler:SetLevelAt(line, 1+header_level)
		end
	end
end,
exts={"blocks"},
styles={
	["block-begin"]="$(colour.keyword),bold",
	["block-end"]="$(colour.comment),bold",
	["link"]="$(colour.keyword),underlined",
	["$"]="$(colour.number),italics",
	["`"]="$(colour.string)",
	["*"]="bold",
	["="]="font:Courier New",
}
})

props["command.go.*.blocks"]="blocks_export $(FileNameExt)"
props["command.go.subsystem.*.blocks"]=3
props["abbreviations.*.blocks"]="$(SciteUserHome)/blocks_abbrev.properties"

blocks_string2exporter=function(str)
	return function(block)
		return string.gsub(str,"@(.-)@",block)
	end
end

blocks_register_exporter=function(name,exporter)
	exporters[name]=exporter
end

blocks_register_exporter("html",{
["section0"]=blocks_string2exporter[[
<html>
<head>
<title>@caption@</title>
</head>
<body>
<h0>@caption@</h0>
@content@
</body>
</html>	
]],
["section1"]=blocks_string2exporter[[
<div id="sec:@id@">
<h1>@id@ @caption@</h1>
@content@
</div>
]],
["section2"]=blocks_string2exporter[[
<div id="sec:@id@">
<h2>@id@ @caption@</h2>
@content@
</div>
]],
["section3"]=blocks_string2exporter[[
<div id="sec:@id@">
<h3>@id@ @caption@</h3>
@content@
</div>
]],
})


