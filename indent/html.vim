" Vim indent script
" Comments: "{{{
" File:		html.vim
" Author:	Andy Wokula, anwoku#yahoo*de (#* -> @.)
" Last Change:	2007 Nov 18
" Version:	0.2 (still experimental)
" Vim Version:	Vim7
" Description:
" - Speedup: uses state and benefits of Vim7
" - more exact: checks all the tags in a line, considers comments
" - uses search() instead of searchpair()
" - no extra indent after <html>, <head>, <body>, <tbody>; <script> content
"   starts with zero indent
" - s:Alien*() functions for indenting inner block contents
" - command :IndHtmlLocal for tuning script internals
" - no syntax dependencies
" Based On:
" - the distributed script from J. Zellner (last change 2006 Jun 05)
" Example:
"   2900 non-blank lines of http://www.weather.com/weather/local/USPA0372
"   without state: 11.75 sec (already much faster than the old script)
"   with state: 2.27 sec (again 5 times faster) (machine 1.2 GHz Athlon)
" Problems:
" - natural state problem:
"	indent line N with "=="
"	change line N with ">>"	    (no update of state)
"	indent line N+1 with "=="   (wrong indent)
"	indent line N+1 with "=="   (workaround to get correct indent)
"   I won't fix this
" - quite bloated
" - attributes spanning over several lines
" - s:FreshState() doesn't ignore a commented blocktag; other nesting
"   problems
" Hmm:
" ? use of the term "blocktag"
" ? call "<!--" and "-->" tags
 "}}}

" Init Folklore: "{{{
if exists("b:did_indent")
    finish
endif
let b:did_indent = 1

setlocal indentexpr=HtmlIndent(v:lnum)
setlocal indentkeys=o,O,*<Return>,<>>,{,},!^F

let b:indent = {"lnum": -1}
let b:undo_indent = "set inde< indk<| unlet b:indent"

" Load Once:
if exists("*s:FreshState")
    finish
endif

let s:cpo_save = &cpo
set cpo-=C
 "}}}

" Init Script Vars  "{{{
let s:usestate = 1
" not to be changed:
let s:endtags = []
let s:newstate = {}
let s:countonly = 0
 "}}}
func! s:IndAdder(tag, ...) "{{{
    " a:tag
    "	tag that changes indent
    " a:1
    "	1 (default): add an indent [unit shiftwidth] for next line
    "	2,3,4: special values (no indents!) for opening blocktags:
    "	    <pre>, <script>, <style>
    "	5: comments <!-- -->
    " a:2
    "	explicit closing tag
    "	if not given, "/".tag is implied
    let val = a:0==0 ? 1 : a:1
    let g:html_indent_tags[a:tag] = val
    let c_tag = a:0<2 ? '/'.a:tag : a:2
    let g:html_indent_tags[c_tag] = -val
    if val >= 2
	if len(s:endtags) < val-2+1
	    call extend(s:endtags, range(2, val-len(s:endtags)))
	endif
	let s:endtags[val-2] = a:0<2 ? '<'.c_tag.'>' : c_tag
    endif
endfunc

func! s:NoIndAdder(...)
    " remove tags from g:html_indent_tags
    for itag in a:000
	sil! unlet g:html_indent_tags[itag]
	if itag =~ '^\a\+$'
	    sil! unlet g:html_indent_tags["/".itag]
	endif
    endfor
endfunc

"}}}
" IndAdder Calls: {{{
if !exists("g:html_indent_tags")
    let g:html_indent_tags = {}
endif
call s:IndAdder('a')
call s:IndAdder('abbr')
call s:IndAdder('acronym')
call s:IndAdder('address')
call s:IndAdder('b')
call s:IndAdder('bdo')
call s:IndAdder('big')
call s:IndAdder('blockquote')
call s:IndAdder('button')
call s:IndAdder('caption')
call s:IndAdder('center')
call s:IndAdder('cite')
call s:IndAdder('code')
call s:IndAdder('colgroup')
call s:IndAdder('del')
call s:IndAdder('dfn')
call s:IndAdder('dir')
call s:IndAdder('div')
call s:IndAdder('dl')
call s:IndAdder('em')
call s:IndAdder('fieldset')
call s:IndAdder('font')
call s:IndAdder('form')
call s:IndAdder('frameset')
call s:IndAdder('h1')
call s:IndAdder('h2')
call s:IndAdder('h3')
call s:IndAdder('h4')
call s:IndAdder('h5')
call s:IndAdder('h6')
call s:IndAdder('i')
call s:IndAdder('iframe')
call s:IndAdder('ins')
call s:IndAdder('kbd')
call s:IndAdder('label')
call s:IndAdder('legend')
call s:IndAdder('map')
call s:IndAdder('menu')
call s:IndAdder('noframes')
call s:IndAdder('noscript')
call s:IndAdder('object')
call s:IndAdder('ol')
call s:IndAdder('optgroup')
call s:IndAdder('q')
call s:IndAdder('s')
call s:IndAdder('samp')
call s:IndAdder('select')
call s:IndAdder('small')
call s:IndAdder('span')
call s:IndAdder('strong')
call s:IndAdder('sub')
call s:IndAdder('sup')
call s:IndAdder('table')
call s:IndAdder('textarea')
call s:IndAdder('title')
call s:IndAdder('tt')
call s:IndAdder('u')
call s:IndAdder('ul')
call s:IndAdder('var')
"}}}
" Block Tags: contain alien content "{{{
call s:IndAdder('pre', 2)
call s:IndAdder('script', 3)
call s:IndAdder('style', 4)
" Exception: handle comment delimiters <!--...--> like block tags
call s:IndAdder("<!--", 5, '-->')
" if !exists('g:html_indent_strict')
"     call s:IndAdder('body')
"     call s:IndAdder('head')
"     call s:IndAdder('tbody')
" endif

if !exists('g:html_indent_strict_table')
    call s:IndAdder('th')
    call s:IndAdder('td')
    call s:IndAdder('tr')
    call s:IndAdder('tfoot')
    call s:IndAdder('thead')
endif "}}}

func! s:CountITags(...) "{{{

    " relative indent steps for current line [unit &sw]:
    let s:curind = 0
    " relative indent steps for next line [unit &sw]:
    let s:nextrel = 0

    if a:0==0
	let s:block = s:newstate.block
	let tmpline = substitute(s:curline, '<\zs\/\=\a\+\>\|<!--\|-->', '\=s:CheckTag(submatch(0))', 'g')
	if s:block == 3
	    let s:newstate.scripttype = s:GetScriptType(matchstr(tmpline, '\C.*<SCRIPT\>\zs[^>]*'))
	endif
	let s:newstate.block = s:block
    else
	let s:block = 0		" assume starting outside of a block
	let s:countonly = 1	" don't change state
	let tmpline = substitute(s:altline, '<\zs\/\=\a\+\>\|<!--\|-->', '\=s:CheckTag(submatch(0))', 'g')
	let s:countonly = 0
    endif
endfunc "}}}
func! s:CheckTag(itag) "{{{
    " "tag" or "/tag" or "<!--" or "-->"
    let ind = get(g:html_indent_tags, a:itag)
    if ind == -1
	" closing tag
	if s:block != 0
	    " ignore itag within a block
	    return "foo"
	endif
	if s:nextrel == 0
	    let s:curind -= 1
	else
	    let s:nextrel -= 1
	endif
    elseif ind == 1
	" opening tag
	if s:block != 0
	    return "foo"
	endif
	let s:nextrel += 1
    elseif ind != 0
	" block-tag (opening or closing)
	return s:Blocktag(a:itag, ind)
    endif
    " else ind==0 (other tag found): keep indent
    return "foo"   " no matter
endfunc "}}}
func! s:Blocktag(blocktag, ind) "{{{
    if a:ind > 0
	" a block starts here
	if s:block != 0
	    " already in a block (nesting) - ignore
	    " especially ignore comments after other blocktags
	    return "foo"
	endif
	let s:block = a:ind		" block type
	if s:countonly
	    return "foo"
	endif
	let s:newstate.blocklnr = s:lnum	" not used
	" save allover indent for the endtag
	let s:newstate.blocktagind = b:indent.baseindent + (s:nextrel + s:curind) * &shiftwidth
	if a:ind == 3
	    return "SCRIPT"    " all except this must be lowercase
	    " line is to be checked again for the type attribute
	endif
    else
	let s:block = 0
	" we get here if starting and closing block-tag on same line
    endif
    return "foo"
endfunc "}}}
func! s:GetScriptType(str) "{{{
    if a:str == "" || a:str =~ "java"
	return "javascript"
    else
	return ""
    endif
endfunc "}}}

func! s:FreshState(lnum) "{{{
    " Look back in the file (lines 1 to a:lnum-1) to calc a state for line
    " a:lnum.  A state is to know ALL relevant details about the lines
    " 1..a:lnum-1, initial calculating (here!) can be slow, but updating is
    " fast (incremental).
    " State:
    " 	lnum		last indented line == prevnonblank(a:lnum - 1)
    " 	block = 0	a:lnum located within special tag: 0:none, 2:<pre>,
    "			3:<script>, 4:<style>, 5:<!--
    "	baseindent	use this indent for line a:lnum as a start - kind of
    "			autoindent (if block==0)
    " 	scripttype = ''	type attribute of a script tag (if block==3)
    " 	blocktagind	indent for current opening (get) and closing (set)
    "			blocktag (if block!=0)
    "	blocklnr	lnum of starting blocktag (if block!=0)
    let state = {}
    let state.lnum = prevnonblank(a:lnum - 1)
    let state.scripttype = ""
    let state.blocktagind = -1
    let state.block = 0
    let state.baseindent = 0
    let state.blocklnr = 0

    if state.lnum == 0
	return state
    endif

    " Heuristic:
    " remember startline state.lnum
    " look back for <pre, </pre, <script, </script, <style, </style tags
    " remember stopline
    " if opening tag found,
    "	assume a:lnum within block
    " else
    "	look back in result range (stopline, startline) for comment
    "	    \ delimiters (<!--, -->)
    "	if comment opener found,
    "	    assume a:lnum within comment
    "	else
    "	    assume usual html for a:lnum
    "	    if a:lnum-1 has a closing comment
    "		look back to get indent of comment opener
    " FI

    " look back for blocktag
    call cursor(a:lnum, 1)
    let [stopline, stopcol] = searchpos('\c<\zs\/\=\%(pre\>\|script\>\|style\>\)', "bW")
    " fugly ... why isn't there searchstr()
    let tagline = tolower(getline(stopline))
    let blocktag = matchstr(tagline, '\/\=\%(pre\>\|script\>\|style\>\)', stopcol-1)
    if stopline > 0 && blocktag[0] != "/"
	" opening tag found, assume a:lnum within block
	let state.block = g:html_indent_tags[blocktag]
	if state.block == 3
	    let state.scripttype = s:GetScriptType(matchstr(tagline, '\>[^>]*', stopcol))
	endif
	let state.blocklnr = stopline
	" check preceding tags in the line:
	let s:altline = tagline[: stopcol-2]	" XXX -1, -2, -3?
	call s:CountITags(1)
	let state.blocktagind = indent(stopline) + (s:curind + s:nextrel) * &shiftwidth
	return state
    elseif stopline == state.lnum
	" handle special case: previous line (= state.lnum) contains a
	" closing blocktag which is preceded by line-noise;
	" blocktag == "/..."
	let swtag = match(tagline, '^\s*<') >= 0
	if !swtag
	    let [bline, bcol] = searchpos('<'.blocktag[1:].'\>', "bW")
	    let s:altline = tolower(getline(bline)[: bcol-2])
	    call s:CountITags(1)
	    let state.baseindent = indent(bline) + (s:nextrel+s:curline) * &shiftwidth
	    return state
	endif
    endif

    " else look back for comment
    call cursor(a:lnum, 1)
    let [comline, comcol, found] = searchpos('\(<!--\)\|-->', 'bpW', stopline)
    if found == 2
	" comment opener found, assume a:lnum within comment
	let state.block = 5
	let state.blocklnr = comline
	" check preceding tags in the line:
	let s:altline = tolower(getline(comline)[: comcol-2])
	call s:CountITags(1)
	let state.blocktagind = indent(comline) + (s:curind + s:nextrel) * &shiftwidth
	return state
    endif

    " else within usual html
    let s:altline = tolower(getline(state.lnum))
    " check a:lnum-1 for closing comment (we need indent from the opening line)
    let comcol = stridx(s:altline, '-->')
    if comcol >= 0
	call cursor(state.lnum, comcol+1)
	let [comline, comcol] = searchpos('<!--', 'bW')
	if comline == state.lnum
	    let s:altline = s:altline[: comcol-2]
	else
	    let s:altline = tolower(getline(comline)[: comcol-2])
	endif
	call s:CountITags(1)
	let state.baseindent = indent(comline) + (s:nextrel+s:curline) * &shiftwidth
	return state
	" TODO check tags that follow the closing comment delimiter
    endif

    " else no comments
    call s:CountITags(1)
    let state.baseindent = indent(state.lnum) + s:nextrel * &shiftwidth
    " line starts with tag
    let swtag = match(s:altline, '^\s*<') >= 0
    if !swtag
	let state.baseindent += s:curind * &shiftwidth
    endif
    return state
endfunc "}}}

func! s:Alien2() "{{{
    " <pre> block
    return -1
endfunc "}}}
func! s:Alien3() "{{{
    " <script> javascript
    if prevnonblank(s:lnum-1) == b:indent.blocklnr
	" indent for the first line after <script>
	return 0
    endif
    if b:indent.scripttype == "javascript"
	return cindent(s:lnum)
    else
	return -1
    endif
endfunc "}}}
func! s:Alien4() "{{{
    " <style>
    return -1
endfunc "}}}
func! s:Alien5() "{{{
    " <!-- -->
    return -1
endfunc "}}}

func! HtmlIndent(lnum) "{{{
    let s:lnum = a:lnum
    let s:curline = tolower(getline(s:lnum))

    let s:newstate = {}
    let s:newstate.lnum = s:lnum

    " is the first non-blank in the line the start of a tag?
    let swtag = match(s:curline, '^\s*<') >= 0

    if prevnonblank(s:lnum-1) == b:indent.lnum && s:usestate
	" use state (continue from previous line)
    else
	" start over (know nothing)
	let b:indent = s:FreshState(a:lnum)
    endif

    if b:indent.block != 0
	" within block
	" if not 0 then always >= 2 (esp. not negative)
	let endtag = s:endtags[b:indent.block-2]
	let blockend = stridx(s:curline, endtag)
	if blockend >= 0
	    " block ends here
	    let s:newstate.block = 0
	    " calc indent for REST OF LINE (may start more blocks):
	    let s:curline = strpart(s:curline, blockend+strlen(endtag))
	    call s:CountITags()
	    if swtag && b:indent.block != 5
		let indent = b:indent.blocktagind + s:curind * &shiftwidth
		let s:newstate.baseindent = indent + s:nextrel * &shiftwidth
	    else
		let indent = s:Alien{b:indent.block}()
		let s:newstate.baseindent = b:indent.blocktagind + s:nextrel * &shiftwidth
	    endif
	    call extend(b:indent, s:newstate, "force")
	    return indent
	else
	    " block continues
	    " indent this line with alien method
	    let indent = s:Alien{b:indent.block}()
	    call extend(b:indent, s:newstate, "force")
	    return indent
	endif
    else
	" not within a block - within usual html
	let s:newstate.block = b:indent.block
	call s:CountITags()
	if swtag
	    let indent = b:indent.baseindent + s:curind * &shiftwidth
	    let s:newstate.baseindent = indent + s:nextrel * &shiftwidth
	else
	    let indent = b:indent.baseindent
	    let s:newstate.baseindent = indent + (s:curind + s:nextrel) * &shiftwidth
	endif
	call extend(b:indent, s:newstate, "force")
	return indent
    endif

endfunc "}}}

" IndHtmlLocal, clear cpo, Modeline: {{{1

com! -nargs=* IndHtmlLocal <args>
" Examples
" :IndHtmlLocal call s:IndAdder("html")
"   add an itag
"
" :IndHtmlLocal call s:NoIndAdder("a","html")
"   remove itags
"
" :IndHtmlLocal delfunc s:FreshState
"   on next :setf html, define functions again
"
" :IndHtmlLocal let s:usestate = 0
"   test performance with state ignored

let &cpo = s:cpo_save
unlet s:cpo_save

" vim:set fdm=marker ts=8:
