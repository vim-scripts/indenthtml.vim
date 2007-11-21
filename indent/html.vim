" Vim indent script
" General: "{{{
" File:		html.vim (Vimscript #2075)
" Author:	Andy Wokula, anwoku#yahoo*de (#* -> @.)
" Last Change:	2007 Nov 21
" Version:	0.3.2
" Vim Version:	Vim7
" Description:
"   improved version of the distributed html indent script
" - Based on:
"	indent/html.vim from J. Zellner (2006 Jun 05)
"	indent/css.vim from N. Weibull (2006 Dec 20)
" - indenting regions:
"	Blocktag : Indent-Expr
"	   <pre> : -1 (= keep indent)
"	<script> : 0		    if first line of block
"		 : cindent(v:lnum)  if attributes empty or contain "java"
"		 : -1		    else (vbscript, tcl, ...)
"	<style>  : 0		    if first line of block
"		 : GetCSSIndent()   else (v0.3)
"	<!-- --> : -1
" - speedup: uses a state to support indenting a range of lines; benefits of
"   Vim7, uses search() instead of searchpair()
" - more exact when checking tags in a line
" - per default no extra indent for <html>, <head>, <body>
" - no syntax dependencies
" Example:
"   2900 non-blank lines of http://www.weather.com/weather/local/USPA0372
"   without state: 11.75 sec (already much faster than the old script)
"   with state: 2.27 sec (again 5 times faster) (machine 1.2 GHz Athlon)
" Problems:
" - natural state problem: to reproduce,
"	indent line N with "=="
"	change line N with ">>"	    (no update of state)
"	indent line N+1 with "=="   (wrong indent)
"	indent line N+1 with "=="   (workaround to get correct indent)
" - attributes spanning over several lines (but occurs rarely in websites)
" - s:FreshState(): doesn't ignore a commented blocktag; nesting in general;
"   workaround: start indenting at a line for which s:FreshState() works ok
" Hmm:
" ? use of the term "blocktag"
" ? call "<!--" and "-->" tags
 "}}}
" Customization: "{{{
" :IndHtmlLocal {cmd}
"	change internals after loading the script, e.g. command is available
"	in after/indent/html.vim
"
" Examples:
" :IndHtmlLocal call s:IndAdder("body","head","tbody")
"	add tags "itags" that add an indent step.  The above command
"	restores defaults of the distributed script, that could formerly be
"	disabled with  :let g:html_indent_strict = 1
"
" :IndHtmlLocal call s:NoIndAdder("th","td","tr","tfoot","thead")
"	remove given itags (silently), this is like the former
"	:let g:html_indent_strict_table = 1
"
" :IndHtmlLocal let s:usestate = 0
"	test performance with state ignored (default 1)
"
" :IndHtmlLocal func! s:CSSIndent()
" :    return -1
" :endfunc
" :IndHtmlLocal let s:css1indent = -1	" default 0
"	disable the CSS-Indenter -- use indent -1 for <style> regions
"	(this is not very practical, just a demo of what can be done)
"
" :delfunc HtmlIndent
" :IndHtmlLocal let s:css1indent = 0
" :edit					" reload .html file
"	re-enable the CSS-Indenter during session
 "}}}

" Init Folklore: "{{{
if exists("b:did_indent")
    finish
endif
let b:did_indent = 1

setlocal indentexpr=HtmlIndent()
setlocal indentkeys=o,O,*<Return>,<>>,{,},!^F

let b:indent = {"lnum": -1}
let b:undo_indent = "set inde< indk<| unlet b:indent"

" Load Once:
if exists("*HtmlIndent")
    finish
endif

let s:cpo_save = &cpo
set cpo-=C
 "}}}

" Init Script Vars  "{{{
let s:usestate = 1
let s:css1indent = 0
" not to be changed:
let s:endtags = [0,0,0,0,0,0,0,0]   " some places unused
let s:newstate = {}
let s:countonly = 0
 "}}}
func! s:IndAdder(tag, ...) "{{{
    if a:0 == 0
	let val = 1
    elseif a:1 >= 2 && a:1 < 10
	let val = a:1
	let s:endtags[val-2] = "</".a:tag.">"
    else
	call s:IndAdder(a:tag)
	call map(copy(a:000), 's:IndAdder(v:val)')
	return
    endif
    let s:indent_tags[a:tag] = val
    let s:indent_tags['/'.a:tag] = -val
endfunc "}}}
func! s:NoIndAdder(...) "{{{
    " remove itags (protect blocktags from being removed)
    for itag in a:000
	if !has_key(s:indent_tags, itag) || s:indent_tags[itag] != 1
	    continue
	endif
	unlet s:indent_tags[itag]
	if itag =~ '^\w\+$'
	    unlet s:indent_tags["/".itag]
	endif
    endfor
endfunc "}}}
" IndAdder Calls: {{{
if !exists("s:indent_tags")
    let s:indent_tags = {}
endif
call s:IndAdder('a', 'abbr', 'acronym', 'address', 'b', 'bdo', 'big')
call s:IndAdder('blockquote', 'button', 'caption', 'center', 'cite', 'code')
call s:IndAdder('colgroup', 'del', 'dfn', 'dir', 'div', 'dl', 'em')
call s:IndAdder('fieldset', 'font', 'form', 'frameset', 'h1', 'h2', 'h3')
call s:IndAdder('h4', 'h5', 'h6')
" call s:IndAdder('html')
call s:IndAdder('i', 'iframe', 'ins', 'kbd', 'label', 'legend', 'map')
call s:IndAdder('menu', 'noframes', 'noscript', 'object', 'ol', 'optgroup')
call s:IndAdder('q', 's', 'samp', 'select', 'small', 'span', 'strong')
call s:IndAdder('sub', 'sup', 'table', 'textarea', 'title', 'tt', 'u', 'ul')
call s:IndAdder('var')
call s:IndAdder('th', 'td', 'tr', 'tfoot', 'thead')
"}}}
" Block Tags: contain alien content "{{{
call s:IndAdder('pre', 2)
call s:IndAdder('script', 3)
call s:IndAdder('style', 4)
" Exception: handle comment delimiters <!--...--> like block tags
let s:indent_tags["<!--"] = 5
let s:indent_tags['-->'] = -5
let s:endtags[5-2] = "-->"
"}}}

func! s:CountITags(...) "{{{

    " relative indent steps for current line [unit &sw]:
    let s:curind = 0
    " relative indent steps for next line [unit &sw]:
    let s:nextrel = 0

    if a:0==0
	let s:block = s:newstate.block
	let tmpline = substitute(s:curline, '<\zs\/\=\w\+\>\|<!--\|-->', '\=s:CheckTag(submatch(0))', 'g')
	if s:block == 3
	    let s:newstate.scripttype = s:GetScriptType(matchstr(tmpline, '\C.*<SCRIPT\>\zs[^>]*'))
	endif
	let s:newstate.block = s:block
    else
	let s:block = 0		" assume starting outside of a block
	let s:countonly = 1	" don't change state
	let tmpline = substitute(s:altline, '<\zs\/\=\w\+\>\|<!--\|-->', '\=s:CheckTag(submatch(0))', 'g')
	let s:countonly = 0
    endif
endfunc "}}}
func! s:CheckTag(itag) "{{{
    " "tag" or "/tag" or "<!--" or "-->"
    let ind = get(s:indent_tags, a:itag)
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
	let s:newstate.blocklnr = v:lnum
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
	let state.block = s:indent_tags[blocktag]
	if state.block == 3
	    let state.scripttype = s:GetScriptType(matchstr(tagline, '\>[^>]*', stopcol))
	endif
	let state.blocklnr = stopline
	" check preceding tags in the line:
	let s:altline = tagline[: stopcol-2]
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
	" TODO check tags that follow "-->"
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
    if prevnonblank(v:lnum-1) == b:indent.blocklnr
	" indent for the first line after <script>
	return 0
    endif
    if b:indent.scripttype == "javascript"
	return cindent(v:lnum)
    else
	return -1
    endif
endfunc "}}}
func! s:Alien4() "{{{
    " <style>
    if prevnonblank(v:lnum-1) == b:indent.blocklnr
	" indent for first content line
	return s:css1indent
    endif
    return s:CSSIndent()
endfunc

func! s:CSSIndent() "{{{
    " adopted $VIMRUNTIME/indent/css.vim
    if getline(v:lnum) =~ '^\s*[*}]'
	return cindent(v:lnum)
    endif
    let minline = b:indent.blocklnr
    let pnum = s:css_prevnoncomment(v:lnum - 1, minline)
    if pnum <= minline
	" < is to catch errors
	" indent for first content line after comments
	return s:css1indent
    endif
    let ind = indent(pnum) + s:css_countbraces(pnum, 1) * &sw
    let pline = getline(pnum)
    if pline =~ '}\s*$'
	let ind -= (s:css_countbraces(pnum, 0) - (pline =~ '^\s*}')) * &sw
    endif
    return ind
endfunc "}}}
func! s:css_prevnoncomment(lnum, stopline) "{{{
    " caller starts from a line a:lnum-1 that is not a comment
    let lnum = prevnonblank(a:lnum)
    let ccol = match(getline(lnum), '\*/')
    if ccol < 0
	return lnum
    endif
    call cursor(lnum, ccol+1)
    let lnum = search('/\*', 'bW', a:stopline)
    if indent(".") == virtcol(".")-1
	return prevnonblank(lnum-1)
    else
	return lnum
    endif
endfunc "}}}
func! s:css_countbraces(lnum, count_open) "{{{
    let brs = substitute(getline(a:lnum),'[''"].\{-}[''"]\|/\*.\{-}\*/\|/\*.*$\|[^{}]','','g')
    let n_open = 0
    let n_close = 0
    for brace in split(brs, '\zs')
	if brace == "{"
	    let n_open += 1
	elseif brace == "}"
	    if n_open > 0
		let n_open -= 1
	    else
		let n_close += 1
	    endif
	endif
    endfor
    return a:count_open ? n_open : n_close
endfunc "}}}

"}}}
func! s:Alien5() "{{{
    " <!-- -->
    return -1
endfunc "}}}

func! HtmlIndent() "{{{
    let s:curline = tolower(getline(v:lnum))

    let s:newstate = {}
    let s:newstate.lnum = v:lnum

    " is the first non-blank in the line the start of a tag?
    let swtag = match(s:curline, '^\s*<') >= 0

    if prevnonblank(v:lnum-1) == b:indent.lnum && s:usestate
	" use state (continue from previous line)
    else
	" start over (know nothing)
	let b:indent = s:FreshState(v:lnum)
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
func! s:Ihlc(arl, cml, pos)
    " useful completions for IndHtmlLocal
    return "let s:css1indent = 0\nfunc! s:CSSIndent()\nlet s:usestate = 1\ncall s:NoIndAdder(\ncall s:IndAdder("
endfunc

com! -nargs=* -complete=custom,s:Ihlc IndHtmlLocal <args>

let &cpo = s:cpo_save
unlet s:cpo_save

" vim:set fdm=marker ts=8:
